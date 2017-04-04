data "template_file" "s3_catter" {
  template = "${file("jobdefs/s3_catter.json")}"

  vars {
    image = "${var.image}"
    jobRoleArn = "${aws_iam_role.ecs_task.arn}"
    s3_path = "s3://${var.s3_bucket}/${var.s3_key}"
  }
}
