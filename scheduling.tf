########################################################
# Scheduled events

# TODO: Fix target inputs

resource "aws_cloudwatch_event_rule" "sekret_cron" {
  name                = "cat-sekret"
  description         = "cat the sekret.txt file"
  schedule_expression = "rate(1 day)"
  is_enabled          = false
}

resource "aws_cloudwatch_event_target" "sekret_target" {
  rule      = "${aws_cloudwatch_event_rule.sekret_cron.name}"
  target_id = "JobSubmit"

  # This is just a name really
  arn = "${aws_lambda_function.jobsubmit.arn}"

  input = <<EOF
  {
    "jobs": [
      {
        "jobName": "s3-catter-sekret",
        "jobQueue": "batch-queue-1",
        "jobDefinition": "s3-catter:6",
        "parameters": {
          "s3_path": "s3://${var.s3_bucket}/sekret.txt"
        }
      }
    ]
  }
EOF
}

# Lambda permissions for event
resource "aws_lambda_permission" "allow_cloudwatch_sekret" {
  statement_id  = "allow-cw-schedule-sekret"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.jobsubmit.arn}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.sekret_cron.arn}"
}

## Hourly

resource "aws_cloudwatch_event_rule" "another_cron" {
  name                = "cat-another"
  description         = "cat the another.txt file"
  schedule_expression = "rate(1 hour)"
  is_enabled          = false
}

resource "aws_cloudwatch_event_target" "another_target" {
  rule      = "${aws_cloudwatch_event_rule.another_cron.name}"
  target_id = "JobSubmit"

  # This is just a name really
  arn = "${aws_lambda_function.jobsubmit.arn}"

  input = <<EOF
  {
    "jobs": [
      {
        "jobName": "s3-catter-another",
        "jobQueue": "batch-queue-1",
        "jobDefinition": "s3-catter:6",
        "parameters": {
          "s3_path": "s3://${var.s3_bucket}/another.txt"
        }
      }
    ]
  }
EOF
}

# Lambda permissions for event
resource "aws_lambda_permission" "allow_cloudwatch_another" {
  statement_id  = "allow-cw-schedule-another"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.jobsubmit.arn}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.another_cron.arn}"
}

## Minute

resource "aws_cloudwatch_event_rule" "sleep_cron" {
  name                = "sleep"
  description         = "sleep"
  schedule_expression = "rate(1 minute)"
  is_enabled          = false
}

resource "aws_cloudwatch_event_target" "sleep_target" {
  rule      = "${aws_cloudwatch_event_rule.sleep_cron.name}"
  target_id = "JobSubmit"

  # This is just a name really
  arn = "${aws_lambda_function.jobsubmit.arn}"

  input = <<EOF
  {
    "jobs": [
      {
        "jobName": "sleep",
        "jobQueue": "batch-queue-1",
        "jobDefinition": "sleep:5",
        "parameters": {
          "seconds": "20"
        }
      }
    ]
  }
EOF
}

# Lambda permissions for event
resource "aws_lambda_permission" "allow_cloudwatch_sleep" {
  statement_id  = "allow-cw-schedule-sleep"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.jobsubmit.arn}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.sleep_cron.arn}"
}

########################################################
# Capacity monitor

resource "aws_cloudwatch_event_rule" "monitor_cron" {
  name                = "monitor"
  description         = "Monitor compute capacity available to a batch job queue"
  schedule_expression = "rate(3 minutes)"
  is_enabled          = false
}

# TODO: Handling mapping between compute environments/job queues better

resource "aws_cloudwatch_event_target" "monitor_target" {
  rule      = "${aws_cloudwatch_event_rule.monitor_cron.name}"
  target_id = "CapacityMonitor"

  # This is just a name really
  arn = "${aws_lambda_function.monitor.arn}"

  input = <<EOF
  {
    "jobQueue": "batch-queue-1",
    "computeEnvironment": "batch-compute-dynamic"
  }
EOF
}

resource "aws_lambda_permission" "allow_cloudwatch_monitor" {
  statement_id  = "allow-cw-schedule-monitor"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.monitor.arn}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.monitor_cron.arn}"
}

########################################################
# Lambda (JobSubmit)

data "archive_file" "jobsubmit" {
  type        = "zip"
  source_dir  = "./lambda/jobsubmit"
  output_path = "./jobsubmit.zip"
}

resource "aws_lambda_function" "jobsubmit" {
  filename         = "jobsubmit.zip"
  function_name    = "jobsubmit"
  role             = "${aws_iam_role.lambda_execution_role.arn}"
  handler          = "jobsubmit.invoke"
  source_code_hash = "${base64sha256(file("jobsubmit.zip"))}"
  runtime          = "python3.6"
  timeout          = 120

  depends_on = [
    "data.archive_file.jobsubmit",
  ]
}

data "archive_file" "monitor" {
  type        = "zip"
  source_dir  = "./lambda/monitor"
  output_path = "./monitor.zip"
}

resource "aws_lambda_function" "monitor" {
  filename         = "monitor.zip"
  function_name    = "monitor"
  role             = "${aws_iam_role.lambda_execution_role.arn}"
  handler          = "monitor.run"
  source_code_hash = "${base64sha256(file("monitor.zip"))}"
  runtime          = "python3.6"
  timeout          = 210                                         # Seconds, 3.5 min

  environment {
    variables {
      SLACK_WEBHOOK_URL       = "${var.slack_webhook_url}"
      METRIC_NAMESPACE        = "Custom"
      METRIC_NAME             = "ScaleFactor"
      INTERVAL                = "15"
      ITERS                   = "12"
      SCALE_CAP               = "${var.dynamic_asg_max}"
      AUTOSCALING_GROUP_NAME  = "${aws_autoscaling_group.batch_dynamic.name}"
      AUTOSCALING_POLICY_NAME = "${aws_autoscaling_policy.batch_dynamic.name}"
    }
  }

  depends_on = [
    "null_resource.monitor_deps",
    "data.archive_file.monitor",
  ]
}

resource "null_resource" "monitor_deps" {
  provisioner "local-exec" {
    command = "pip install --upgrade -r ./lambda/monitor/requirements.txt -t ./lambda/monitor"
  }

  triggers = {
    sha_change = "${sha1(file("lambda/monitor/monitor.py"))}"
  }
}

########################################################
# CloudWatch

resource "aws_cloudwatch_log_group" "jobsubmit" {
  name = "/aws/lambda/jobsubmit"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_cloudwatch_log_group" "monitor" {
  name = "/aws/lambda/monitor"

  lifecycle {
    prevent_destroy = false
  }
}

########################################################
# IAM (for Lambda)

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "logging_permissions" {
  name = "lambda-logging-permissions"
  role = "${aws_iam_role.lambda_execution_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": [
              "logs:*"
          ],
          "Resource": [
            "${aws_cloudwatch_log_group.jobsubmit.arn}",
            "${aws_cloudwatch_log_group.monitor.arn}"
            ]
      }
  ]
}
EOF
}

resource "aws_iam_role_policy" "jobsubmit_permissions" {
  name = "batch-permissions"
  role = "${aws_iam_role.lambda_execution_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "batch:SubmitJob",
        "batch:ListJobs",
        "batch:DescribeComputeEnvironments",
        "ecs:DescribeClusters",
        "cloudwatch:PutMetricData",
        "autoscaling:PutScalingPolicy"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
