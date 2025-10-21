output "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.wordpress.name
}

output "autoscaling_group_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.wordpress.arn
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.wordpress.id
}

output "scale_up_policy_arn" {
  description = "Scale up policy ARN"
  value       = aws_autoscaling_policy.scale_up.arn
}

output "scale_down_policy_arn" {
  description = "Scale down policy ARN"
  value       = aws_autoscaling_policy.scale_down.arn
}