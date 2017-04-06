data "aws_ami" "ecs_ami" {
  most_recent      = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }

}

########################################################
# ECS Cluster

# TODO: Not necessary
/*resource "aws_ecs_cluster" "batch" {
  name = "batch"
}*/

########################################################
# Instance/ASG config

# For nodes in ECS/Batch ASG
resource "aws_security_group" "batch" {
  name = "batch-access"
  description = "Container Instance Allowed Ports"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }

}

# TODO: AWS trust relationship principals
# "ec2.amazonaws.com" - Allows the INSTANCE to register with ECS
# "ecs.amazonaws.com" - Allows ECS to call EC2/ELB for SERVICES (health checks)
# "ecs-tasks.amazonaws.com" - Allows TASKS to be controlled by ECS

resource "aws_iam_role" "ecs_instance" {
  name               = "ecs-instance-role"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
        ]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_instance" {
  name = "ecs-api-calls"
  role = "${aws_iam_role.ecs_instance.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster",
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTelemetrySession",
        "ecs:Submit*",
        "ecs:StartTask",
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetAuthorizationToken",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ecs" {
  name = "ecs-instance-profile"
  path = "/"
  roles = ["${aws_iam_role.ecs_instance.id}"]
}

data "template_file" "init" {
  template = <<EOF
#!/bin/bash
echo ECS_CLUSTER=$${cluster} > /etc/ecs/ecs.config
EOF

  vars {
    # cluster = "${aws_ecs_cluster.batch.name}"
    cluster = "batch-compute-1_Batch_650da530-43e4-3f28-a5ed-ceae37712632"
  }
}

resource "aws_launch_configuration" "batch" {
  name_prefix          = "batch"
  # image_id             = "${lookup(var.ecs_amis, "us-east-1")}"
  image_id             = "${data.aws_ami.ecs_ami.id}"
  # instance_type        = "m4.large"
  instance_type        = "${var.asg_instance_type}"
  key_name             = "aws"
  security_groups      = ["${aws_security_group.batch.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.ecs.id}"
  user_data            = "${data.template_file.init.rendered}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "batch" {
  name                  = "batch"
  launch_configuration  = "${aws_launch_configuration.batch.name}"
  min_size              = "${var.asg_min}"
  max_size              = "${var.asg_max}"
  desired_capacity      = "${var.asg_desired}"
  vpc_zone_identifier   = ["${aws_subnet.main.id}"]

  # lifecycle {
  #   create_before_destroy = true
  # }

  tag {
    key = "Name"
    value = "batch-worker"
    propagate_at_launch = true
  }
}

########################################################
# Task config

resource "aws_iam_role" "ecs_task" {
  name               = "ecs-task-role"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": [
          "ecs-tasks.amazonaws.com"
        ]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_task_catter" {
  name = "ecs-task-s3-catter"
  role = "${aws_iam_role.ecs_task.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::${var.s3_bucket}",
        "arn:aws:s3:::${var.s3_bucket}/sekret.txt",
        "arn:aws:s3:::${var.s3_bucket}/another.txt"
      ]
    }
  ]
}
EOF
}
