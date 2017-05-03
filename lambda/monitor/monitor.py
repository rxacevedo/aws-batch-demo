import json
import logging
import os
import time
from datetime import datetime

import boto3
from botocore.exceptions import ClientError
from enum import Enum

import requests
from requests.exceptions import HTTPError, ConnectionError, SSLError, Timeout, RequestException

log = logging.getLogger()
logging.basicConfig()
log.setLevel(logging.INFO)

NAMESPACE = os.environ['METRIC_NAMESPACE']
METRIC_NAME = os.environ['METRIC_NAME']
INTERVAL = int(os.environ['INTERVAL'])  # Seconds
ITERS = int(os.environ['ITERS'])
SCALE_CAP = int(os.environ['SCALE_CAP'])
AUTOSCALING_POLICY_NAME = os.environ['AUTOSCALING_POLICY_NAME']
AUTOSCALING_GROUP_NAME = os.environ['AUTOSCALING_GROUP_NAME']
SLACK_WEBHOOK_URL = os.environ['SLACK_WEBHOOK_URL']

SCALING_NEEDED_MESSAGE = 'Queue: {}, available compute: {}, {} required {}'
SCALING_CAPPED_MESSAGE = ':exclamation: Queue: {}, available compute: {}, scaling is needed but capped by SCALE_LIMIT: {} :exclamation:'


class ScalingType(Enum):
    SCALE_OUT = 1
    NONE = 0
    SCALE_IN = -1


def available_compute(ecs, cluster_arn):
    """
    Reports the current capacity for the specified ECS cluster ARN based on the number of registered nodes.
    :param ecs: The ECS client
    :param cluster_arn: The full ARN of the ECS Cluster being queried
    :return: The number of available/registered compute nodes.
    """
    try:
        res = ecs.describe_clusters(clusters=[cluster_arn])
        cluster_list = res['clusters']
        node_count = cluster_list[0]['registeredContainerInstancesCount']
        return node_count
    except ClientError as e:
        log.error(e)


def ecs_cluster(batch, environment):
    """
    Reports the ECS Cluster ARN corresponding to an AWS Batch compute environment.
    :param batch: The Batch client
    :param environment: The compute environment name
    :return: The full ARN of the ECS cluster created for this Batch environment
    """
    try:
        res = batch.describe_compute_environments(computeEnvironments=[environment])
        env_list = res['computeEnvironments']
        ecs_cluster_arn = env_list[0]['ecsClusterArn']
        return ecs_cluster_arn
    except ClientError as e:
        log.error(e)


def queue_size(batch, job_queue, job_status, max_results=100):
    """
    Gauges a Batch job queue's size based on the number of SUBMITTED/RUNNABLE jobs.
    :param batch: The Batch client
    :param job_queue: The name of the job queue being queried
    :return:
    """
    try:

        runnable = batch.list_jobs(
            jobQueue=job_queue,
            jobStatus=job_status,
            maxResults=max_results
        )

        size = len(runnable['jobSummaryList'])
        return size

    except ClientError as e:
        log.error(e)


def post_cloudwatch_metric(cloudwatch, dimensions, value):
    """
    Posts a single metric value/datum to CloudWatch, reflecting whether or not the compute
    environment for this request is in need of scale-out.
    :param cloudwatch: The CloudWatch client
    :param job_queue: The job queue being inspected to determine whether or not scale-out
    is required.
    :param scale_out_needed: A boolean value specifying if scale-out is needed.
    :return: None
    """
    try:

        cloudwatch.put_metric_data(
            Namespace=NAMESPACE,
            MetricData=[
                {
                    'MetricName': METRIC_NAME,
                    'Dimensions': dimensions,
                    'Timestamp': datetime.utcnow(),
                    'Value': value
                }
            ]
        )

    except ClientError as e:
        log.error(e)
        raise e


def update_autoscaling_policy(client, scaling_adjustment):
    try:
        client.put_scaling_policy(
            AutoScalingGroupName=AUTOSCALING_GROUP_NAME,
            PolicyName=AUTOSCALING_POLICY_NAME,
            ScalingAdjustment=scaling_adjustment,
            AdjustmentType='ExactCapacity',
            Cooldown=300
        )
    except ClientError as e:
        log.error(e)
        raise e


