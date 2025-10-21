variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private app subnet IDs"
  type        = list(string)
}

variable "wordpress_security_group_id" {
  description = "WordPress security group ID"
  type        = string
}

variable "target_group_arn" {
  description = "Target group ARN"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "wordpress_instance_type" {
  description = "WordPress instance type"
  type        = string
}

variable "min_size" {
  description = "Minimum number of instances"
  type        = number
}

variable "max_size" {
  description = "Maximum number of instances"
  type        = number
}

variable "desired_capacity" {
  description = "Desired number of instances"
  type        = number
}

variable "db_host" {
  description = "Database host endpoint"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "efs_id" {
  description = "EFS file system ID"
  type        = string
}