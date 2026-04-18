variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "finops-cost-optimization"
}

variable "alert_email" {
  description = "Email address for cost alerts"
  type        = string
}

variable "monthly_budget" {
  description = "Monthly AWS budget in USD"
  type        = string
  default     = "1000"
}

variable "anomaly_threshold_percent" {
  description = "Percentage increase to trigger anomaly alert"
  type        = string
  default     = "30"
}

variable "min_savings_threshold" {
  description = "Minimum monthly savings in USD to report"
  type        = string
  default     = "10"
}
