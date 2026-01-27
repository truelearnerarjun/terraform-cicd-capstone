# 1. Artifact Bucket
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "${var.project_name}-artifacts-${random_id.suffix.hex}"
  force_destroy = true
}

resource "random_id" "suffix" {
  byte_length = 3
}

# 2. GitHub Connection (Version 2)
# NOTE: After 'terraform apply', you must go to AWS Console 
# Settings > Connections to "Update pending connection".
resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
}

# 3. IAM Role for both Build and Pipeline
resource "aws_iam_role" "pipeline_role" {
  name = "${var.project_name}-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["codebuild.amazonaws.com", "codepipeline.amazonaws.com"]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "pipeline_admin" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 4. CodeBuild Project
resource "aws_codebuild_project" "terraform_build" {
  name         = "${var.project_name}-build"
  service_role = aws_iam_role.pipeline_role.arn

  artifacts {
    type = "CODEPIPELINE" # Required when using CodePipeline
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type      = "CODEPIPELINE" # Required when using CodePipeline
    buildspec = "buildspec.yml"
  }
}

# 5. CodePipeline
resource "aws_codepipeline" "terraform_pipeline" {
  name          = "${var.project_name}-pipeline"
  role_arn      = aws_iam_role.pipeline_role.arn
  pipeline_type = "V2" # Modern pipeline type

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.codepipeline_bucket.bucket
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection" # Updated to V2
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "truelearnerarjun/terraform-cicd-capstone" 
        BranchName       = "main"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name            = "Terraform"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform_build.name
      }
    }
  }
}
