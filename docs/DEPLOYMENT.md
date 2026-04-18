# Deployment Guide

## Prerequisites

- AWS account with admin access
- Terraform installed (>= 1.0)
- AWS CLI configured

## Step-by-Step Deployment

### 1. Get the code

```bash
git clone https://github.com/<your-github>/<your-fork>.git
cd <your-repo>
```

If you use a ZIP download, extract it first, then `cd` into the project directory (the folder that contains `terraform/` and `lambda/`).

### 2. Configure Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
alert_email = "your.email@example.com"  # REQUIRED
monthly_budget = "1000"                  # Your monthly AWS budget
aws_region = "us-east-1"                # Your preferred region
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform plan    # Review changes
terraform apply   # Type 'yes' to confirm
```

### 4. Confirm SNS Subscription

- Check email inbox for "AWS Notification - Subscription Confirmation"
- Click "Confirm subscription" link

### 5. Verify Deployment

```bash
# Test cost reporter manually
aws lambda invoke \
  --function-name finops-cost-optimization-cost-reporter \
  --region us-east-1 \
  output.json

# Check output
cat output.json
```

### 6. Monitor Execution

```bash
# View logs
aws logs tail /aws/lambda/finops-cost-optimization-cost-reporter --follow
```

## Scheduled Execution

- **Daily Cost Report**: 8:00 AM UTC daily
- **Anomaly Detection**: Every hour
- **Resource Optimization**: 9:00 AM UTC every Monday

## Cleanup

To remove all resources:

```bash
terraform destroy
```

## Troubleshooting

**No emails received?**
- Check SNS subscription confirmed
- Verify email not in spam folder
- Check CloudWatch Logs for Lambda errors

**Permission errors?**
- Ensure AWS credentials have admin access
- Check IAM role policies attached correctly

**High Lambda costs?**
- Review timeout settings (60-120 seconds appropriate)
- Check execution frequency in EventBridge rules
