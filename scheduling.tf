########################################################
# Scheduling

## Daily

resource "aws_cloudwatch_event_rule" "sekret_cron" {
  name = "cat-sekret"
  description = "cat the sekret.txt file"
  schedule_expression = "rate(1 day)"
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
  role             = "${aws_iam_role.jobsubmit_execution_role.arn}"
  handler          = "jobsubmit.invoke"
  source_code_hash = "${base64sha256(file("jobsubmit.zip"))}"
  runtime          = "python2.7"
  timeout          = 120

  depends_on = ["data.archive_file.jobsubmit"]
}

resource "aws_iam_role" "jobsubmit_execution_role" {
  name = "lambda-jobsubmit-execution-role"
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

resource "aws_iam_role_policy" "logging_permissions" {
  name = "jobsubmit-logging-permissions"
  role = "${aws_iam_role.jobsubmit_execution_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": [
              "logs:*"
          ],
          "Resource": "${aws_cloudwatch_log_group.jobsubmit.arn}"
      }
  ]
}
EOF
}

resource "aws_iam_role_policy" "jobsubmit_permissions" {
  name = "jobsubmit-batch-permissions"
  role = "${aws_iam_role.jobsubmit_execution_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "batch:SubmitJob"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
