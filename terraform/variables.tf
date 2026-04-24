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

variable "environment" {
  description = "Deployment environment label"
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = "Email address for cost alerts"
  type        = string
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "monthly_budget" {
  description = "Monthly AWS budget in USD"
  type        = string
  default     = "1000"
  validation {
    condition     = can(tonumber(var.monthly_budget)) && tonumber(var.monthly_budget) > 0
    error_message = "monthly_budget must be a positive number."
  }
}

variable "anomaly_threshold_percent" {
  description = "Percentage increase to trigger anomaly alert"
  type        = string
  default     = "30"
  validation {
    condition     = can(tonumber(var.anomaly_threshold_percent)) && tonumber(var.anomaly_threshold_percent) >= 1 && tonumber(var.anomaly_threshold_percent) <= 500
    error_message = "anomaly_threshold_percent must be between 1 and 500."
  }
}

variable "min_savings_threshold" {
  description = "Minimum monthly savings in USD to report"
  type        = string
  default     = "10"
  validation {
    condition     = can(tonumber(var.min_savings_threshold)) && tonumber(var.min_savings_threshold) >= 0
    error_message = "min_savings_threshold must be zero or greater."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}
