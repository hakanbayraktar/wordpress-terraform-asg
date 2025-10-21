output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = aws_sns_topic.alarms.arn
}

output "sns_topic_name" {
  description = "SNS topic name"
  value       = aws_sns_topic.alarms.name
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "cpu_high_alarm_name" {
  description = "CPU high alarm name"
  value       = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}

output "cpu_low_alarm_name" {
  description = "CPU low alarm name"
  value       = aws_cloudwatch_metric_alarm.cpu_low.alarm_name
}