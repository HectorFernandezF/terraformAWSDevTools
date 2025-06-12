# Codebuild role
data "aws_iam_policy_document" "codebuild_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuildRole" {
  name               = "codebuildServiceRole"
  assume_role_policy = data.aws_iam_policy_document.codebuild_policy.json
}

# s3 bucket
resource "aws_s3_bucket" "codebuild_demo_artifact" {
  bucket = "mytestings3bucket4builds2"
}

# policy
data "aws_iam_policy_document" "s3_cloudwatchpolicy_policy" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.codebuild_demo_artifact.arn,
      "${aws_s3_bucket.codebuild_demo_artifact.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:CreateLogGroup"
    ]
    resources = [
      "arn:aws:logs:*"
    ]
  }
}

resource "aws_iam_role_policy" "s3_policy" {
  role   = aws_iam_role.codebuildRole.name
  policy = data.aws_iam_policy_document.s3_cloudwatchpolicy_policy.json
}

locals {
  codebuild_projects = {
    java_project = {
      name      = "JavaBuildProject"
      gh_repo   = "https://github.com/wes-novack/codebuild-demo.git"
      buildspec = "java-example/buildspec.yml"
      image     = "aws/codebuild/standard:5.0"
    }

    python_project = {
      name      = "PythonBuildProject"
      gh_repo   = "https://github.com/wes-novack/codebuild-demo.git"
      buildspec = "python-example/buildspec.yml"
      image     = "aws/codebuild/python:3.7.1-1.7.0"
    }

    ruby_project = {
      name      = "RubyBuildProject"
      gh_repo   = "https://github.com/HectorFernandezF/terraformAWSDevTools"
      buildspec = "code-build/buildspec.yml"
      image     = "aws/codebuild/eb-ruby-2.3-amazonlinux-64:2.1.6"
    }
  }
}

# main build project
resource "aws_codebuild_project" "codebuild_projects" {
  for_each = local.codebuild_projects

  name           = each.value.name
  description    = "Testing with ${each.value.name}"
  service_role   = aws_iam_role.codebuildRole.arn
  build_timeout  = 5
  queued_timeout = 5

  source {
    type      = "GITHUB"
    location  = each.value.gh_repo
    buildspec = each.value.buildspec
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = each.value.image
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "foo"
      value = "bar"
    }
  }

  artifacts {
    type           = "S3"
    location       = aws_s3_bucket.codebuild_demo_artifact.id
    name           = each.value.name
    namespace_type = "BUILD_ID"
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = "/aws/codebuild/${each.value.name}"
      stream_name = "build-log"
    }
  }

  tags = {
    Company = "Justia"
  }
}