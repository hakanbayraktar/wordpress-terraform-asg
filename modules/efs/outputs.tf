output "efs_id" {
  description = "EFS File System ID"
  value       = aws_efs_file_system.wordpress.id
}

output "efs_dns_name" {
  description = "EFS DNS name"
  value       = aws_efs_file_system.wordpress.dns_name
}

output "efs_access_point_id" {
  description = "EFS Access Point ID"
  value       = aws_efs_access_point.wordpress.id
}