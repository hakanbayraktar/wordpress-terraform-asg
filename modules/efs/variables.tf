variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "efs_security_group_id" {
  description = "EFS security group ID"
  type        = string
}