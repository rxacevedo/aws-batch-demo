########################################################
# Scheduled jobs

## Daily

# TODO: Fix target inputs

resource "aws_cloudwatch_event_rule" "sekret_cron" {
  name = "cat-sekret"
  description = "cat the sekret.txt file"
  schedule_expression = "rate(1 day)"
  is_enabled = false
}

resource "aws_cloudwatch_event_target" "sekret_target" {
  rule = "${aws_cloudwatch_event_rule.sekret_cron.name}"
  target_id = "JobSubmit"  # This is just a name really
  arn = "${aws_lambda_function.jobsubmit.arn}"
  input = <<EOF
  {
    "jobName": "s3-catter-sekret",
    "jobQueue": "batch-queue-1",
    "jobDefinition": "s3-catter:6",
    "parameters": {"s3_path": "s3://${var.s3_bucket}/sekret.txt"}
  }
EOF
}

resource "aws_lambda_permission" "allow_cloudwatch_sekret" {
    statement_id = "allow-cw-schedule-sekret"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.jobsubmit.arn}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.sekret_cron.arn}"
}

## Hourly

resource "aws_cloudwatch_event_rule" "another_cron" {
  name = "cat-another"
  description = "cat the another.txt file"
  schedule_expression = "rate(1 hour)"
  is_enabled = false
}

resource "aws_cloudwatch_event_target" "another_target" {
  rule = "${aws_cloudwatch_event_rule.another_cron.name}"
  target_id = "JobSubmit"  # This is just a name really
  arn = "${aws_lambda_function.jobsubmit.arn}"
  input = <<EOF
  {
    "jobName": "s3-catter-another",
    "jobQueue": "batch-queue-1",
    "jobDefinition": "s3-catter:6",
    "parameters": {"s3_path": "s3://${var.s3_bucket}/another.txt"}
  }
EOF
}

resource "aws_lambda_permission" "allow_cloudwatch_another" {
    statement_id = "allow-cw-schedule-another"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.jobsubmit.arn}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.another_cron.arn}"
}

## Minute

resource "aws_cloudwatch_event_rule" "sleep_cron" {
  name = "sleep"
  description = "sleep"
  schedule_expression = "rate(1 minute)"
  is_enabled = false
}

resource "aws_cloudwatch_event_target" "sleep_target" {
  rule = "${aws_cloudwatch_event_rule.sleep_cron.name}"
  target_id = "JobSubmit"  # This is just a name really
  arn = "${aws_lambda_function.jobsubmit.arn}"
  input = <<EOF
  {
    "jobName": "sleep",
    "jobQueue": "batch-queue-1",
    "jobDefinition": "sleep:5",
    "parameters": {"seconds": "20"}
  }
EOF
}

resource "aws_lambda_permission" "allow_cloudwatch_sleep" {
  statement_id = "allow-cw-schedule-sleep"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.jobsubmit.arn}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.sleep_cron.arn}"
}

########################################################
# Jobber (monitors compute)

resource "aws_cloudwatch_event_rule" "jobber_cron" {
  name = "jobber"
  description = "Monitor compute capacity available to a batch job queue"
  schedule_expression = "rate(1 minute)"
  is_enabled = false
}

resource "aws_cloudwatch_event_target" "jobber_target" {
  rule = "${aws_cloudwatch_event_rule.jobber_cron.name}"
  target_id = "Jobber"  # This is just a name really
  arn = "${aws_lambda_function.jobber.arn}"
  input = <<EOF
  {
    "jobQueue": "batch-queue-1",
    "computeEnvironment": "batch-compute-1"
  }
EOF
}

resource "aws_lambda_permission" "allow_cloudwatch_jobber" {
    statement_id = "allow-cw-schedule-jobber"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.jobber.arn}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.jobber_cron.arn}"
}

########################################################
# Lambda (JobSubmit)

data "archive_file" "jobsubmit" {
  type        = "zip"
  source_dir  = "./jobsubmit"
  output_path = "./jobsubmit.zip"
}

resource "aws_lambda_function" "jobsubmit" {
  filename         = "jobsubmit.zip"
  function_name    = "jobsubmit"
  role             = "${aws_iam_role.lambda_execution_role.arn}"
  handler          = "jobsubmit.invoke"
  source_code_hash = "${base64sha256(file("jobsubmit.zip"))}"
  runtime          = "python2.7"
  timeout          = 120

  depends_on = ["data.archive_file.jobsubmit"]
}

data "archive_file" "jobber" {
  type        = "zip"
  source_dir  = "./jobber"
  output_path = "./jobber.zip"
}

resource "aws_lambda_function" "jobber" {
  filename         = "jobber.zip"
  function_name    = "jobber"
  role             = "${aws_iam_role.lambda_execution_role.arn}"
  handler          = "jobber.run"
  source_code_hash = "${base64sha256(file("jobber.zip"))}"
  runtime          = "python2.7"
  timeout          = 120

  environment {
    variables {
      SLACK_WEBHOOK_URL = "${var.slack_webhook_url}"
    }
  }

  depends_on = ["data.archive_file.jobber"]
}

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

## CloudWatch Logs

resource "aws_cloudwatch_log_group" "jobsubmit" {
  name = "/aws/lambda/jobsubmit"
}

resource "aws_cloudwatch_log_group" "jobber" {
  name = "/aws/lambda/jobber"
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
            "${aws_cloudwatch_log_group.jobber.arn}"
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
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
