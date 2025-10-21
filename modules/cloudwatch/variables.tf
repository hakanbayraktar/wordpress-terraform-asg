variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  type        = string
}

variable "scale_up_policy_arn" {
  description = "Scale up policy ARN"
  type        = string
}

variable "scale_down_policy_arn" {
  description = "Scale down policy ARN"
  type        = string
}

variable "alarm_email" {
  description = "Email address for alarm notifications"
  type        = string
}