

#s3
resource "aws_s3_bucket" "artifact_store_bucket" {
  bucket = "codepipeline_artifact_store_testing"
}

data "aws_iam_policy_document" "codepipeline_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "codepipeline_assume_role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role_policy.json
}

resource "aws_codepipeline" "demo" {
  name = "demo"
  pipeline_type = "V1"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_store_bucket.bucket
    type = "S3"
  }

  stage {
    name = "Source"

    action {
      name = "Source"
      category = "Source"
      owner = "ThirdParty"
      provider = "GitHub"
      version = "1"
      output_artifacts = [ "source_output" ]
      run_order = 1

      configuration = {
        FullRepositoryId = var.repository_id
        BranchName = "main"
        DetectChanges = true
        OAuthToken       = var.github_token
      }
    }

  }

    stage {
        name = "Build"

        action {
          name = "BuildAction"
          category = "Build"
          owner = "AWS"
          provider = "CodeBuild"
          version = "1"
          input_artifacts = [ "source_output" ]
          output_artifacts = [ ]
          run_order = 2

          configuration = {
            ProjectName = aws_codebuild_project.codebuild_projects["python_project"].name
          }
        }
    }

    stage {
      name = "Deploy"

      action {
        name = "DeployAction"
        category = "Deploy"
        owner = "AWS"
        provider = "CodeDeploy"
        version = "1"
        input_artifacts = [ "source_output" ]
        run_order = 3

        configuration = {
          ApplicationName = aws_codedeploy_app.codedeploy_application.name
          DeploymentGroupName = aws_codedeploy_deployment_group.codedeploy_deployment_group.name
        }
      }
    }
}