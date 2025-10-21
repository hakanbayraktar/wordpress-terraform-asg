output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.alb.alb_dns_name
}

output "wordpress_url" {
  description = "WordPress URL"
  value       = "http://${module.alb.alb_dns_name}"
}

output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = module.bastion.bastion_public_ip
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}

output "efs_id" {
  description = "EFS File System ID"
  value       = module.efs.efs_id
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  value       = module.autoscaling.autoscaling_group_name
}

output "ssh_to_bastion" {
  description = "SSH command to connect to bastion host"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${module.bastion.bastion_public_ip}"
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for alarms"
  value       = module.cloudwatch.sns_topic_arn
}

# OpenVPN Outputs (only when VPN is enabled)
output "vpn_server_ip" {
  description = "OpenVPN server public IP (connect here first)"
  value       = var.enable_vpn ? module.openvpn[0].vpn_server_public_ip : "VPN not enabled"
}

output "vpn_user" {
  description = "VPN username"
  value       = var.enable_vpn ? module.openvpn[0].vpn_user : "VPN not enabled"
}

output "vpn_config_path" {
  description = "Path to VPN config file on server"
  value       = var.enable_vpn ? module.openvpn[0].vpn_config_path : "VPN not enabled"
}

output "download_vpn_config" {
  description = "Command to download VPN config file"
  value       = var.enable_vpn ? "scp -i ~/.ssh/${var.key_name}.pem ubuntu@${module.openvpn[0].vpn_server_public_ip}:/root/${var.vpn_user}.ovpn ~/vpn/" : "VPN not enabled - set enable_vpn=true in terraform.tfvars"
}

output "vpn_setup_instructions" {
  description = "Instructions for VPN setup"
  value = var.enable_vpn ? join("\n", [
    "========================================",
    "OpenVPN Server Setup Complete!",
    "========================================",
    "",
    "1. Wait 5 minutes for OpenVPN installation to complete",
    "",
    "2. Download your VPN config file:",
    "   ./scripts/download-vpn-config.sh",
    "",
    "3. Connect to VPN:",
    "   - macOS/Linux: sudo openvpn --config ~/vpn/${var.vpn_user}.ovpn",
    "   - Windows: Import ~/vpn/${var.vpn_user}.ovpn into OpenVPN GUI",
    "   - Tunnelblick (macOS): Double-click the .ovpn file",
    "",
    "4. After VPN is connected, access bastion:",
    "   ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${module.bastion.bastion_public_ip}",
    "",
    "5. Security: Bastion now only accepts SSH from VPN server IP",
    "   VPN Server IP: ${module.openvpn[0].vpn_server_public_ip}",
    "",
    "For troubleshooting, check README.md VPN section.",
    "========================================"
  ]) : "Set enable_vpn=true in terraform.tfvars to enable OpenVPN"
}