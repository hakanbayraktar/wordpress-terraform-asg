# SNS Topic for Alarms
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"

  tags = {
    Name = "${var.project_name}-alarms"
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CloudWatch Alarm - Scale Up (CPU > 50%)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  datapoints_to_alarm = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "Triggers when CPU > 50% for 10 minutes"
  treat_missing_data  = "notBreaching"

  alarm_actions       = [var.scale_up_policy_arn, aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = var.autoscaling_group_name
  }

  tags = {
    Name = "${var.project_name}-cpu-high-alarm"
  }
}

# CloudWatch Alarm - Scale Down (CPU < 50%)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  datapoints_to_alarm = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "Triggers when CPU < 50% for 10 minutes"
  treat_missing_data  = "notBreaching"

  alarm_actions       = [var.scale_down_policy_arn, aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = var.autoscaling_group_name
  }

  tags = {
    Name = "${var.project_name}-cpu-low-alarm"
  }
}

# CloudWatch Alarm - Unhealthy Host Count
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  datapoints_to_alarm = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "Triggers when there are unhealthy hosts"
  treat_missing_data  = "notBreaching"

  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.autoscaling_group_name
  }

  tags = {
    Name = "${var.project_name}-unhealthy-hosts-alarm"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average", label = "CPU Utilization" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "EC2 CPU Utilization"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/AutoScaling", "GroupDesiredCapacity", { stat = "Average" }],
            [".", "GroupInServiceInstances", { stat = "Average" }],
            [".", "GroupMinSize", { stat = "Average" }],
            [".", "GroupMaxSize", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Auto Scaling Group Metrics"
        }
      }
    ]
  })
}

data "aws_region" "current" {}