def run(event, context):
    """
    Checks queue size and compute size. If there are more tasks in queue than instances, scale out.
    :param event:
    :param context:
    :return:
    """

    # TODO: Since we are using autoscaling policies to drive scale-in/scale-out, this function should fail
    # and post an error to Slack if the ASG in the environment variables does not have a policy attached
    # to it
    log.info('Starting monitor')

    batch = boto3.client('batch')
    ecs = boto3.client('ecs')
    cloudwatch = boto3.client('cloudwatch')
    autoscaling = boto3.client('autoscaling')

    scale_out_needed_vals, scale_in_needed_vals = list(), list()

    for i in range(1, ITERS + 1):

        log.info('Iter {} of {}'.format(i, ITERS))

        target, adjusted = compute_target_capacity(batch, event)

        # log.info('Target equation: {} + {}'.format(runnable, running))
        # log.info('Adjusted target equation: {} - ({} - {})'.format(target, SCALE_CAP, target))

        # TODO: Compute environments can be determined based on the requested job queue
        cluster_arn = ecs_cluster(batch, event['computeEnvironment'])
        compute = available_compute(ecs, cluster_arn)

        log.info('Compute: {} / target: {} / adjusted target = {}'.format(
            compute, target, adjusted
        ))

        scaling_type = determine_scaling(adjusted, compute)

        # TODO: If scale-in is "needed," then we should ensure that only inactive nodes
        # (those not currently running tasks) are not affected by scale-in. This can be
        # done by either:
        # 1. Setting an ECS node to DRAINING, then de-registering from the ASG and
        # adjusting capacity accordingly (more effective, more time-consuming)
        #
        # 2. Preventing scale-in from occuring until all tasks have been worked. (less
        # effective, but also requires less time)

        if i % 2 == 0:
            # Warning scenario
            if scaling_type == ScalingType.NONE and target > SCALE_CAP:
                notify_slack(message='Target capacity: {} greater than scaling limit: {}.'.format(
                    target,
                    SCALE_CAP))
            elif scaling_type == ScalingType.NONE and target <= compute:
                log.info('Capacity is healthy.')
                # else:
                #     log.info('!!! UNKNOWN SCENARIO !!!')
                #     notify_slack(message='Unknown scaling scenario - compute: {}, target: {}, adjusted target: {}'.format(
                #         compute, target, adjusted
                #     ))

        # We can scale out
        if scaling_type == ScalingType.SCALE_OUT:
            log.info(
                'Scaling out, adjusted target: {}, scale cap: {}. Updating autoscaling policy: {} :arrow_up:'.format(
                    adjusted,
                    SCALE_CAP,
                    AUTOSCALING_POLICY_NAME))
            update_autoscaling_policy(client=autoscaling, scaling_adjustment=adjusted)
        # We can scale in
        elif scaling_type == ScalingType.SCALE_IN:
            notify_slack(message='Reducing target autoscaling capacity to {} :arrow_down:'.format(adjusted))
            update_autoscaling_policy(client=autoscaling, scaling_adjustment=adjusted)

        metric_value = scaling_type.value

        dimensions = [
            {
                'Name': 'JobQueue',
                'Value': event['jobQueue']
            },
            {
                'Name': 'ComputeEnvironment',
                'Value': event['computeEnvironment']
            }
        ]

        post_cloudwatch_metric(cloudwatch, dimensions=dimensions, value=metric_value)

        log.info('Sleeping for {} seconds...'.format(INTERVAL))
        time.sleep(INTERVAL)  # We should sleep until we've exceeded ITERS

    log.info('Exiting')

    return {
        'target': target,
        'compute': compute,
        'scalingAction': str(scaling_type)
    }


def compute_target_capacity(batch, event):
    """
    Computes the target cluster capacity based on queue size.
    :param batch:
    :param event:
    :return:
    """
    runnable = queue_size(batch, event['jobQueue'], job_status='RUNNABLE')
    running = queue_size(batch, event['jobQueue'], job_status='RUNNING')
    target = runnable + running
    adjusted = SCALE_CAP if target > SCALE_CAP else target

    return target, adjusted


def determine_scaling(adjusted, compute):
    """
    Determine the scaling action (enum type) based on current compute capacity and adjusted compute target.
    :param adjusted:
    :param compute:
    :return:
    """
    scale_out_needed = True if adjusted > compute else False
    # THIS IS IMPORTANT - only scale in when adjusted/queue is 0
    scale_in_needed = True if adjusted == 0 and compute > 0 else False

    # notify_slack(message='Scale-out needed? {}'.format(scale_out_needed))
    # notify_slack(message='Scale-in needed? {}'.format(scale_in_needed))

    return ScalingType.SCALE_OUT if scale_out_needed \
        else ScalingType.SCALE_IN if scale_in_needed \
        else ScalingType.NONE


def notify_slack(message):
    """
    Send a notification to the configured Slack webhook.
    :param message:
    :return:
    """
    data = dict(
        text=message,
        username='monitor-bot',
        icon_emoji=':passenger_ship:'
    )

    logging.info('Logging to Slack')
    # log.debug(message)

    try:
        requests.post(SLACK_WEBHOOK_URL, data=json.dumps(data))
    except (HTTPError, ConnectionError, SSLError, Timeout) as e:
        log.error('Could not talk to Slack!')
        log.error(e)
    except RequestException as e:
        log.error('General exception:')
        log.error(e)
