# Terraform CI/CD Capstone Project - Complete Overview

## 🎯 Project Summary

This is a **fully automated Terraform CI/CD pipeline** that deploys a scalable AWS infrastructure with:
- **Application Load Balancer (ALB)** for traffic distribution
- **2 EC2 Instances** running web servers
- **VPC & Networking** with public subnets
- **CI/CD Pipeline** that automatically deploys on Git push
- **Configuration Drift Prevention** to detect unauthorized changes

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Complete Flow                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. Developer pushes code to GitHub (main branch)       │
│             ↓                                            │
│  2. CodePipeline triggered                
│             ↓                                            │
│  3. CodeBuild pulls code from GitHub                    │
│             ↓                                            │
│  4. CodeBuild runs buildspec.yml commands               │
│             ↓                                            │
│  5. Terraform deploys AWS infrastructure                │
│             ↓                                            │
│  6. ALB + EC2 instances created/updated                 │
│             ↓                                            │
│  7. Configuration drift detected automatically          │
│             ↓                                            │
│  8. Infrastructure live and accessible                  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
terraform-cicd-capstone/
├── buildspec.yml              # ← Build configuration
├── terraform/
│   ├── provider.tf            # AWS provider & state backend
│   ├── variables.tf           # Input variables
│   ├── pipeline.tf            # CodePipeline & CodeBuild
│   ├── network.tf             # VPC & Subnets
│   ├── alb.tf                 # Load Balancer
│   ├── ec2.tf                 # Web Servers
│   ├── security.tf            # Security Groups
│   ├── routes.tf              # Route Tables
│   ├── outputs.tf             # Output values
│   └── user_data.sh           # EC2 initialization
├── README.md                  # Project documentation
└── aws/                       # AWS installation scripts
```

---

## 🔑 Key Components Explained

### 1️⃣ **buildspec.yml** - The Build Instructions

This file tells CodeBuild **exactly what to do** when code is pushed.

```yaml
version: 0.2

phases:
  install:
    # Download and install Terraform
    - curl -O https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
    - unzip -o terraform_1.7.5_linux_amd64.zip
    - mv terraform /usr/local/bin/

  build:
    # The actual build steps
    - cd terraform
    - terraform init           # Download providers & setup
    - terraform validate       # Check for syntax errors
    - terraform plan           # Show what will change (DRIFT DETECTION!)
    - terraform apply          # Apply the changes
```

**What Happens:**

| Step | Purpose | Detects Drift? |
|------|---------|---|
| `terraform init` | Connects to state file (S3) | - |
| `terraform validate` | Checks syntax | - |
| `terraform plan` | Compares code vs AWS | ✅ YES |
| `terraform apply` | Applies changes to AWS | - |

**Drift Detection:**
```bash
terraform plan -detailed-exitcode
# Exit code 0 = No changes needed (no drift)
# Exit code 2 = Changes detected (DRIFT DETECTED!)
```

---

### 2️⃣ **variables.tf** - Configuration Parameters

Defines inputs that can be customized without changing code.

```hcl
variable "aws_region" {
  default = "us-east-1"
  # Region where infrastructure is deployed
}

variable "project_name" {
  default = "group2-cicd"
  # Prefix for all resource names (ALB, VPC, etc.)
}
```

**Usage:**
- Resources reference these: `"${var.project_name}-alb"` → `"group2-cicd-alb"`
- Easy to change: just update defaults or pass via CLI
- Keeps code DRY (Don't Repeat Yourself)

---

### 3️⃣ **provider.tf** - AWS Connection & State Storage

Configures how Terraform connects to AWS and stores state.

```hcl
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket = "group2-terraform-state"  # Where state is stored
    key    = "cicd/terraform.tfstate"   # File path in S3
    region = "us-east-1"
    encrypt = true                      # Encrypt state (SECURITY!)
  }
}

