variable "project_name" {
  description = "Project name for resource naming"
  type        = string
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

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "instance_type" {
  description = "Instance type for OpenVPN server"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "vpn_user" {
  description = "VPN client username to create"
  type        = string
  default     = "hakan"
}
