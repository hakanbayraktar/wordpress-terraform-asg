variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to bastion host (use VPN server IP/32 for VPN-only access)"
  type        = string
}

variable "vpn_server_ip" {
  description = "OpenVPN server IP address (if using VPN)"
  type        = string
  default     = ""
}