# terraform template for Telstra uploading almost all metadata to s3 created by Arash
# Providers template(1.0.0) and aws(1.39.0) have been used in this file
##varialbes
variable "region" {default = "ap-southeast-2"}
variable "aws_access_key_id" {}
variable "aws_secret_access_key" {}
variable "bucket_name" {}
variable "asgmin" {default = 1}
variable "asgmax" {default = 1}
variable "asgdesire" {default = 1}

# this is used for loading AZs
data "aws_availability_zones" "AZavailable" {}
#This data is used to be able to map correct AMI for region, although sydney is set by default.
data "aws_ami" "AMI" {
  most_recent = true
  filter {
    name = "name"
    values = ["amzn-ami-hvm-????.??.?.????????-x86_64-gp2"]
  }
}

## Provider
provider "aws" {
  region = "${var.region}"
  access_key = "${var.aws_access_key_id}"
  secret_key = "${var.aws_secret_access_key}"
}

## IAM
resource "aws_iam_role" "s3-access" {
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}
# this role is allow all for this test only not secure for prodcution environments
resource "aws_iam_policy" "s3-access" {
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": ["s3:ListBucket"],
          "Resource": ["arn:aws:s3:::${var.bucket_name}"]
      },
      {
          "Effect": "Allow",
          "Action": [
              "s3:PutObject",
              "s3:GetObject"
          ],
          "Resource": ["arn:aws:s3:::${var.bucket_name}/*"]
      }
  ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "s3-access" {
      role = "${aws_iam_role.s3-access.name}"
      policy_arn = "${aws_iam_policy.s3-access.arn}"
}
resource "aws_iam_instance_profile" "s3-access" {
  role = "${aws_iam_role.s3-access.name}"
}
## s3
resource "aws_s3_bucket" "TelstraS3" {
  bucket = "${var.bucket_name}"
  force_destroy = true
}
## User data
#why some metadata let's get almost all metadata to be uploaded to s3
data "template_file" "userdata" {
  template = <<EOD
#!/bin/bash
for i in `curl -s http://169.254.169.254/latest/meta-data/ -o - | egrep -v '/'` ; do echo -n "$i:   "; curl -s http://169.254.169.254/latest/meta-data/$i ;echo ; done > metadata-for-telstra.txt
/usr/bin/aws s3 cp metadata-for-telstra.txt s3://${aws_s3_bucket.TelstraS3.id}/metadata-for-telstra.txt
EOD
}

## launch configuration
resource "aws_launch_configuration" "TelstraLC" {
  image_id = "${data.aws_ami.AMI.id}"
  instance_type = "t2.micro"
  iam_instance_profile = "${aws_iam_instance_profile.s3-access.id}"
  user_data = "${data.template_file.userdata.rendered}"
  lifecycle {
    create_before_destroy = true
  }
}
## Auto Scaling group
resource "aws_autoscaling_group" "TelstraASG" {
  launch_configuration = "${aws_launch_configuration.TelstraLC.name}"
  min_size = "${var.asgmin}"
  max_size = "${var.asgmax}"
  availability_zones = ["${data.aws_availability_zones.AZavailable.names[0]}","${data.aws_availability_zones.AZavailable.names[1]}"]
  desired_capacity = "${var.asgdesire}"
  lifecycle {
    create_before_destroy = true
  }
}

output "region" {
  value = "${var.region} is current region but can be changed by variable \"region\""
}
output "s3" {
  value = " file is located in \"s3://${aws_s3_bucket.TelstraS3.id}/metadata-for-telstra.txt\" , bucket is private though."
}



#Created and tested by Arash on Fri  5 Oct 15:49:46 AEST 2018 for Telstra
