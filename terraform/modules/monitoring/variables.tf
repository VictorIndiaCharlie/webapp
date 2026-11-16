variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB to monitor (e.g., app/anagram-alb/1234567890)"
  type        = string
}

variable "alert_email" {
  description = "Email address for receiving monitoring alerts"
  type        = string
  default     = ""
}