provider "aws" {
  region = var.aws_region              # us-east-1
}
```

**Key Points:**

| Config | Purpose |
|--------|---------|
| `backend "s3"` | State file saved in S3 (not local) |
| `encrypt = true` | State file encrypted at rest |
| `provider "aws"` | Connects to AWS account |

**Why S3 Backend?**
- ✅ Shared state (team can collaborate)
- ✅ Encrypted (sensitive data protected)
- ✅ Centralized (single source of truth)

---

### 4️⃣ **pipeline.tf** - CI/CD Infrastructure

Creates the CodePipeline, CodeBuild, and IAM roles.

#### **Part 1: Artifact Bucket**
```hcl
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.project_name}-artifacts-${random_id.suffix.hex}"
  # Stores build artifacts (terraform plans, etc.)
}
```

#### **Part 2: GitHub Connection**
```hcl
resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
  # Connects AWS to GitHub for pulling code
}
```

#### **Part 3: IAM Role (Permissions)**
```hcl
resource "aws_iam_role" "pipeline_role" {
  # Defines what CodeBuild is allowed to do
  # Can: create EC2, ALB, modify IAM roles
  # Cannot: delete databases, access Lambda, etc.
}

resource "aws_iam_role_policy" "pipeline_policy" {
  # Grants specific permissions:
  # - s3:*              (S3 access for artifacts & state)
  # - codepipeline:*    (Manage pipeline)
  # - codebuild:*       (Run builds)
  # - ec2:*             (Create/modify instances)
  # - elasticloadbalancing:* (ALB management)
  # - iam:PassRole      (Pass roles to resources)
  # - logs:*            (Write logs)
  # - cloudformation:*  (Stack management)
  # - events:*          (EventBridge)
}
```

#### **Part 4: CodeBuild Project**
```hcl
resource "aws_codebuild_project" "terraform_build" {
  name         = "group2-cicd-build"
  service_role = aws_iam_role.pipeline_role.arn
  
  # Uses buildspec.yml to build
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}
```

#### **Part 5: CodePipeline**
```hcl
resource "aws_codepipeline" "terraform_pipeline" {
  name = "group2-cicd-pipeline"
  
  stage {
    name = "Source"
    # Pull from GitHub main branch
  }
  
  stage {
    name = "Build"
    # Run CodeBuild (executes buildspec.yml)
  }
}
```

**Pipeline Flow:**
```
GitHub Push → Source Stage → Build Stage → Infrastructure Updated
```

---

### 5️⃣ **network.tf** - VPC & Networking

Creates the foundation for all resources.

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  # VPC network range (65,536 IP addresses)
}

resource "aws_subnet" "public_1" {
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  # Public subnet in Availability Zone A
  # Instances here get public IPs
}

resource "aws_subnet" "public_2" {
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  # Public subnet in Availability Zone B (High Availability)
}
```

**Network Diagram:**
```
┌─ VPC (10.0.0.0/16) ──────────────────┐
│                                       │
│  ┌─ Subnet 1 (10.0.1.0/24) ──────┐  │
│  │  └─ EC2 Instance 1 (web1)     │  │
│  │     └─ Public IP               │  │
│  └────────────────────────────────┘  │
│                                       │
│  ┌─ Subnet 2 (10.0.2.0/24) ──────┐  │
│  │  └─ EC2 Instance 2 (web2)     │  │
│  │     └─ Public IP               │  │
│  └────────────────────────────────┘  │
│                                       │
└───────────────────────────────────────┘
```

---

### 6️⃣ **alb.tf** - Application Load Balancer

Distributes traffic across EC2 instances.

```hcl
resource "aws_lb" "alb" {
  name               = "group2-cicd-alb"
  load_balancer_type = "application"
  # Listens on port 80 (HTTP)
}

resource "aws_lb_target_group" "tg" {
  port     = 80
  protocol = "HTTP"
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
  }
  # Checks if instances are healthy
  # Removes unhealthy instances from rotation
}

resource "aws_lb_target_group_attachment" "a1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
  # Attach web1 to load balancer
}

resource "aws_lb_target_group_attachment" "a2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
  # Attach web2 to load balancer
}
```

**Traffic Flow:**
```
User Request
    ↓
ALB (group2-cicd-alb)
    ├─→ Health Check ✓ → Route to web1
    ├─→ Health Check ✓ → Route to web2
    └─→ Health Check ✗ → Bypass unhealthy instance
```

---

### 7️⃣ **ec2.tf** - Web Servers

Creates 2 EC2 instances for redundancy.

```hcl
resource "aws_instance" "web1" {
  ami                    = "ami-0532be01f26a3de55"  # Ubuntu 22.04
  instance_type          = "t3.micro"               # Small, cost-effective
  subnet_id              = aws_subnet.public_1.id   # In subnet 1
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = file("${path.module}/user_data.sh")
  # Runs user_data.sh on startup (install web server, etc.)
}

resource "aws_instance" "web2" {
  ami                    = "ami-0532be01f26a3de55"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_2.id   # In subnet 2
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = file("${path.module}/user_data.sh")
}
```

