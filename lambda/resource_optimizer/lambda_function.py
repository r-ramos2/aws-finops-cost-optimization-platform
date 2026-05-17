import boto3
import os
from datetime import datetime, timedelta, timezone
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
        volume_paginator = ec2_client.get_paginator('describe_volumes')
        volumes_iter = volume_paginator.paginate(
            Filters=[{'Name': 'status', 'Values': ['available']}]
        )

        for page in volumes_iter:
            for volume in page['Volumes']:
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
        #
        # Collect all volume IDs first across all pages, then fetch sizes in
        # batches — avoids one describe_volumes API call per instance (N+1).
        instance_paginator = ec2_client.get_paginator('describe_instances')
        instances_iter = instance_paginator.paginate(
            Filters=[{'Name': 'instance-state-name', 'Values': ['stopped']}]
        )

        stopped_instances = []  # list of (instance_dict, [volume_id, ...])
        all_ebs_volume_ids = []

        for page in instances_iter:
            for reservation in page['Reservations']:
                for instance in reservation['Instances']:
                    vol_ids = [
                        mapping['Ebs']['VolumeId']
                        for mapping in instance.get('BlockDeviceMappings', [])
                        if 'Ebs' in mapping
                    ]
                    all_ebs_volume_ids.extend(vol_ids)
                    stopped_instances.append((instance, vol_ids))

        # Batch describe volumes (≤500 IDs per call)
        volume_sizes = {}
        for i in range(0, len(all_ebs_volume_ids), 500):
            chunk = all_ebs_volume_ids[i:i + 500]
            vol_response = ec2_client.describe_volumes(VolumeIds=chunk)
            for vol in vol_response['Volumes']:
                volume_sizes[vol['VolumeId']] = vol['Size']

        for instance, vol_ids in stopped_instances:
            ebs_cost = sum(
                Decimal(str(volume_sizes.get(vid, 0))) * Decimal('0.10')
                for vid in vol_ids
            )

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
        #
        # snapshot['StartTime'] from the AWS SDK is timezone-aware (UTC).
        # Compare directly against a timezone-aware cutoff — do not strip tzinfo,
        # as that caused incorrect comparisons when the offset is non-zero.
        snapshot_paginator = ec2_client.get_paginator('describe_snapshots')
        snapshots_iter = snapshot_paginator.paginate(OwnerIds=['self'])
        old_date = datetime.now(timezone.utc) - timedelta(days=90)

        for page in snapshots_iter:
            for snapshot in page['Snapshots']:
                if snapshot['StartTime'] < old_date:
                    # Estimate: $0.05/GB-month for snapshots
                    size = Decimal(str(snapshot['VolumeSize']))
                    monthly_cost = size * Decimal('0.05')
                    total_savings += monthly_cost

                    age_days = (datetime.now(timezone.utc) - snapshot['StartTime']).days

                    recommendations.append({
                        'type': 'Old Snapshot',
                        'resource_id': snapshot['SnapshotId'],
                        'age_days': age_days,
                        'size_gb': snapshot['VolumeSize'],
                        'monthly_savings': monthly_cost,
                        'action': 'Delete if backup no longer needed'
                    })
        
        # Send report if savings found
        min_threshold = Decimal(os.environ['MIN_SAVINGS_THRESHOLD'])
        
        if total_savings >= min_threshold:
            message = "Resource Optimization Opportunities\n"
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
