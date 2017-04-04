########################################################
# Scheduling

/*

resource "aws_cloudwatch_event_rule" "task_cron" {
  name = "cron-s3-catter-jobsubmit"
  description = "RUN IT"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule = "${aws_cloudwatch_event_rule.task_cron.name}"
  target_id = "JobSubmit"  # This is just a name really
  arn = "${aws_lambda_function.jobsubmit.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.jobsubmit.arn}"
    principal = "events.amazonaws.com"
    # source_account = "111122223333"
    source_arn = "${aws_cloudwatch_event_rule.task_cron.arn}"
    # qualifier = "${aws_lambda_alias.test_alias.name}"
}

*/

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
