terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.98.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  required_version = "~> 1.12.0"
}

variable "repository_id" {
  type    = string
  default = "HectorFernandezF/codebuild-demo"
}

provider "github" {
  token = var.github_token
}

variable "github_token" {
  type      = string
  sensitive = true
  default   = ""
}