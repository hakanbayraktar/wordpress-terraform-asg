variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either 'dev' or 'prod'."
  }
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for tagging resources"
  type        = string
  default     = "wordpress-autoscaling"
}

# Network Configuration
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Private app subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "Private database subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to bastion host"
  type        = string
  default     = "0.0.0.0/0"  # Change this to your IP for production
}

# EC2 Configuration
variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "bastion_instance_type" {
  description = "Bastion host instance type"
  type        = string
  default     = "t2.micro"
}

variable "wordpress_instance_type" {
  description = "WordPress instance type"
  type        = string
  default     = "t3.micro"
}

# Auto Scaling Configuration
variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 2
}

# RDS Configuration
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "wordpress"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

variable "allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

# CloudWatch Configuration
variable "alarm_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
}

# OpenVPN Configuration
variable "enable_vpn" {
  description = "Enable OpenVPN server for secure access"
  type        = bool
  default     = true
}

variable "vpn_vpc_cidr" {
  description = "CIDR block for VPN VPC (isolated from WordPress VPC)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "vpn_subnet_cidr" {
  description = "CIDR block for VPN public subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "vpn_instance_type" {
  description = "Instance type for OpenVPN server"
  type        = string
  default     = "t2.micro"
}

variable "vpn_user" {
  description = "VPN client username to create"
  type        = string
  default     = "hakan"
}