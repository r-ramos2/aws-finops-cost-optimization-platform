import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import json

ce_client = boto3.client('ce')
sns_client = boto3.client('sns')

def lambda_handler(event, context):
    """Detect cost anomalies by comparing to previous week"""
    try:
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=1)
        week_ago_start = end_date - timedelta(days=8)
        week_ago_end = end_date - timedelta(days=7)
        
        # Current costs
        current_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['UnblendedCost'],
            GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
        )
        
        # Previous week costs
        previous_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': week_ago_start.strftime('%Y-%m-%d'),
                'End': week_ago_end.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['UnblendedCost'],
            GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
        )
        
        # Calculate totals and by-service
        current_total = Decimal('0')
        current_by_service = {}
        
        for result in current_response['ResultsByTime']:
            for group in result['Groups']:
                service = group['Keys'][0]
                amount = Decimal(group['Metrics']['UnblendedCost']['Amount'])
                current_total += amount
                current_by_service[service] = amount
        
        previous_total = Decimal('0')
        previous_by_service = {}
        
        for result in previous_response['ResultsByTime']:
            for group in result['Groups']:
                service = group['Keys'][0]
                amount = Decimal(group['Metrics']['UnblendedCost']['Amount'])
                previous_total += amount
                previous_by_service[service] = amount
        
        # Detect anomalies
        threshold = Decimal(os.environ['ANOMALY_THRESHOLD']) / 100
        anomalies = []
        
        # Check total
        if previous_total > 0:
            total_change = (current_total - previous_total) / previous_total
            if total_change > threshold:
                anomalies.append({
                    'type': 'Overall',
                    'current': current_total,
                    'previous': previous_total,
                    'change_percent': total_change * 100
                })
        
        # Check by service
        for service in current_by_service:
            current = current_by_service[service]
            previous = previous_by_service.get(service, Decimal('0'))
            
            if previous > Decimal('1') and current > Decimal('1'):
                change = (current - previous) / previous
                if change > threshold:
                    anomalies.append({
                        'type': 'Service',
                        'service': service,
                        'current': current,
                        'previous': previous,
                        'change_percent': change * 100
                    })
        
        # Alert if anomalies found
        if anomalies:
            message = f"Cost Anomaly Detected - {end_date.strftime('%Y-%m-%d')}\n\n"
            
            for anomaly in sorted(anomalies, key=lambda x: x['change_percent'], reverse=True):
                if anomaly['type'] == 'Overall':
                    message += f"⚠️ Overall costs increased {anomaly['change_percent']:.1f}%\n"
                    message += f"  Previous: ${anomaly['previous']:.2f}\n"
                    message += f"  Current: ${anomaly['current']:.2f}\n\n"
                else:
                    message += f"⚠️ {anomaly['service']} increased {anomaly['change_percent']:.1f}%\n"
                    message += f"  Previous: ${anomaly['previous']:.2f}\n"
                    message += f"  Current: ${anomaly['current']:.2f}\n\n"
            
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject="⚠️ Cost Anomaly Detected",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'anomalies_found': len(anomalies),
                'details': [
                    {k: float(v) if isinstance(v, Decimal) else v for k, v in a.items()}
                    for a in anomalies
                ]
            })
        }
        
    except Exception as e:
        print(f"Error detecting anomalies: {str(e)}")
        raise
