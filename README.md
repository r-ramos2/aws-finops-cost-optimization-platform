# AWS FinOps Cost Optimization Platform

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.0-blue)](https://www.terraform.io/) [![AWS](https://img.shields.io/badge/AWS-Cloud-orange)](https://aws.amazon.com/) [![Python](https://img.shields.io/badge/Python-3.9-blue)](https://www.python.org/) [![Lambda](https://img.shields.io/badge/AWS-Lambda-orange)](https://aws.amazon.com/lambda/) [![EventBridge](https://img.shields.io/badge/AWS-EventBridge-orange)](https://aws.amazon.com/eventbridge/)

Automated cost monitoring, anomaly detection, and resource optimization for AWS infrastructure. Teams often target **roughly 20–35%** savings when they combine visibility like this with broader FinOps practices (right-sizing, purchasing programs, storage lifecycle work, and governance).

---

## Highlights (For Recruiters & Hiring Managers)

- **Business impact**: Surfaces waste, anomalies, and optimization candidates by email so teams can act quickly; material savings depend on follow-up work across the FinOps playbook (often in the ~20–35% range when multiple levers are used).
- **Production-style controls**: CloudWatch logging, KMS encryption for SNS and log groups, least-privilege IAM scoped to the functions’ APIs, and an SNS resource policy so AWS Budgets can publish to the topic.
- **Serverless-first**: Event-driven Lambda functions triggered by EventBridge for zero idle costs and automatic scaling.
- **Cost visibility**: Daily email reports with budget tracking, service-level breakdowns, and month-to-date spend analysis.
- **FinOps automation**: Detects configurable cost spikes (default 30%+), scans for unattached EBS volumes, stopped instances, and aged snapshots, and emails actionable summaries—without manual runs.

---

## Quickstart (For Experienced Users)

```bash
# 1. Get the code and enter the terraform folder (fork/clone your copy, or cd into your extracted project directory)
git clone https://github.com/<your-github>/<your-fork>.git
cd <your-repo>/terraform

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars → set alert_email and monthly_budget

# 3. Deploy infrastructure
terraform init
terraform apply -auto-approve

# 4. Confirm SNS subscription
# Check email for "AWS Notification - Subscription Confirmation"
# Click confirmation link

# 5. Verify deployment (manual test)
aws lambda invoke --function-name finops-cost-optimization-cost-reporter output.json
cat output.json
```

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Repository Structure](#repository-structure)
4. [Getting Started](#getting-started)
5. [How It Works](#how-it-works)
6. [Expected Savings](#expected-savings)
7. [Cost Estimate](#cost-estimate)
8. [Cleanup](#cleanup)
9. [Best Practices](#best-practices)
10. [Security Considerations](#security-considerations)
11. [Troubleshooting](#troubleshooting)
12. [Limitations (Not Production-Ready)](#limitations-not-production-ready)
13. [Next Steps & Enhancements](#next-steps--enhancements)
14. [Resources](#resources)

---

## Architecture Overview

```
EventBridge (Daily 8AM UTC)    → Lambda (Cost Reporter)     → SNS → Email
EventBridge (Hourly)           → Lambda (Anomaly Detector)  → SNS → Email  
EventBridge (Weekly Mon 9AM)   → Lambda (Resource Optimizer) → SNS → Email

All Lambdas → CloudWatch Logs (7-day retention, KMS encrypted)
AWS Budgets → SNS → Email (50%, 75%, 90%, 100% thresholds)
```

**Key components:**
- **3 Lambda functions** for cost reporting, anomaly detection, and resource optimization
- **EventBridge rules** for scheduled execution (daily, hourly, weekly)
- **SNS topic** with email subscription for all cost alerts and reports
- **CloudWatch Log Groups** with KMS encryption for centralized logging
- **AWS Budgets** with multi-threshold alerts for spend tracking
- **KMS key** with automatic rotation for encryption at rest

---

## Prerequisites

- AWS account with admin access (or permissions for Lambda, SNS, EventBridge, Cost Explorer, Budgets, KMS, IAM, CloudWatch)
- Terraform installed (>= 1.0)
- AWS CLI configured with credentials
- Email address for cost alerts
- **Cost Explorer** enabled in AWS account (required for cost data access)

**Enable Cost Explorer:**
1. Navigate to AWS Cost Explorer in the console
2. Click "Enable Cost Explorer" (if not already enabled)
3. Wait 24 hours for initial data population

---

## Repository Structure

```
<your-project-folder>/
├── README.md                     # This file
├── LICENSE                       # MIT License
├── .gitignore                    # Git ignore rules
├── terraform/
│   ├── main.tf                   # Primary infrastructure definitions
│   ├── variables.tf              # Input variable declarations
│   ├── outputs.tf                # Output values after deployment
│   └── terraform.tfvars.example  # Example configuration file
├── lambda/
│   ├── cost_reporter/
│   │   ├── lambda_function.py    # Daily cost report logic
│   │   └── requirements.txt      # Python dependencies
│   ├── anomaly_detector/
│   │   ├── lambda_function.py    # Hourly anomaly detection logic
│   │   └── requirements.txt      # Python dependencies
│   └── resource_optimizer/
│       ├── lambda_function.py    # Weekly optimization recommendations
│       └── requirements.txt      # Python dependencies
└── docs/
    └── DEPLOYMENT.md             # Detailed deployment guide
```

---

## Getting Started

### 1. Get the repository

```bash
git clone https://github.com/<your-github>/<your-fork>.git
cd <your-repo>/terraform
```

If you downloaded a ZIP archive instead, extract it, then `cd` into the project folder and run `cd terraform` from there.

### 2. Configure variables

Create your configuration file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set required values:

```hcl
# Required: Email for cost alerts
alert_email = "your.email@example.com"

# Required: Monthly budget in USD
monthly_budget = "1000"

# Optional: Customize project name
project_name = "finops-cost-optimization"

# Optional: AWS region
aws_region = "us-east-1"

# Optional: Anomaly detection threshold (percent increase)
anomaly_threshold_percent = "30"

# Optional: Minimum monthly savings to report
min_savings_threshold = "10"
```

### 3. Provision infrastructure

```bash
# Initialize Terraform and download providers (commit terraform/.terraform.lock.hcl for reproducible applies)
terraform init

# Validate configuration syntax
terraform validate

# Preview infrastructure changes
terraform plan -out=plan.tfplan

# Apply the plan (creates AWS resources)
terraform apply plan.tfplan
```

Deployment creates:
- 3 Lambda functions with CloudWatch log groups
- 1 SNS topic with KMS encryption
- 3 EventBridge rules for scheduling
- 1 IAM role with least-privilege policies
- 1 KMS key with automatic rotation
- 1 AWS Budget with multi-threshold alerts

**Estimated deployment time:** 2-3 minutes

### 4. Confirm SNS subscription

**Critical step:** Without confirmation, you will NOT receive email alerts.

1. Check email inbox for "AWS Notification - Subscription Confirmation"
2. Click "Confirm subscription" link
3. Verify confirmation page appears

**Troubleshooting:** If email not received:
- Check spam/junk folder
- Verify `alert_email` in terraform.tfvars is correct
- Re-run `terraform apply` if needed

### 5. Verify deployment

**Manual test of cost reporter:**

```bash
# Invoke Lambda function manually
aws lambda invoke \
  --function-name finops-cost-optimization-cost-reporter \
  --region us-east-1 \
  output.json

# Check output
cat output.json
```

**Check CloudWatch Logs:**

```bash
# View cost reporter logs
aws logs tail /aws/lambda/finops-cost-optimization-cost-reporter --follow

# View anomaly detector logs
aws logs tail /aws/lambda/finops-cost-optimization-anomaly-detector --follow

# View resource optimizer logs
aws logs tail /aws/lambda/finops-cost-optimization-resource-optimizer --follow
```

Save deployment outputs:

```bash
terraform output > deployment_info.txt
```

---

## How It Works

### Cost Reporter (Daily at 8 AM UTC)

**Purpose:** Daily cost visibility and budget tracking

**Functionality:**
- Fetches yesterday's and month-to-date costs from Cost Explorer API
- Compares MTD spend against configured monthly budget
- Breaks down costs by AWS service (top 10)
- Calculates budget utilization percentage
- Sends formatted email report via SNS

**Email format:**
```
Daily AWS Cost Report

Yesterday: $123.45
Month-to-Date: $2,345.67
Monthly Budget: $3,000.00
Budget Used: 78.2%

Top Services:
- EC2: $1,234.56 (52.6%)
- S3: $456.78 (19.5%)
- RDS: $234.56 (10.0%)
...
```

**Schedule:** Daily at 8:00 AM UTC via EventBridge

### Anomaly Detector (Hourly)

**Purpose:** Early cost spike detection (Cost Explorer data is not real-time; this compares the latest complete daily slice the API returns.)

**Functionality:**
- Compares **yesterday’s** total and per-service costs to the **same weekday one week earlier** (e.g., Tuesday vs the prior Tuesday)
- Flags increases at or above the configured threshold (default 30%)
- Sends an email only when at least one service or the overall total crosses the threshold

**Email format (illustrative):**
```
Cost Anomaly Detected - 2026-04-17

⚠️ Overall costs increased 64.3%
  Previous: $345.67
  Current: $567.89

⚠️ AWS Lambda increased 150.0%
  Previous: $123.45
  Current: $308.64
```

**Schedule:** Every hour via EventBridge

### Resource Optimizer (Weekly Monday 9 AM UTC)

**Purpose:** Identify cost optimization opportunities

**Functionality:**
- Scans for unattached EBS volumes (still incurring storage costs)
- Identifies stopped EC2 instances (EBS volumes still charged)
- Finds snapshots older than 90 days (likely forgotten backups)
- Estimates monthly savings for each recommendation
- Only sends report if total savings >= $10/month (configurable)

**Email format:**
```
💰 Resource Optimization Opportunities
Total Potential Monthly Savings: $234.56

• Unattached EBS Volume
  ID: vol-0abc123
  Savings: $15.20/month
  Action: Delete if no longer needed

• Stopped EC2 Instance
  ID: i-0def456
  Savings: $42.80/month
  Action: Terminate or create AMI and terminate
...
```

**Schedule:** Weekly on Monday at 9:00 AM UTC via EventBridge

---

## Expected Savings

The figures below mix **common FinOps outcomes** (industry patterns) with **what this repository automates** (EBS/snapshot/stopped-instance visibility via the weekly Lambda). S3 lifecycle and broad right-sizing are not implemented in code here; they are included as reference savings categories.

**S3 Lifecycle Policies (manual / separate tooling):** 15-25% reduction on storage costs
- Transition infrequently accessed data to S3 Glacier
- Delete old versions and incomplete multipart uploads
- Typical customer scenario: 1TB Standard → 700GB Standard + 300GB Glacier = $7.68/month savings

**Unattached resource cleanup (partially surfaced by this repo’s weekly scan):** 5-10% reduction on storage costs
- Delete EBS volumes no longer attached to instances
- Remove old snapshots (90+ days with no associated AMI)
- Typical customer scenario: 500GB unattached volumes @ $0.10/GB = $50/month savings

**Right-sizing recommendations (not automated here):** 10-20% reduction on compute costs
- Identify oversized EC2 instances (consistent <20% CPU utilization)
- Recommend Reserved Instances for predictable workloads
- Suggest Spot instances for fault-tolerant workloads
- Typical customer scenario: 5 t3.large → 5 t3.medium = $146/month savings

**Total Potential Reduction:** 20-35% overall AWS spend

**Example scenario:**
- Baseline AWS bill: $3,000/month
- After S3 lifecycle (20%): -$150/month
- After EBS cleanup (5%): -$50/month
- After right-sizing (15%): -$300/month
- **New monthly bill:** $2,500/month (**$500/month savings, 16.7% reduction**)

---

## Cost Estimate

Running this FinOps platform incurs minimal costs:

**Lambda execution:**
- Cost Reporter: 1x daily × 60s × 30 days = 1,800 seconds/month
- Anomaly Detector: 24x daily × 60s × 30 days = 43,200 seconds/month  
- Resource Optimizer: 1x weekly × 120s × 4 weeks = 480 seconds/month
- **Total:** ~45,500 seconds/month = **$0.76/month** (128MB memory, 1M free tier seconds)

**SNS notifications:**
- Daily report: 30 emails/month
- Anomaly alerts: ~5 emails/month (estimated)
- Optimization report: 4 emails/month
- **Total:** ~40 emails/month = **$0.00** (first 1,000 emails free, then $0.50/1,000)

**CloudWatch Logs:**
- 7-day retention for 3 log groups
- Estimated 50MB logs/month
- **Total:** **$0.03/month** ($0.50/GB ingestion)

**KMS:**
- 1 KMS key with rotation
- ~100 encrypt/decrypt operations per month
- **Total:** **$1.00/month** (key storage) + **$0.00** (operations under free tier)

**AWS Budgets:**
- 1 budget with 4 thresholds
- **Total:** **$0.00** (first 2 budgets free)

**Total monthly cost:** **~$1.80-$2.50/month**

**ROI:** If this platform saves even $50/month, ROI = 2,000-2,778%

---

## Cleanup

**Destroy all AWS resources:**

```bash
cd terraform
terraform destroy -auto-approve
```

**Verify deletion:**

```bash
# Check for remaining Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `finops-cost-optimization`)]'

# Check for remaining log groups
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/finops-cost-optimization

# Check for remaining SNS topics
aws sns list-topics --query 'Topics[?contains(TopicArn, `finops-cost-optimization`)]'
```

**Manual cleanup (if terraform destroy fails):**

1. Delete Lambda functions from AWS Console
2. Delete CloudWatch Log Groups
3. Delete SNS topic and subscription
4. Delete EventBridge rules
5. Delete IAM role and policies
6. Schedule KMS key deletion (7-day waiting period)
7. Delete AWS Budget

**Important:** Terraform state file (`terraform.tfstate`) remains on disk after destroy. Delete manually if no longer needed:

```bash
rm -f terraform.tfstate terraform.tfstate.backup
```

---

## Best Practices

**Infrastructure Management:**
- Use remote state (S3 + DynamoDB) for team collaboration
- Tag all resources consistently for cost allocation
- Enable CloudTrail for audit logging of infrastructure changes
- Version control all Terraform code
- Set up AWS billing alerts independent of this platform

**Cost Optimization:**
- Review optimization reports weekly and act on recommendations
- Set realistic monthly budgets based on historical usage
- Adjust `anomaly_threshold_percent` to reduce false positives (start at 30%, increase if too noisy)
- Archive or delete old CloudWatch Logs after 30 days
- Use Terraform workspaces for dev/staging/prod separation

**Security Hygiene:**
- Rotate SNS subscription email if personnel changes
- Review IAM policies quarterly for least privilege
- Enable MFA on AWS root and admin accounts
- Restrict Terraform state file access (contains sensitive outputs)
- Monitor CloudWatch Logs for unusual Lambda execution patterns

**Operational Excellence:**
- Subscribe multiple team members to SNS topic for redundancy
- Document cost optimization actions taken (create ticket trail)
- Schedule monthly reviews of cost trends
- Test disaster recovery (destroy and rebuild infrastructure)
- Automate Terraform applies via CI/CD for production

---

## Security Considerations

This platform follows AWS security best practices but has intentional limitations for simplicity. It is designed as a portfolio/lab project demonstrating FinOps implementation.

**Security features implemented:**

✅ **Encryption at rest:** All CloudWatch Logs encrypted with KMS
✅ **Encryption in transit:** SNS uses TLS; Lambda uses HTTPS for AWS API calls  
✅ **Least-privilege IAM:** Lambda role is scoped to Cost Explorer reads, EC2 describe APIs used by the optimizer, SNS publish to the dedicated topic, KMS use for that topic and log groups, and CloudWatch Logs for the three function log groups
✅ **Budget notifications:** SNS topic policy allows the AWS Budgets service to publish threshold alerts to the same encrypted topic
✅ **KMS key rotation:** Automatic annual key rotation enabled
✅ **No secrets in code:** All configuration via Terraform variables
✅ **CloudWatch logging:** All Lambda executions logged for audit trail

**For production, apply these hardening steps:**

- Store Terraform state in S3 with encryption and versioning enabled
- Use DynamoDB for Terraform state locking to prevent concurrent modifications
- Implement AWS Organizations SCPs to prevent accidental resource deletion
- Add CloudWatch alarms for Lambda errors and throttling
- Enable AWS Config to track configuration changes
- Use AWS Secrets Manager for email addresses instead of plain text variables
- Implement SNS message filtering to route different alert types to different teams
- Add Lambda function VPC integration if accessing private resources
- Enable X-Ray tracing for Lambda functions for debugging
- Implement automated testing (Terratest) before production deployments
- Set up GuardDuty for threat detection on the AWS account
- Configure AWS Backup for disaster recovery of critical data
- Add SCP policies to prevent disabling Cost Explorer or deleting budgets

---

## Troubleshooting

**No email alerts received:**

1. Check SNS subscription confirmed (AWS Console → SNS → Subscriptions)
2. Check spam/junk folder
3. Verify `alert_email` in terraform.tfvars is correct
4. Check Lambda execution logs:
   ```bash
   aws logs tail /aws/lambda/finops-cost-optimization-cost-reporter --follow
   ```
5. Manually invoke Lambda to test:
   ```bash
   aws lambda invoke --function-name finops-cost-optimization-cost-reporter output.json
   ```

**"AccessDenied" errors in Lambda logs:**

1. Verify Cost Explorer is enabled in your AWS account (Billing Dashboard)
2. Wait 24 hours after enabling Cost Explorer for data availability
3. Check IAM role has `ce:GetCostAndUsage` permission
4. Verify AWS credentials have admin access or required permissions

**Terraform apply fails with "ResourceAlreadyExists":**

1. Previous deployment may have partially completed
2. Run `terraform destroy` first, then `terraform apply`
3. Check for orphaned resources in AWS Console (Lambda, SNS, CloudWatch)

**High Lambda costs:**

1. Check EventBridge rule schedules (should be daily, hourly, weekly—not more frequent)
2. Verify Lambda timeout is 60-120 seconds (not higher)
3. Check CloudWatch Logs for Lambda errors causing retries
4. Consider increasing `min_savings_threshold` to reduce optimizer reports

**Cost data is zero or missing:**

1. Cost Explorer requires 24-48 hours after enabling for data
2. New AWS accounts may not have cost data for several days
3. Check Lambda logs for API errors from Cost Explorer
4. Verify AWS account has actual usage generating costs

**Anomaly alerts too frequent (false positives):**

1. Increase `anomaly_threshold_percent` from 30% to 50% or higher
2. Typical workload variance may be normal for your use case
3. Consider changing schedule from hourly to every 6 hours

---

## Limitations (Not Production-Ready)

This repository is intentionally designed as a **portfolio/lab project** demonstrating FinOps implementation. Key limitations:

**Single-account architecture:**
- Only monitors one AWS account (not multi-account AWS Organizations)
- No consolidated billing analysis across accounts
- No cross-region cost aggregation

**Basic reporting:**
- Email-only notifications (no Slack, PagerDuty, or webhook integrations)
- Text-based reports (no dashboards or visualizations)
- No historical trend analysis or cost forecasting
- Limited to top 10 services in cost breakdown

**Limited optimization scope:**
- Does not inspect S3 buckets or recommend lifecycle transitions (only EC2/EBS snapshot heuristics in code)
- Does not analyze Reserved Instance utilization or coverage
- No Savings Plans recommendations
- Does not check for underutilized RDS instances
- No Compute Optimizer integration
- No recommendation engine for EC2 right-sizing (just identifies candidates)

**No automated remediation:**
- Provides recommendations only—does not auto-delete resources
- No approval workflow for optimization actions
- No integration with change management systems

**Security limitations:**
- Email addresses stored in plain text (should use Secrets Manager)
- No fine-grained access control for who receives alerts
- State file stored locally (should use S3 backend with encryption)

These trade-offs keep the project simple, understandable, and cost-efficient while demonstrating core FinOps concepts. For production use, implement the hardening steps in the [Security Considerations](#security-considerations) section.

---

## Next Steps & Enhancements

**Cost visibility improvements:**
- Add CloudWatch Dashboard with cost metrics visualization
- Implement historical cost trending (7-day, 30-day comparisons)
- Create cost allocation tags analysis
- Add Reserved Instance and Savings Plans utilization tracking

**Notification enhancements:**
- Integrate Slack webhooks for team notifications
- Add PagerDuty integration for critical cost spikes
- Implement SNS message filtering for role-based alerting
- Create custom email templates with HTML formatting

**Optimization sophistication:**
- Integrate AWS Compute Optimizer recommendations
- Add RDS instance utilization analysis
- Implement Lambda function right-sizing recommendations
- Create automated S3 Intelligent-Tiering enablement

**Multi-account support:**
- Extend to AWS Organizations consolidated billing
- Implement cross-account IAM roles for cost analysis
- Add account-level and OU-level budget tracking
- Create service-control policies for cost governance

**Automation and workflow:**
- Build approval workflow for optimization actions (Slack buttons → Step Functions)
- Implement automated EBS snapshot cleanup (with safety checks)
- Add Terraform drift detection and auto-remediation
- Create CI/CD pipeline for infrastructure updates

**Advanced analytics:**
- Integrate Amazon QuickSight for interactive dashboards
- Implement cost anomaly detection using ML (AWS Cost Anomaly Detection)
- Add cost forecasting with trend analysis
- Create chargebacks/showbacks for business units

---

## Resources

- [AWS Cost Explorer Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html)
- [AWS Budgets Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- [AWS SNS Documentation](https://docs.aws.amazon.com/sns/)
- [FinOps Foundation](https://www.finops.org/)
- [AWS Cost Optimization Best Practices](https://aws.amazon.com/pricing/cost-optimization/)
