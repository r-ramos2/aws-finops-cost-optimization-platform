terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_iam_policy_document" "kms_finops" {
  statement {
    sid    = "EnableAccountRootAdministration"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }

  statement {
    sid    = "AllowSNSEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# SNS Topic for Cost Alerts
resource "aws_sns_topic" "cost_alerts" {
  name              = "${var.project_name}-cost-alerts"
  display_name      = "AWS Cost Optimization Alerts"
  kms_master_key_id = aws_kms_key.finops.id
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_policy" "cost_alerts_budgets" {
  arn = aws_sns_topic.cost_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAWSBudgetsPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.cost_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# KMS Key for Encryption
resource "aws_kms_key" "finops" {
  description             = "KMS key for FinOps cost optimization"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_finops.json
  tags                    = local.common_tags
}

resource "aws_kms_alias" "finops" {
  name          = "alias/${var.project_name}"
  target_key_id = aws_kms_key.finops.key_id
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "cost_reporter" {
  name              = "/aws/lambda/${var.project_name}-cost-reporter"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.finops.arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "anomaly_detector" {
  name              = "/aws/lambda/${var.project_name}-anomaly-detector"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.finops.arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "resource_optimizer" {
  name              = "/aws/lambda/${var.project_name}-resource-optimizer"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.finops.arn
  tags              = local.common_tags
}

resource "aws_sqs_queue" "eventbridge_dlq" {
  name                      = "${var.project_name}-eventbridge-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/aws/sqs"
  tags                      = local.common_tags
}

# IAM Roles for Lambda Functions
resource "aws_iam_role" "cost_reporter_lambda" {
  name = "${var.project_name}-cost-reporter-role"

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
  tags = local.common_tags
}

resource "aws_iam_role" "anomaly_detector_lambda" {
  name = "${var.project_name}-anomaly-detector-role"

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
  tags = local.common_tags
}

resource "aws_iam_role" "resource_optimizer_lambda" {
  name = "${var.project_name}-resource-optimizer-role"

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
  tags = local.common_tags
}

resource "aws_iam_role_policy" "cost_reporter_policy" {
  name = "cost-reporter-access"
  role = aws_iam_role.cost_reporter_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast"
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
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.finops.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = aws_cloudwatch_log_group.cost_reporter.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cost_reporter.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "anomaly_detector_policy" {
  name = "anomaly-detector-access"
  role = aws_iam_role.anomaly_detector_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage"
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
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.finops.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = aws_cloudwatch_log_group.anomaly_detector.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.anomaly_detector.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "resource_optimizer_policy" {
  name = "resource-optimizer-access"
  role = aws_iam_role.resource_optimizer_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
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
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.finops.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = aws_cloudwatch_log_group.resource_optimizer.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.resource_optimizer.arn}:*"
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
  role             = aws_iam_role.cost_reporter_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.cost_reporter.output_base64sha256
  runtime          = "python3.9"
  timeout          = 60
  tags             = local.common_tags

  environment {
    variables = {
      SNS_TOPIC_ARN  = aws_sns_topic.cost_alerts.arn
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
  role             = aws_iam_role.anomaly_detector_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.anomaly_detector.output_base64sha256
  runtime          = "python3.9"
  timeout          = 60
  tags             = local.common_tags

  environment {
    variables = {
      SNS_TOPIC_ARN     = aws_sns_topic.cost_alerts.arn
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
  role             = aws_iam_role.resource_optimizer_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.resource_optimizer.output_base64sha256
  runtime          = "python3.9"
  timeout          = 120
  tags             = local.common_tags

  environment {
    variables = {
      SNS_TOPIC_ARN         = aws_sns_topic.cost_alerts.arn
      MIN_SAVINGS_THRESHOLD = var.min_savings_threshold
    }
  }

  depends_on = [aws_cloudwatch_log_group.resource_optimizer]
}

# EventBridge Rules
resource "aws_cloudwatch_event_rule" "daily_cost_report" {
  name                = "${var.project_name}-daily-cost-report"
  description         = "Trigger daily cost report"
  schedule_expression = "cron(0 8 * * ? *)" # 8 AM UTC daily
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "daily_cost_report" {
  rule      = aws_cloudwatch_event_rule.daily_cost_report.name
  target_id = "cost-reporter-lambda"
  arn       = aws_lambda_function.cost_reporter.arn
  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }
}

resource "aws_lambda_permission" "allow_eventbridge_cost_reporter" {
  statement_id  = "AllowExecutionFromEventBridgeCostReporter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_cost_report.arn
}

resource "aws_cloudwatch_event_rule" "hourly_anomaly_check" {
  name                = "${var.project_name}-hourly-anomaly"
  description         = "Hourly cost anomaly detection"
  schedule_expression = "rate(1 hour)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "hourly_anomaly_check" {
  rule      = aws_cloudwatch_event_rule.hourly_anomaly_check.name
  target_id = "anomaly-detector-lambda"
  arn       = aws_lambda_function.anomaly_detector.arn
  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }
}

resource "aws_lambda_permission" "allow_eventbridge_anomaly_detector" {
  statement_id  = "AllowExecutionFromEventBridgeAnomalyDetector"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anomaly_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.hourly_anomaly_check.arn
}

resource "aws_cloudwatch_event_rule" "weekly_optimization" {
  name                = "${var.project_name}-weekly-optimization"
  description         = "Weekly resource optimization scan"
  schedule_expression = "cron(0 9 ? * MON *)" # 9 AM UTC every Monday
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "weekly_optimization" {
  rule      = aws_cloudwatch_event_rule.weekly_optimization.name
  target_id = "resource-optimizer-lambda"
  arn       = aws_lambda_function.resource_optimizer.arn
  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }
}

resource "aws_lambda_permission" "allow_eventbridge_resource_optimizer" {
  statement_id  = "AllowExecutionFromEventBridgeResourceOptimizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resource_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_optimization.arn
}

# Budget Alert
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  depends_on = [aws_sns_topic_policy.cost_alerts_budgets]

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 75
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 90
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }
}

resource "aws_sqs_queue_policy" "eventbridge_dlq" {
  queue_url = aws_sqs_queue.eventbridge_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.eventbridge_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              aws_cloudwatch_event_rule.daily_cost_report.arn,
              aws_cloudwatch_event_rule.hourly_anomaly_check.arn,
              aws_cloudwatch_event_rule.weekly_optimization.arn
            ]
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "cost_reporter_errors" {
  alarm_name          = "${var.project_name}-cost-reporter-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when cost reporter Lambda errors occur"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  dimensions = {
    FunctionName = aws_lambda_function.cost_reporter.function_name
  }
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "anomaly_detector_errors" {
  alarm_name          = "${var.project_name}-anomaly-detector-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when anomaly detector Lambda errors occur"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  dimensions = {
    FunctionName = aws_lambda_function.anomaly_detector.function_name
  }
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "resource_optimizer_errors" {
  alarm_name          = "${var.project_name}-resource-optimizer-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when resource optimizer Lambda errors occur"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  dimensions = {
    FunctionName = aws_lambda_function.resource_optimizer.function_name
  }
  tags = local.common_tags
}
