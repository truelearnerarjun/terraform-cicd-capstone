############################################
# 1) Artifact Bucket
############################################
resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "${var.project_name}-artifacts-${random_id.suffix.hex}"
  force_destroy = true
}


############################################
# 2) GitHub Connection (CodeStar Connections v2)
# After 'terraform apply', go to:
# AWS Console → Developer Tools → Connections → "Update pending connection"
############################################
resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
}


############################################
# 3) IAM Role & Policy (shared for demo: CodePipeline + CodeBuild)
# (For production, split into separate service roles.)
############################################
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
      # S3 artifacts (pipeline + build)
      {
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*",
          "arn:aws:s3:::group2-terraform-state",
          "arn:aws:s3:::group2-terraform-state/*"
        ]
      },
      # Core services (demo-wide for simplicity)
      {
        Effect   = "Allow"
        Action   = ["codepipeline:*", "codebuild:*", "codestar-connections:*", "codedeploy:*"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:*", "elasticloadbalancing:*"]
        Resource = "*"
      },
      # IAM usage for build/deploy flows
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:PassRole",
          "iam:CreateRole",
          "iam:PutRolePolicy",
          "iam:AttachRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListRoles",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:DeleteRole",
          "iam:UntagRole"
        ]
        Resource = "*"
      },
      # (Optional) EventBridge mgmt not required anymore since we removed custom rule
      {
        Effect   = "Allow"
        Action   = ["events:DescribeRule", "events:ListRules", "events:ListTargetsByRule", "events:ListTagsForResource", "events:PutRule", "events:PutTargets", "events:RemoveTargets", "events:DeleteRule"]
        Resource = "*"
      },
      # Logs for CodeBuild
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "arn:aws:logs:*:*:*"
      },
      # CloudFormation/CloudWatch (if used by your build/deploy)
      {
        Effect   = "Allow"
        Action   = ["cloudformation:*", "cloudwatch:*"]
        Resource = "*"
      }
    ]
  })
}


############################################
# 4) CodeBuild Project (source from CodePipeline)
############################################
resource "aws_codebuild_project" "terraform_build" {
  name         = "${var.project_name}-build"
  service_role = aws_iam_role.pipeline_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}


############################################
# 5) CodePipeline (CodeStarSourceConnection + DetectChanges)
############################################
resource "aws_codepipeline" "terraform_pipeline" {
  name           = "${var.project_name}-pipeline"
  role_arn       = aws_iam_role.pipeline_role.arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"

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
        ConnectionArn     = aws_codestarconnections_connection.github.arn
        FullRepositoryId  = "truelearnerarjun/terraform-cicd-capstone"
        BranchName        = "main"
        DetectChanges     = "true"  # enables auto-trigger on push via CodeStar Connections
        # Optional: OutputArtifactFormat = "CODEBUILD_CLONE_REF"
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


############################################
# 6) IAM Role for EC2 (CodeDeploy Agent)
############################################
resource "aws_iam_role" "ec2_codedeploy_role" {
  name = "${var.project_name}-ec2-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ec2_codedeploy_policy" {
  name = "${var.project_name}-ec2-codedeploy-policy"
  role = aws_iam_role.ec2_codedeploy_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CodeDeploy agent permissions
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeploymentConfig",
          "codedeploy:CreateDeploymentGroup",
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetDeploymentGroup",
          "codedeploy:GetDeploymentInstance",
          "codedeploy:ListApplicationRevisions",
          "codedeploy:ListDeploymentConfigs",
          "codedeploy:ListDeploymentGroups",
          "codedeploy:ListDeployments",
          "codedeploy:ListInstances",
          "codedeploy:PutLifecycleEventHookExecutionStatus",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:StopDeployment"
        ]
        Resource = "*"
      },
      # S3 access for deployment artifacts
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.codepipeline_bucket.arn,
          "${aws_s3_bucket.codepipeline_bucket.arn}/*"
        ]
      },
      # CloudWatch Logs for CodeDeploy
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_codedeploy_role.name
}