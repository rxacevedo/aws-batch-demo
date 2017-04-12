import json
import logging
import os
import time
from datetime import datetime

import boto3
from botocore.exceptions import ClientError

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
SLACK_WEBHOOK_URL = os.environ['SLACK_WEBHOOK_URL']

SCALING_NEEDED_MESSAGE = 'Queue: {}, available compute: {}, {} required {}'
SCALING_CAPPED_MESSAGE = ':exclamation: Queue: {}, available compute: {}, scaling is needed but capped by SCALE_LIMIT: {} :exclamation:'


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


def queue_size(batch, job_queue):
    """
    Gauges a Batch job queue's size based on the number of SUBMITTED/RUNNABLE jobs.
    :param batch: The Batch client
    :param job_queue: The name of the job queue being queried
    :return:
    """
    try:

        # submitted = batch.list_jobs(
        #     jobQueue=job_queue,
        #     jobStatus='SUBMITTED',
        #     maxResults=100
        # )

        runnable = batch.list_jobs(
            jobQueue=job_queue,
            jobStatus='RUNNABLE',
            maxResults=100
        )

        # size = len(submitted['jobSummaryList'] + runnable['jobSummaryList'])

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


def run(event, context):
    """
    Checks queue size and compute size. If there are more tasks in queue than instances, scale out.
    :param event:
    :param context:
    :return:
    """

    log.info('Starting monitor')

    batch = boto3.client('batch')
    ecs = boto3.client('ecs')
    cloudwatch = boto3.client('cloudwatch')
    scale_out_needed_vals, scale_in_needed_vals = list(), list()

    for i in range(1, ITERS + 1):

        log.info('Iter {} of {}'.format(i, ITERS))

        queue = queue_size(batch, event['jobQueue'])
        # TODO: Compute environments can be determined based on the requested job queue
        cluster_arn = ecs_cluster(batch, event['computeEnvironment'])
        compute = available_compute(ecs, cluster_arn)

        log.info('Queue: {}, available compute: {}'.format(queue, compute))

        scale_out_needed = True if queue > compute else False
        scale_out_needed_vals.append(scale_out_needed)

        # TODO: If scale-in is "needed," then we should ensure that only inactive nodes
        # (those not currently running tasks) are not affected by scale-in. This can be
        # done by either:
        # 1. Setting an ECS node to DRAINING, then de-registering from the ASG and
        # adjusting capacity accordingly (more effective, more time-consuming)
        #
        # 2. Preventing scale-in from occuring until all tasks have been worked. (less
        # effective, but also requires less time)
        #
        scale_in_needed = True if queue < compute else False
        scale_in_needed_vals.append(scale_in_needed)

        if i % 2 == 0:
            if scale_out_needed:
                notify_slack('scale-out', compute, queue)
            if scale_in_needed:
                notify_slack('scale-in', compute, queue)

        metric_value = 1 if scale_out_needed else -1 if scale_in_needed else 0

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

        time.sleep(INTERVAL)  # We should sleep until we've exceeded ITERS

    log.info('Exiting')

    return {
        'queue': queue,
        'compute': compute,
        'scaleOutNeeded': '|'.join([str(v) for v in scale_out_needed_vals]),
        'scaleInNeeded': '|'.join([str(v) for v in scale_in_needed_vals])
    }


def notify_slack(scaling_type, compute, queue):
    message = scaling_message(compute, queue, scaling_type)

    log.info(message)

    data = dict(
        text=message,
        username='monitor-bot',
        icon_emoji=':passenger_ship:'
    )
    logging.info('Logging to Slack')
    try:
        requests.post(SLACK_WEBHOOK_URL, data=json.dumps(data))
    except (HTTPError, ConnectionError, SSLError, Timeout) as e:
        log.error('Could not talk to Slack!')
        log.error(e)
    except RequestException as e:
        log.error('General exception:')
        log.error(e)


def scaling_message(compute, queue, scaling_type):
    if scaling_type == 'scale-out':
        icon_emoji = ':arrow_up:'
        message = SCALING_NEEDED_MESSAGE.format(queue, compute, scaling_type, icon_emoji)
    elif scaling_type == 'scale-in':
        icon_emoji = ':arrow_down:'
        message = SCALING_NEEDED_MESSAGE.format(queue, compute, scaling_type, icon_emoji)
    else:
        icon_emoji = ':question:'
        message = SCALING_NEEDED_MESSAGE.format(queue, compute, scaling_type, icon_emoji)

    if scaling_type == 'scale-out' and str(compute) == SCALE_CAP:
        icon_emoji = ':exclamation:'
        message = SCALING_CAPPED_MESSAGE.format(queue, compute, SCALE_CAP)

    return message
