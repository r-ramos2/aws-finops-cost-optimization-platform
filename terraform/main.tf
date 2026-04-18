terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# SNS Topic for Cost Alerts
resource "aws_sns_topic" "cost_alerts" {
  name              = "${var.project_name}-cost-alerts"
  display_name      = "AWS Cost Optimization Alerts"
  kms_master_key_id = aws_kms_key.finops.id
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# KMS Key for Encryption
resource "aws_kms_key" "finops" {
  description             = "KMS key for FinOps cost optimization"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "finops" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.finops.key_id
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "cost_reporter" {
  name              = "/aws/lambda/${var.project_name}-cost-reporter"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.finops.arn
}

resource "aws_cloudwatch_log_group" "anomaly_detector" {
  name              = "/aws/lambda/${var.project_name}-anomaly-detector"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.finops.arn
}

resource "aws_cloudwatch_log_group" "resource_optimizer" {
  name              = "/aws/lambda/${var.project_name}-resource-optimizer"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.finops.arn
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_finops" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for Cost Explorer Access
resource "aws_iam_role_policy" "lambda_cost_explorer" {
  name = "cost-explorer-access"
  role = aws_iam_role.lambda_finops.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "budgets:ViewBudget"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",
          "s3:GetLifecycleConfiguration"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function - Cost Reporter
data "archive_file" "cost_reporter" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/cost_reporter"
  output_path = "${path.module}/cost_reporter.zip"
}

resource "aws_lambda_function" "cost_reporter" {
  filename         = data.archive_file.cost_reporter.output_path
  function_name    = "${var.project_name}-cost-reporter"
  role            = aws_iam_role.lambda_finops.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.cost_reporter.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cost_alerts.arn
      MONTHLY_BUDGET = var.monthly_budget
    }
  }

  depends_on = [aws_cloudwatch_log_group.cost_reporter]
}

# Lambda Function - Anomaly Detector
data "archive_file" "anomaly_detector" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/anomaly_detector"
  output_path = "${path.module}/anomaly_detector.zip"
}

resource "aws_lambda_function" "anomaly_detector" {
  filename         = data.archive_file.anomaly_detector.output_path
  function_name    = "${var.project_name}-anomaly-detector"
  role            = aws_iam_role.lambda_finops.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.anomaly_detector.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cost_alerts.arn
      ANOMALY_THRESHOLD = var.anomaly_threshold_percent
    }
  }

  depends_on = [aws_cloudwatch_log_group.anomaly_detector]
}

# Lambda Function - Resource Optimizer
data "archive_file" "resource_optimizer" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/resource_optimizer"
  output_path = "${path.module}/resource_optimizer.zip"
}

resource "aws_lambda_function" "resource_optimizer" {
  filename         = data.archive_file.resource_optimizer.output_path
  function_name    = "${var.project_name}-resource-optimizer"
  role            = aws_iam_role.lambda_finops.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.resource_optimizer.output_base64sha256
  runtime         = "python3.9"
  timeout         = 120

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.cost_alerts.arn
      MIN_SAVINGS_THRESHOLD = var.min_savings_threshold
    }
  }

  depends_on = [aws_cloudwatch_log_group.resource_optimizer]
}

# EventBridge Rules
resource "aws_cloudwatch_event_rule" "daily_cost_report" {
  name                = "${var.project_name}-daily-cost-report"
  description         = "Trigger daily cost report"
  schedule_expression = "cron(0 8 * * ? *)"  # 8 AM UTC daily
}

resource "aws_cloudwatch_event_target" "daily_cost_report" {
  rule      = aws_cloudwatch_event_rule.daily_cost_report.name
  target_id = "cost-reporter-lambda"
  arn       = aws_lambda_function.cost_reporter.arn
}

resource "aws_lambda_permission" "allow_eventbridge_cost_reporter" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_cost_report.arn
}

resource "aws_cloudwatch_event_rule" "hourly_anomaly_check" {
  name                = "${var.project_name}-hourly-anomaly"
  description         = "Hourly cost anomaly detection"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "hourly_anomaly_check" {
  rule      = aws_cloudwatch_event_rule.hourly_anomaly_check.name
  target_id = "anomaly-detector-lambda"
  arn       = aws_lambda_function.anomaly_detector.arn
}

resource "aws_lambda_permission" "allow_eventbridge_anomaly_detector" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anomaly_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.hourly_anomaly_check.arn
}

resource "aws_cloudwatch_event_rule" "weekly_optimization" {
  name                = "${var.project_name}-weekly-optimization"
  description         = "Weekly resource optimization scan"
  schedule_expression = "cron(0 9 ? * MON *)"  # 9 AM UTC every Monday
}

resource "aws_cloudwatch_event_target" "weekly_optimization" {
  rule      = aws_cloudwatch_event_rule.weekly_optimization.name
  target_id = "resource-optimizer-lambda"
  arn       = aws_lambda_function.resource_optimizer.arn
}

resource "aws_lambda_permission" "allow_eventbridge_resource_optimizer" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resource_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_optimization.arn
}

# Budget Alert
resource "aws_budgets_budget" "monthly" {
  name              = "${var.project_name}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = var.monthly_budget
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 75
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }
}
