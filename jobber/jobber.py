import boto3
import logging
from botocore.exceptions import ClientError
from datetime import datetime
import time

log = logging.getLogger()
logging.basicConfig()
log.setLevel(logging.INFO)

NAMESPACE = 'Custom'
INTERVAL = 15  # Seconds
ITERS = 4


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


def post_cloudwatch_metric(cloudwatch, job_queue, scale_out_needed):
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
                    'MetricName': 'ScaleOutFactor',
                    'Dimensions': [
                        {
                            'Name': 'JobQueue',
                            'Value': job_queue
                        },
                    ],
                    'Timestamp': datetime.utcnow(),
                    'Value': 1 if scale_out_needed else 0
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

    log.info('Starting jobber')

    batch = boto3.client('batch')
    ecs = boto3.client('ecs')
    cloudwatch = boto3.client('cloudwatch')
    scale_out_needed_vals = list()

    for i in range(ITERS):

        log.info('Iter {} of {}'.format(i, ITERS))

        queue = queue_size(batch, event['jobQueue'])
        # TODO: Compute environments can be determined based on the requested job queue
        cluster_arn = ecs_cluster(batch, event['computeEnvironment'])
        compute = available_compute(ecs, cluster_arn)

        log.info('Queue: {}, available compute: {}'.format(queue, compute))

        scale_out_needed = True if queue > compute else False
        scale_out_needed_vals.append(scale_out_needed)

        if scale_out_needed:
            log.info('Queue size is greater than available compute, scale-out required.')

        post_cloudwatch_metric(cloudwatch, event['jobQueue'], scale_out_needed)

        time.sleep(INTERVAL)  # We should sleep until we've exceeded ITERS

    log.info('Exiting')

    return {
        'queue': queue,
        'compute': compute,
        'scaleOutNeeded': '|'.join([str(v) for v in scale_out_needed_vals])
    }