**Why 2 Instances?**
- ✅ High Availability (if one fails, other still runs)
- ✅ Load distribution
- ✅ Zero downtime deployments

---

### 8️⃣ **security.tf** - Security Groups

Controls inbound/outbound traffic.

```hcl
resource "aws_security_group" "ec2_sg" {
  # Inbound: Allow HTTP (port 80) from ALB
  # Outbound: Allow all traffic out
}

resource "aws_security_group" "alb_sg" {
  # Inbound: Allow HTTP (port 80) from internet
  # Outbound: Allow all traffic out
}
```

---

### 9️⃣ **outputs.tf** - Display Results

Shows important information after deployment.

```hcl
output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.alb.dns_name
  # Output: group2-cicd-alb-12345.us-east-1.elb.amazonaws.com
}

output "web1_instance_id" {
  description = "Instance ID of web1"
  value       = aws_instance.web1.id
  # Output: i-08c272573b7ac6343
}
```

---

### 🔟 **user_data.sh** - EC2 Initialization

Runs when EC2 instances start (typically installs web server).

```bash
#!/bin/bash
# Install Nginx
sudo apt-get update
sudo apt-get install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

---

## 🔄 How Configuration Drift Prevention Works

### **Without Drift Prevention:**
```
1. Deploy with Terraform ✓
2. Someone manually deletes security group in AWS Console
3. Code says "security group exists" but AWS says "it's gone"
4. NOBODY KNOWS THERE'S A PROBLEM ❌
5. Infrastructure is broken
```

### **With Our Implementation:**
```
1. Deploy with Terraform ✓
2. Someone manually deletes security group
3. Next git push triggers pipeline
4. terraform plan runs
5. Plan shows: "Security group missing, will recreate it"
6. terraform apply fixes it automatically ✓
```

**How We Detect It:**
```hcl
# In buildspec.yml
terraform plan -detailed-exitcode -out=tfplan || DRIFT=$?

# Exit codes:
# 0 = No changes (no drift)
# 2 = Changes detected (DRIFT!) ⚠️
```

---

## 🚀 Complete Deployment Flow

### **Step-by-Step Execution:**

```
Time 0: Developer makes change
  └─ Edits alb.tf or ec2.tf
  └─ git add .
  └─ git commit -m "Add new instance"
  └─ git push origin main

Time 1: GitHub receives push
  └─ CodePipeline automatically triggered
  └─ (No manual intervention needed!)

Time 2: CodePipeline Source Stage
  └─ Connects to GitHub via CodeStar
  └─ Pulls code from main branch
  └─ Stores code in S3 artifact bucket

Time 3: CodePipeline Build Stage
  └─ Launches CodeBuild project
  └─ Downloads buildspec.yml
  └─ Creates build environment

Time 4: CodeBuild Install Phase
  └─ Downloads Terraform 1.7.5
  └─ Installs to /usr/local/bin

Time 5: CodeBuild Build Phase
  └─ terraform init
      └─ Downloads AWS provider
      └─ Loads state from S3
      └─ Connects to Terraform backend
      
  └─ terraform validate
      └─ Checks syntax
      └─ Verifies resource configuration
      
  └─ terraform plan
      └─ Connects to AWS
      └─ Fetches current infrastructure
      └─ Compares with .tf files
      └─ Shows what WILL change
      └─ If changes exist: Exit code 2 (drift detected!)
      
  └─ terraform apply
      └─ Executes the plan
      └─ Creates/updates resources
      └─ Updates state file in S3

Time 6: Infrastructure Updated
  └─ EC2 instances created/updated
  └─ ALB configured
  └─ Security groups active
  └─ Ready for traffic

Time 7: Verification
  └─ ALB DNS name returned
  └─ Accessible via browser
  └─ EC2 instances running
  └─ Load balanced

Total time: ~5-10 minutes
```

---

## 📋 State File Management

### **Where is State Stored?**

```
S3 Bucket: group2-terraform-state
  └─ cicd/terraform.tfstate
