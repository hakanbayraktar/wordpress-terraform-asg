output "alb_sg_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "bastion_sg_id" {
  description = "Bastion Security Group ID"
  value       = aws_security_group.bastion.id
}

output "wordpress_sg_id" {
  description = "WordPress Security Group ID"
  value       = aws_security_group.wordpress.id
}

output "rds_sg_id" {
  description = "RDS Security Group ID"
  value       = aws_security_group.rds.id
}

output "efs_sg_id" {
  description = "EFS Security Group ID"
  value       = aws_security_group.efs.id
}