# Terraform CI/CD Capstone

AWS CI/CD pipeline with Terraform for automated infrastructure deployment.

## Overview

- **Infrastructure**: VPC, ALB, EC2 instances (t3.micro) with Apache
- **CI/CD**: GitHub → CodePipeline → CodeBuild → CodeDeploy
- **Automation**: Auto-trigger on git push, terraform plan/apply

## Quick Start

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

## Architecture

```
GitHub (main branch) → CodePipeline → CodeBuild (plan/apply) → EC2 Deployment
```

## Key Files

- `terraform/` - Infrastructure code
- `buildspec.yml` - CodeBuild configuration
- `terraform/user_data.sh` - EC2 bootstrap with CodeDeploy agent

## Outputs

```bash
terraform output
# Returns:
# - alb_dns_name
# - web1_instance_id
# - web2_instance_id
```

## IAM Setup

- **CodeBuild Role**: Terraform, EC2, IAM, S3, logs permissions
- **EC2 Role**: CodeDeploy, S3 artifact access

## Cleanup

```bash
terraform destroy -auto-approve
```

## Troubleshooting

- **Permission Errors**: Check IAM role policies
- **CodeDeploy Agent**: `sudo systemctl status codedeploy-agent`
- **GitHub Connection**: Authorize in AWS Console → Connections