output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.wordpress.arn
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.wordpress.dns_name
}

output "alb_zone_id" {
  description = "ALB zone ID"
  value       = aws_lb.wordpress.zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = aws_lb_target_group.wordpress.arn
}

output "target_group_name" {
  description = "Target group name"
  value       = aws_lb_target_group.wordpress.name
}