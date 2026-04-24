import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import json

ce_client = boto3.client('ce')
sns_client = boto3.client('sns')

def lambda_handler(event, context):
    """Daily cost report with budget tracking"""
    try:
        # Get cost data
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=1)
        month_start = end_date.replace(day=1)
        
        # Yesterday's costs
        daily_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['UnblendedCost'],
            GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
        )
        
        # Month-to-date costs
        mtd_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': month_start.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost']
        )
        
        # Parse results
        daily_total = Decimal('0')
        service_costs = []
        
        for result in daily_response['ResultsByTime']:
            for group in result['Groups']:
                service = group['Keys'][0]
                amount = Decimal(group['Metrics']['UnblendedCost']['Amount'])
                daily_total += amount
                if amount > Decimal('0.01'):
                    service_costs.append((service, amount))
        
        service_costs.sort(key=lambda x: x[1], reverse=True)

        mtd_results = mtd_response.get('ResultsByTime') or []
        if not mtd_results:
            mtd_total = Decimal('0')
        else:
            mtd_total = Decimal(mtd_results[0]['Total']['UnblendedCost']['Amount'])
        monthly_budget = Decimal(os.environ['MONTHLY_BUDGET'])
        budget_percent = (mtd_total / monthly_budget * 100) if monthly_budget > 0 else 0
        
        # Build report
        report = f"""AWS Cost Report - {end_date.strftime('%Y-%m-%d')}
        
Yesterday's Cost: ${daily_total:.2f}
Month-to-Date: ${mtd_total:.2f}
Monthly Budget: ${monthly_budget:.2f}
Budget Used: {budget_percent:.1f}%

Top Services (Yesterday):
"""
        
        for service, cost in service_costs[:10]:
            report += f"  • {service}: ${cost:.2f}\n"
        
        if budget_percent > 90:
            report += "\n⚠️ WARNING: Budget utilization above 90%"
        
        # Send report
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"AWS Cost Report - {end_date.strftime('%Y-%m-%d')}",
            Message=report
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'daily_cost': float(daily_total),
                'mtd_cost': float(mtd_total),
                'budget_percent': float(budget_percent)
            })
        }
        
    except Exception as e:
        print(f"Error generating cost report: {str(e)}")
        raise
