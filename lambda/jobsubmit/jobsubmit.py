import json
import logging

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
logging.basicConfig()
log.setLevel(logging.INFO)


class ValidationError(Exception):
    pass


def invoke(event, context):
    batch = boto3.client('batch')

    # TODO: This could be better
    direct_input = True if 'jobs' in event else False
    file_input = True if 's3_path' in event else False

    # Raises exception when validation fails
    validate_event(direct_input, file_input)

    if file_input:
        jobs = s3_spec(event)
    elif direct_input:
        jobs = direct_input_spec(event)
    else:
        raise RuntimeError('This code path should not have been reached, check validation logic above.')

    try:

        submitted = dict()
        ordered = submission_order(jobs=jobs)

        for job in ordered:
            if 'dependsOn' in job:
                dependencies = [dict(jobId=job_id) for job_name, job_id in submitted.items()
                                if job_name in job['dependsOn']]
            else:
                dependencies = []
            job_id = submit(batch, job, dependencies=dependencies)
            submitted[job['jobName']] = job_id

        return {
            'Body': 'Job(s) submitted: {}'.format(submitted)
        }

    except Exception as e:
        logging.error('Failed to submit job.')
        raise e


def submit(client, job, dependencies=[]):
    """
    Submit a batch job to the batch. Returns the job ID issued by the scheduler.
    :param dependencies: An optional list of dependencies (job IDs)
    :param client:
    :param job:
    :return:
    """
    if 'parameters' in job:
        parameters = job['parameters']
    else:
        parameters = {}

    submit_parameters = dict(
        jobName=job['jobName'],
        jobQueue=job['jobQueue'],
        jobDefinition=job['jobDefinition'],
        parameters={k: str(v) for k, v in parameters.items()},
    )

    if dependencies:
        submit_parameters['dependsOn'] = dependencies
    res = client.submit_job(**submit_parameters)

    if res['ResponseMetadata']['HTTPStatusCode'] == 200:  # Success
        return res['jobId']
    else:
        raise ClientError('Error submitting job for job: {}'.format(json.dumps(job)))


def validate_event(direct_input, file_input):
    """
    Validate this scenario
    :param direct_input: 
    :param file_input: 
    :return: 
    """
    if direct_input and file_input:
        raise ValidationError("Error validating event: 'jobs' and 's3_path' cannot both be set.")
    if not direct_input and not file_input:
        raise ValidationError("Error validating event: One of 'jobs' or 's3_path' must be specified.")


def direct_input_spec(event):
    job_spec = event['jobs']
    return job_spec


def s3_spec(event):
    try:
        s3 = boto3.client('s3')
        bucket = event['s3_path'].split('//')[1].split('/')[0]
        key = '/'.join(event['s3_path'].split('//')[1].split('/')[1:])
        log.info('Bucket: {}, key: {}'.format(bucket, key))
        res = s3.get_object(Bucket=bucket, Key=key)
        job_spec = res['Body'].read()
    except ClientError as e:
        log.error(e)
    return job_spec


def submission_order(jobs):
    """
    Returns a copy of job_spec sorted in the order which the jobs need to be submitted in
    :param jobs: 
    :return:
    """
    # Don't modify the input
    clone = list(jobs)
    ordered, submitted = list(), list()

    # Loop until we've worked through/emptied the job list
    while len(clone) > 0:
        for job in clone:

            job_name = job['jobName']

            if 'dependsOn' in job:
                dependencies = job['dependsOn']
                satisfied_deps = [dep for dep in dependencies if dep in submitted]
                log.info('Satisfied dependencies for {}: {}'.format(job_name, satisfied_deps))
                if sorted(satisfied_deps) == sorted(dependencies):  # TODO: Just do len()?
                    submitted.append(job_name)
                    ordered.append(job)
                    clone.remove(job)
                else:
                    log.info('Skipping job {}, dependencies remain: {}'.format(
                        job_name,
                        [dep for dep in dependencies if dep not in satisfied_deps]
                    ))
                    continue
            else:
                ordered.append(job)
                submitted.append(job_name)
                clone.remove(job)

    return ordered
