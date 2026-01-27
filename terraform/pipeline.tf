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

resource "aws_iam_role_policy" "pipeline_policy" {
  name = "${var.project_name}-pipeline-policy"
  role = aws_iam_role.pipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::group2-terraform-state/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
          "iam:GetRole",
          "iam:PassRole",
          "iam:CreateRole",
          "iam:PutRolePolicy",
          "iam:AttachRolePolicy"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
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
  name             = "${var.project_name}-pipeline"
  role_arn         = aws_iam_role.pipeline_role.arn
  pipeline_type    = "V2"
  execution_mode   = "QUEUED"

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.codepipeline_bucket.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

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
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.terraform_build.name
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.pipeline_policy,
    aws_s3_bucket.codepipeline_bucket
  ]
}

# EventBridge Rule for automatic pipeline triggering on GitHub push
resource "aws_cloudwatch_event_rule" "github_push" {
  name        = "${var.project_name}-github-push"
  description = "Trigger CodePipeline on GitHub push"

  event_pattern = jsonencode({
    source      = ["aws.codestar-connections"]
    detail-type = ["CodeStar Connections Repository State Change"]
    detail = {
      event = ["push"]
      referenceType = ["branch"]
      referenceName = ["main"]
      repositoryName = ["terraform-cicd-capstone"]
    }
  })
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  rule      = aws_cloudwatch_event_rule.github_push.name
  target_id = "CodePipeline"
  arn       = aws_codepipeline.terraform_pipeline.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
}

# IAM Role for EventBridge
resource "aws_iam_role" "eventbridge_role" {
  name = "${var.project_name}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name = "${var.project_name}-eventbridge-policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codepipeline:StartPipelineExecution"
      ]
      Resource = aws_codepipeline.terraform_pipeline.arn
    }]
  })
}
