import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handles an SNS message from a CloudWatch alarm.
    """
    logger.info("Received event: %s", json.dumps(event))
    
    # SNS messages are base64 encoded in the event
    for record in event.get('Records', []):
        message = record['Sns']['Message']
        logger.info("ALARM MESSAGE: %s", message)
        
        # --- EXTEND THIS SECTION FOR REMEDIATION ---
        # Example: Parse the alarm message and take action.
        # if "5xx-errors" in message:
        #     # Could call boto3 to restart a service, scale up, etc.
        #     pass
        # -------------------------------------------
    
    return {
        'statusCode': 200,
        'body': json.dumps('Monitoring event processed.')
    }