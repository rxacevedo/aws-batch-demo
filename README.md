# AWS Batch setup

## TODO:

Welp, AWS Batch has no built in cron/time-based scheduling functionality. So we gotta use Lambda here.

- [ ] Implement small GUI/CLI tool for:
  - [ ] Setting/getting CloudWatch schedules **[FOR JOBSUBMIT ONLY]**
  - [ ] Listing existing schedules **[FOR JOBSUBMIT ONLY]**
  - [ ] Updating schedules for specific job definitions (this will be fun 😬).

## First:
* Create environment/queue objects. Only access requirements for these are on the AWSBatchServiceRole (detailed at the bottom)

### Create Job Queue
```bash
aws batch create-job-queue \
    --job-queue-name batch-queue-1 \
    --state ENABLED \
    --priority 1 \
    --compute-environment-order order=1,computeEnvironment=batch-compute-1
# {
#     "jobQueueName": "batch-queue-1",
#     "jobQueueArn": "arn:aws:batch:us-east-1:999999999999:job-queue/batch-queue-1"
# }
```

### Create Compute Environment
(This creates an ECS cluster)
```bash
aws batch create-compute-environment \
    --compute-environment-name batch-compute-1 \
    --type UNMANAGED \
    --state ENABLED \
    # See below if this policy does not exist in your account
    --service-role arn:aws:iam::999999999999:role/service-role/AWSBatchServiceRole
# {
#     "computeEnvironmentName": "batch-compute-1",
#     "computeEnvironmentArn": "arn:aws:batch:us-east-1:999999999999:compute-environment/batch-compute-1"
# }
```

## Then:
* Run Terraform config to allocate/authorize compute resources and create the `jobsubmit` Lambda function.

## Adding a job definition:
```bash
aws batch register-job-definition --cli-input-json "$(echo data.template_file.s3_catter.rendered | terraform console)"
{
    "jobDefinitionName": "s3-catter",
    "jobDefinitionArn": "arn:aws:batch:us-east-1:999999999999:job-definition/s3-catter:6",
    "revision": 6
}
```

## Finally:

### Submit a job via the Lambda function (prints to STDOUT)

```bash
aws lambda invoke \
    --function-name 999999999999:jobsubmit \
    --log-type Tail \
    --payload '{"jobName": "s3-catter-lambda-invoke", "jobQueue": "batch-queue-1", "jobDefinition": "s3-catter:5"}' \
    /dev/stdout  # Where it writes output to (STDOUT)
```

### Peep the logs

```bash
pip install awslogs  # This is fire btw

# Batch logs
awslogs get /aws/batch/job ALL --watch

# Lambda (jobsubmit) logs
awslogs get /aws/lambda/jobsubmit ALL --watch
```

## If AWSBatchServiceRole does not exist:

In case it is not created manually, the AWSBatchServiceRole consists of the following objects (so go create them before doing anything else):

### Trust relationship/policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "batch.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Policy document (permissions)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeInstances",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeSpotFleetInstances",
        "ec2:DescribeSpotFleetRequests",
        "ec2:DescribeSpotPriceHistory",
        "ec2:RequestSpotFleet",
        "ec2:CancelSpotFleetRequests",
        "ec2:ModifySpotFleetRequest",
        "ec2:TerminateInstances",
        "autoscaling:DescribeAccountLimits",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:CreateLaunchConfiguration",
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:DeleteLaunchConfiguration",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:SuspendProcesses",
        "autoscaling:PutNotificationConfiguration",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ecs:DescribeClusters",
        "ecs:DescribeContainerInstances",
        "ecs:DescribeTaskDefinitions",
        "ecs:DescribeTasks",
        "ecs:ListClusters",
        "ecs:ListContainerInstances",
        "ecs:ListTaskDefinitionFamilies",
        "ecs:ListTaskDefinitions",
        "ecs:ListTasks",
        "ecs:CreateCluster",
        "ecs:DeleteCluster",
        "ecs:RegisterTaskDefinition",
        "ecs:DeregisterTaskDefinition",
        "ecs:RunTask",
        "ecs:StartTask",
        "ecs:StopTask",
        "ecs:UpdateContainerAgent",
        "ecs:DeregisterContainerInstance",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "iam:GetInstanceProfile",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```