```

**Why S3?**
- ✅ Centralized (team can see same state)
- ✅ Persistent (survives pipeline restarts)
- ✅ Versioned (can rollback if needed)
- ✅ Encrypted (sensitive data protected)

**State Contains:**
- Current resource IDs (i-12345, sg-67890)
- Resource attributes (instance type, security group rules)
- Metadata (creation timestamps, provider versions)

---

## 🔐 Security Features

### **1. IAM Role Permissions (Principle of Least Privilege)**
- ✅ Only allows what's needed
- ✅ Cannot delete databases or Lambda
- ✅ Limited to EC2, ALB, networking

### **2. State File Encryption**
- ✅ All sensitive data encrypted
- ✅ Access logs in CloudTrail
- ✅ Versioning enabled for recovery

### **3. GitHub Connection Secure**
- ✅ OAuth authentication
- ✅ Limited to main branch
- ✅ CodeStar manages credentials

### **4. Security Groups**
- ✅ HTTP only (port 80)
- ✅ HTTPS ready (can add port 443)
- ✅ No SSH access from internet

---

## 📊 Key Metrics & Information

### **After Deployment, You Get:**
```
ALB DNS Name: group2-cicd-alb-2134044368.us-east-1.elb.amazonaws.com
Instance 1 ID: i-08c272573b7ac6343
Instance 2 ID: i-01f6daefeca88619f

To Access Website:
http://group2-cicd-alb-2134044368.us-east-1.elb.amazonaws.com
```

### **Terraform Outputs:**
```bash
alb_dns_name = "group2-cicd-alb-2134044368.us-east-1.elb.amazonaws.com"
web1_instance_id = "i-08c272573b7ac6343"
web2_instance_id = "i-01f6daefeca88619f"
```

---

## 🔧 How to Modify & Deploy

### **Modify Instance Type:**
```hcl
# In ec2.tf
resource "aws_instance" "web1" {
  instance_type = "t3.small"  # Changed from t3.micro
}
```

### **Add Another Instance:**
```hcl
# In ec2.tf
resource "aws_instance" "web3" {
  ami                    = "ami-0532be01f26a3de55"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = file("${path.module}/user_data.sh")
}

# In alb.tf
resource "aws_lb_target_group_attachment" "a3" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web3.id
  port             = 80
}
```

### **Deploy Changes:**
```bash
git add .
git commit -m "Add web3 instance"
git push origin main
# Pipeline automatically runs!
```

---

## 📈 Cost Estimation

| Resource | Size | Monthly Cost |
|----------|------|---|
| t3.micro EC2 | 2x | ~$10 |
| ALB | 1x | ~$20 |
| S3 (state + artifacts) | 50MB | ~$1 |
| **Total** | - | **~$31/month** |

---

## ✅ Testing the Pipeline

### **Test 1: Deploy from Scratch**
```bash
cd terraform
terraform destroy -auto-approve  # Delete all
terraform apply                  # Redeploy
# Should take 5-10 minutes
```

### **Test 2: Simulate Drift**
```bash
# Manually delete a security group in AWS Console
# Push code to GitHub
# Pipeline automatically recreates it ✓
```

### **Test 3: Update Infrastructure**
```bash
# Edit ec2.tf to change instance type
# git push
# Pipeline updates without destroying ✓
```

---

## 🎓 Key Learning Points

1. **Infrastructure as Code** - All AWS resources defined in .tf files
2. **CI/CD Automation** - Changes deploy automatically on git push
3. **State Management** - Terraform tracks infrastructure state in S3
4. **IAM Security** - Permissions follow principle of least privilege
5. **Configuration Drift** - Automatically detects and fixes unauthorized changes
6. **High Availability** - 2 instances + load balancer = no single point of failure
7. **Declarative Infrastructure** - Describe desired state, Terraform makes it happen

---

## 📞 Quick Reference

| Task | Command |
|------|---------|
| Deploy locally | `cd terraform && terraform apply` |
| Check state | `terraform state list` |
| See outputs | `terraform output` |
| Destroy | `terraform destroy` |
| Format code | `terraform fmt` |
| View plan | `terraform plan` |

---

## 🎯 Summary

This project demonstrates:
- ✅ Complete CI/CD pipeline from code to production
- ✅ Automated infrastructure deployment
- ✅ Configuration drift prevention
- ✅ High availability & load balancing
- ✅ Security best practices
- ✅ Infrastructure as Code principles

**The entire workflow is automated - just push code and infrastructure deploys automatically!** 🚀

