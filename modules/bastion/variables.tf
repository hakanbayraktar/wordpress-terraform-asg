variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for bastion host"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Bastion security group ID"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "bastion_instance_type" {
  description = "Bastion instance type"
  type        = string
}