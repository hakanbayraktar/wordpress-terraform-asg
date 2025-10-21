output "vpn_server_public_ip" {
  description = "OpenVPN server public IP (Elastic IP)"
  value       = aws_eip.openvpn.public_ip
}

output "vpn_server_instance_id" {
  description = "OpenVPN server instance ID"
  value       = aws_instance.openvpn.id
}

output "vpn_vpc_id" {
  description = "VPN VPC ID"
  value       = aws_vpc.openvpn.id
}

output "vpn_user" {
  description = "VPN client username"
  value       = var.vpn_user
}

output "vpn_config_path" {
  description = "Path to VPN config file on server"
  value       = "/root/${var.vpn_user}.ovpn"
}

output "vpn_connection_info" {
  description = "VPN connection information"
  value = {
    server_ip   = aws_eip.openvpn.public_ip
    vpn_user    = var.vpn_user
    config_file = "/root/${var.vpn_user}.ovpn"
    protocol    = "UDP"
    port        = 1194
  }
}
