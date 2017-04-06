import logging

import boto3

log = logging.getLogger()
logging.basicConfig()
log.setLevel(logging.INFO)

def invoke(event, context):

    log.info('Logging event')
    log.info(event)
    log.info('Logging context')
    log.info(context)

    try:
        if 'parameters' in event:
            parameters = event['parameters']
        else:
            parameters = {}

        batch = boto3.client('batch')
        res = batch.submit_job(
            jobName=event['jobName'],
            jobQueue=event['jobQueue'],
            jobDefinition=event['jobDefinition'],
            parameters=parameters
        )

        return {
            'Body': 'Job submitted: {job_name} // {job_id}'.format(job_name=res['jobName'], job_id=res['jobId'])
        }

    except Exception as e:
        logging.error('Failed to submit job.')
        logging.error(e)
