resource "aws_autoscaling_policy" "batch_dynamic_scale_out" {
  name                   = "batch-dynamic-scale-out"
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  scaling_adjustment     = 1
  autoscaling_group_name = "${aws_autoscaling_group.batch_dynamic.name}"
}

resource "aws_autoscaling_policy" "batch_dynamic_scale_in" {
  name                   = "batch-dynamic-scale-in"
  adjustment_type        = "ExactCapacity"
  cooldown               = 300
  scaling_adjustment     = 0
  autoscaling_group_name = "${aws_autoscaling_group.batch_dynamic.name}"
}

resource "aws_cloudwatch_metric_alarm" "batch_dynamic_scale_out" {

  alarm_name = "capacity-under-3-times"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name = "ScaleFactor"
  namespace = "Custom"
  period = "60"
  statistic = "Sum"
  threshold = "3"
  alarm_description = "This metric monitors the period in which scale-out is needed"
  alarm_actions     = ["${aws_autoscaling_policy.batch_dynamic_scale_out.arn}"]
  insufficient_data_actions = []

  dimensions {
    JobQueue = "batch-queue-1"
    ComputeEnvironment = "batch-compute-dynamic"
  }

}

resource "aws_cloudwatch_metric_alarm" "batch_dynamic_scale_in" {

  alarm_name = "capacity-over-3-times"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "1"
  metric_name = "ScaleFactor"
  namespace = "Custom"
  period = "60"
  statistic = "Sum"
  threshold = "-3"
  alarm_description = "This metric monitors the period in which scale-in is needed"
  alarm_actions     = ["${aws_autoscaling_policy.batch_dynamic_scale_in.arn}"]
  insufficient_data_actions = []

  dimensions {
    JobQueue = "batch-queue-1"
    ComputeEnvironment = "batch-compute-dynamic"
  }

}
