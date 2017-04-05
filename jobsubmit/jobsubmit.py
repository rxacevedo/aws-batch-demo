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
        batch.submit_job(
            jobName=event['jobName'],
            jobQueue=event['jobQueue'],
            jobDefinition=event['jobDefinition'],
            parameters=parameters
        )
    except Exception as e:
        logging.error('Failed to submit job.')
        logging.error(e)
        exit(1)

    return {
        'Body': 'Job submitted.'
    }