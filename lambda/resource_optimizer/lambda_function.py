import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import json

ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')

def lambda_handler(event, context):
    """Find optimization opportunities"""
    try:
        recommendations = []
        total_savings = Decimal('0')
        
        # 1. Unattached EBS volumes
        volumes = ec2_client.describe_volumes(
            Filters=[{'Name': 'status', 'Values': ['available']}]
        )
        
        for volume in volumes['Volumes']:
            # Estimate cost: $0.10/GB-month for gp2
            size = Decimal(str(volume['Size']))
            monthly_cost = size * Decimal('0.10')
            total_savings += monthly_cost
            
            recommendations.append({
                'type': 'Unattached EBS Volume',
                'resource_id': volume['VolumeId'],
                'size_gb': volume['Size'],
                'monthly_savings': monthly_cost,
                'action': 'Delete if no longer needed'
            })
        
        # 2. Stopped EC2 instances (still incur EBS costs)
        instances = ec2_client.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['stopped']}]
        )
        
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                # Estimate EBS costs
                ebs_cost = Decimal('0')
                for mapping in instance.get('BlockDeviceMappings', []):
                    if 'Ebs' in mapping:
                        volume_id = mapping['Ebs']['VolumeId']
                        vol = ec2_client.describe_volumes(VolumeIds=[volume_id])
                        size = Decimal(str(vol['Volumes'][0]['Size']))
                        ebs_cost += size * Decimal('0.10')
                
                if ebs_cost > Decimal('0'):
                    total_savings += ebs_cost
                    recommendations.append({
                        'type': 'Stopped EC2 Instance',
                        'resource_id': instance['InstanceId'],
                        'instance_type': instance['InstanceType'],
                        'monthly_savings': ebs_cost,
                        'action': 'Terminate if no longer needed, or create AMI and terminate'
                    })
        
        # 3. Old snapshots (>90 days)
        snapshots = ec2_client.describe_snapshots(OwnerIds=['self'])
        old_date = datetime.now() - timedelta(days=90)
        
        for snapshot in snapshots['Snapshots']:
            if snapshot['StartTime'].replace(tzinfo=None) < old_date:
                # Estimate: $0.05/GB-month for snapshots
                size = Decimal(str(snapshot['VolumeSize']))
                monthly_cost = size * Decimal('0.05')
                total_savings += monthly_cost
                
                recommendations.append({
                    'type': 'Old Snapshot',
                    'resource_id': snapshot['SnapshotId'],
                    'age_days': (datetime.now() - snapshot['StartTime'].replace(tzinfo=None)).days,
                    'size_gb': snapshot['VolumeSize'],
                    'monthly_savings': monthly_cost,
                    'action': 'Delete if backup no longer needed'
                })
        
        # Send report if savings found
        min_threshold = Decimal(os.environ['MIN_SAVINGS_THRESHOLD'])
        
        if total_savings >= min_threshold:
            message = f"Resource Optimization Opportunities\n"
            message += f"Total Potential Monthly Savings: ${total_savings:.2f}\n\n"
            
            # Sort by savings
            recommendations.sort(key=lambda x: x['monthly_savings'], reverse=True)
            
            for rec in recommendations[:20]:  # Top 20
                message += f"• {rec['type']}\n"
                message += f"  ID: {rec['resource_id']}\n"
                message += f"  Savings: ${rec['monthly_savings']:.2f}/month\n"
                message += f"  Action: {rec['action']}\n\n"
            
            if len(recommendations) > 20:
                message += f"\n...and {len(recommendations)-20} more opportunities\n"
            
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f"💰 Resource Optimization: ${total_savings:.2f}/mo savings available",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'total_recommendations': len(recommendations),
                'total_monthly_savings': float(total_savings),
                'top_recommendations': [
                    {k: float(v) if isinstance(v, Decimal) else v for k, v in rec.items()}
                    for rec in recommendations[:10]
                ]
            })
        }
        
    except Exception as e:
        print(f"Error finding optimization opportunities: {str(e)}")
        raise
