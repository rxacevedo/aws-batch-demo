resource "aws_cloudwatch_metric_alarm" "batch_dynamic_scale_out" {

  alarm_name = "capacity-under-3-times"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name = "ScaleOutFactor"
  namespace = "Custom"
  period = "60"
  statistic = "Sum"
  threshold = "3"
  alarm_description = "This metric monitors the period in which scale-out is needed"
  alarm_actions     = ["${aws_autoscaling_policy.batch_dynamic.arn}"]
  insufficient_data_actions = []

  dimensions {
    JobQueue = "batch-queue-1"
  }

}
