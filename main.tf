# IAM roles with s3 access
# Install Code deploy agent
# Ensure the service is running
# Check CodeDeploy logs
# Code deploy service role
# Create an application
# Set up a deployment group
# Run a deployment
# Tour the code deploy console

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.98.0"
    }
  }
  required_version = "~> 1.12.0"
}

# role
resource "aws_iam_role" "ec2_reads3_role" {
  name = "ec2_reads3_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy" "ec2_role_for_codedeploy" {
  name = "AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_role_policy_attachment" "ec2-reads-role-codedepoy" {
  role       = aws_iam_role.ec2_reads3_role.name
  policy_arn = data.aws_iam_policy.ec2_role_for_codedeploy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_reads3_role"
  role = aws_iam_role.ec2_reads3_role.name
}

# ec2
data "aws_ami" "amazon_linux" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ssh_to_ec2" {
  key_name   = "ec2_ssh"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "ssh" {
  name   = "allow ssh"
  vpc_id = "vpc-0700b93d7c90cc743"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  name   = "allow web"
  vpc_id = "vpc-0700b93d7c90cc743"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = ["subnet-09f15832ed8583ae2", "subnet-0c0c5500f2e9b81ec"]
}

resource "aws_lb_target_group" "web_alb_target_group" {
  name     = "web-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-0700b93d7c90cc743"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "web_alb_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_alb_target_group.arn
  }
}

resource "aws_launch_template" "ec2_base_template" {
  name                 = "ec2_base_template"
  image_id             = data.aws_ami.amazon_linux.id
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.web.id]
  instance_type        = "t2.micro"
  key_name             = aws_key_pair.ssh_to_ec2.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(
    <<-EOF
    #!/bin/bash -xe
    yum install -y ruby httpd

    cd /opt
    curl -O https://aws-codedeploy-us-east-1.s3.amazonaws.com/latest/install

    chmod +x ./install
    ./install auto

    sudo systemctl start httpd
    EOF
  )
}

resource "aws_autoscaling_group" "ec2_asg" {
  name               = "ec2_asg"
  max_size           = 4
  min_size           = 2
  desired_capacity   = 2
  health_check_type  = "ELB"
  vpc_zone_identifier  = ["subnet-09f15832ed8583ae2", "subnet-0c0c5500f2e9b81ec"]
  target_group_arns  = [aws_lb_target_group.web_alb_target_group.arn]

  launch_template {
    id      = aws_launch_template.ec2_base_template.id
    version = "$Latest"
  }
}

# resource "aws_instance" "ec2_instance" {
#   ami                    = data.aws_ami.amazon_linux.id
#   instance_type          = "t3.micro"
#   iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
#   key_name               = "ec2_ssh"
#   vpc_security_group_ids = [aws_security_group.ssh.id]
#   user_data_base64 = base64encode(<<-EOF
#     #!/bin/bash -xe
#     yum install -y ruby

#     cd /opt
#     curl -O https://aws-codedeploy-us-east-1.s3.amazonaws.com/latest/install

#     chmod +x ./install
#     ./install auto
#     EOF
#   )

#   tags = {
#     Name = "DeployInstance1"
#   }
# }

# role for codedeploy
resource "aws_iam_role" "codedeploy_role" {
  name = "codedeploy-to-ec2"

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = {
                Service = "codedeploy.amazonaws.com"
            }
        }
      ]
    },
  )
}

data "aws_iam_policy" "codedeploy_ec2_policy" {
  name = "AWSCodeDeployRole"
}

resource "aws_iam_role_policy_attachment" "codedeploy_to_ec2" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = data.aws_iam_policy.codedeploy_ec2_policy.arn
}

# code deploy
resource "aws_codedeploy_app" "codedeploy_application" {
  name = "globomantics-web"
  compute_platform = "Server"
}

resource "aws_codedeploy_deployment_group" "codedeploy_deployment_group" {
    app_name = aws_codedeploy_app.codedeploy_application.name
    deployment_group_name = "staging"
    service_role_arn = aws_iam_role.codedeploy_role.arn
    autoscaling_groups = [ aws_autoscaling_group.ec2_asg.id ]
    deployment_config_name = "CodeDeployDefault.OneAtATime"


    deployment_style {
      deployment_option = "WITHOUT_TRAFFIC_CONTROL"
      deployment_type = "IN_PLACE"
    }

    load_balancer_info {
      target_group_info {
        name = aws_lb_target_group.web_alb_target_group.name
      }
    }
}