# ecs-cicd-webapp

Containerized FastAPI web application deployed to Amazon ECS Fargate with Terraform-managed AWS infrastructure and a GitHub Actions CI/CD pipeline.

This project demonstrates a practical cloud deployment workflow: provisioning AWS infrastructure with Terraform, packaging a Python application with Docker, pushing images to Amazon ECR, running containers on ECS behind an Application Load Balancer, and deploying new versions automatically from GitHub.

## Architecture Overview

The application runs in AWS `us-east-1` as an ECS Fargate service. Public HTTP traffic reaches an Application Load Balancer, which forwards requests to ECS tasks on container port `8000`. Docker images are stored in Amazon ECR. GitHub Actions authenticates to AWS using OIDC, builds and tags the Docker image, pushes it to ECR, registers a new ECS task definition revision, updates the ECS service, waits for stability, and verifies the deployment through the ALB `/version` endpoint.

## Architecture Flow

```text
Developer pushes to main
        |
        v
GitHub Actions
        |
        |-- Configure AWS credentials with OIDC
        |-- Build Docker image from ./app
        |-- Tag image with Git commit SHA
        |-- Push image to Amazon ECR
        |-- Download current ECS task definition
        |-- Register new task definition revision
        |-- Update ECS service
        |-- Wait for service stability
        |-- Verify ALB /version endpoint
        |
        v
Amazon ECS Fargate
        |
        v
Application Load Balancer -> FastAPI container on port 8000
```

## Tech Stack

| Area | Technology |
| --- | --- |
| Cloud provider | AWS |
| Region | `us-east-1` |
| Infrastructure as Code | Terraform |
| Application | Python, FastAPI |
| Runtime server | Gunicorn with Uvicorn worker |
| Containerization | Docker |
| Container registry | Amazon ECR |
| Compute | Amazon ECS Fargate |
| Load balancing | Application Load Balancer |
| Logging | Amazon CloudWatch Logs |
| CI/CD | GitHub Actions |
| AWS authentication | GitHub OIDC and IAM |

## Repository Structure

```text
.
|-- .github/
|   `-- workflows/
|       `-- deploy-ecs.yml
|-- app/
|   |-- Dockerfile
|   |-- main.py
|   `-- requirements.txt
|-- terraform/
|   |-- main.tf
|   |-- outputs.tf
|   |-- providers.tf
|   |-- variables.tf
|   |-- version.tf
|   `-- .terraform.lock.hcl
|-- .gitignore
|-- buildspec.yml
`-- README.md
```

## Application

The application is a small FastAPI service designed for container deployment and pipeline verification.

| Endpoint | Purpose |
| --- | --- |
| `/` | HTML page showing app name, version, and response time |
| `/health` | Health endpoint used by the ALB target group |
| `/version` | JSON version endpoint used after deployment |

The container listens on port `8000` and runs FastAPI with Gunicorn and a Uvicorn worker:

```dockerfile
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000", "main:app"]
```

## Terraform Infrastructure

Terraform provisions the AWS infrastructure needed to run and deploy the application:

- VPC with DNS support and DNS hostnames enabled
- Two public subnets across available Availability Zones
- Internet Gateway, route table, and public route associations
- Application Load Balancer listening on port `80`
- ALB target group forwarding to ECS tasks on port `8000`
- ALB health checks using `/health`
- Security group for public HTTP access to the ALB
- Security group allowing ECS task traffic from the ALB security group
- Amazon ECR repository with image scanning on push
- ECS cluster
- ECS Fargate task definition
- ECS service named `ecs-cicd-webapp`
- CloudWatch log group for ECS container logs
- IAM task execution role for ECS
- S3 artifact bucket, CodeBuild, CodePipeline, SNS, and notification resources from an earlier AWS-native pipeline path

The ECS service includes:

```hcl
lifecycle {
  ignore_changes = [task_definition]
}
```

This lets Terraform create and manage the ECS service while GitHub Actions deploys new task definition revisions without Terraform rolling the service back on the next apply.

## Terraform Outputs

The deployment process uses these Terraform outputs:

```powershell
terraform output -raw ecs_cluster_name
terraform output -raw ecs_service_name
terraform output -raw ecr_repository_url
terraform output -raw alb_url
```

These values are currently stored as GitHub repository variables:

```text
ECS_CLUSTER_NAME
ECS_SERVICE_NAME
ECR_REPOSITORY_URL
ALB_URL
```

If the Terraform project is destroyed and recreated, values such as the ALB URL, ECR repository URL, ECS cluster name, or ECS service name may change. The GitHub repository variables should be updated after recreation.

## CI/CD Pipeline

The GitHub Actions workflow is located at:

```text
.github/workflows/deploy-ecs.yml
```

The workflow runs on pushes to `main` when files under `app/` or the workflow file itself change.

Pipeline steps:

1. Check out the repository with `actions/checkout@v5`.
2. Configure AWS credentials with `aws-actions/configure-aws-credentials@v6`.
3. Authenticate to AWS using an IAM role assumed through GitHub OIDC.
4. Log in to Amazon ECR with `aws-actions/amazon-ecr-login@v2`.
5. Build the Docker image from `./app`.
6. Tag the image using the short Git commit SHA.
7. Push the SHA-tagged image and the `latest` tag to ECR.
8. Download the current ECS task definition.
9. Update the task definition JSON with the new image URI.
10. Register a new ECS task definition revision.
11. Update the ECS service to use the new revision.
12. Wait for the ECS deployment to become stable.
13. Verify the deployment by calling the ALB `/version` endpoint.

## GitHub Actions Configuration

Required repository variables:

| Variable | Description |
| --- | --- |
| `ECS_CLUSTER_NAME` | ECS cluster name from Terraform output |
| `ECS_SERVICE_NAME` | ECS service name from Terraform output. For this project: `ecs-cicd-webapp` |
| `ECR_REPOSITORY_URL` | ECR repository URL from Terraform output |
| `ALB_URL` | Application Load Balancer URL from Terraform output |

Required repository secret:

| Secret | Description |
| --- | --- |
| `ECS_CICD_WEBAPP_GITHUB_ACTIONS_ROLE` | IAM role ARN assumed by GitHub Actions through OIDC |

Example AWS credentials step:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: ${{ secrets.ECS_CICD_WEBAPP_GITHUB_ACTIONS_ROLE }}
    aws-region: us-east-1
```

## IAM and OIDC

This project uses GitHub OIDC instead of storing long-lived AWS access keys in GitHub.

OIDC requirements:

- AWS IAM OIDC provider: `token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`
- IAM role trust policy restricted to this repository and the `main` branch

The GitHub Actions deployment role needs permissions for:

- ECR login and image push
- ECS describe services
- ECS describe task definition
- ECS register task definition
- ECS update service
- IAM `PassRole` for the ECS task execution role and any task role used by the task definition

## Manual Bootstrap Deployment

Before CI/CD can deploy new ECS task definition revisions, the initial `bootstrap` image must exist in ECR because the Terraform task definition references it.

```powershell
cd terraform

$repo = terraform output -raw ecr_repository_url

docker build -t "${repo}:bootstrap" ../app
docker push "${repo}:bootstrap"

aws ecs update-service `
  --cluster $(terraform output -raw ecs_cluster_name) `
  --service $(terraform output -raw ecs_service_name) `
  --force-new-deployment

$url = terraform output -raw alb_url
Invoke-RestMethod "$url/version"
```

## Security and Git Hygiene

This project follows common infrastructure-as-code hygiene practices by keeping local state, local variables, generated files, virtual environments, and environment files out of version control.

Do not commit:

- `.terraform/`
- `terraform.tfstate`
- `terraform.tfstate.backup`
- `terraform.tfvars`
- `.env` files
- Python cache files and virtual environments

The Terraform provider lock file, `.terraform.lock.hcl`, can be committed because it records selected provider versions and helps make Terraform runs more reproducible.

Security decisions demonstrated:

- GitHub Actions uses OIDC instead of static AWS access keys.
- IAM trust policy should be limited to the intended repository and branch.
- ECS task ingress is limited to traffic from the ALB security group.
- ECR image scanning is enabled on push.
- S3 artifact bucket public access is blocked.
- S3 artifact bucket server-side encryption is enabled.
- ECS logs are sent to CloudWatch with a defined retention period.

## Troubleshooting Lessons Learned

Issues identified and fixed while building the deployment flow:

- GitHub Actions workflows must live under `.github/workflows/`.
- Secret names in workflow files must exactly match the configured GitHub repository secret.
- An empty `ECR_REPOSITORY_URL` creates invalid Docker tags such as `:1d064e4`.
- `ECS_SERVICE_NAME` must be set and must match the actual ECS service name, `ecs-cicd-webapp`.
- Using current GitHub Actions versions avoids Node.js 20 deprecation warnings:
  - `actions/checkout@v5`
  - `aws-actions/configure-aws-credentials@v6`
  - `aws-actions/amazon-ecr-login@v2`

## Screenshots

Suggested screenshots to add:

| Screenshot | What to show |
| --- | --- |
| Application homepage | Browser view of the ALB URL |
| `/version` endpoint | JSON response after a successful deployment |
| GitHub Actions run | Successful build, push, and ECS deployment |
| ECS service | Stable service with desired tasks running |
| ECR repository | SHA-tagged and `latest` images |
| ALB target group | Healthy registered targets |

## Future Improvements

- Move Terraform state to an S3 backend with DynamoDB state locking.
- Have GitHub Actions run `terraform init` and read Terraform outputs automatically.
- Replace manually stored repository variables with values from remote Terraform state.
- Add `prevent_destroy = true` to protect the ECR repository from accidental deletion.
- Add HTTPS support with ACM and an ALB HTTPS listener.
- Add a custom domain with Route 53.
- Add automated tests before building and pushing Docker images.
- Add image vulnerability reporting or deployment gates based on ECR scan results.
- Split infrastructure into Terraform modules as the project grows.

Future GitHub Actions output reads could use:

```bash
terraform output -raw ecs_cluster_name
terraform output -raw ecs_service_name
terraform output -raw ecr_repository_url
terraform output -raw alb_url
```

## Skills Demonstrated

- AWS networking with VPCs, subnets, route tables, and security groups
- ECS Fargate service deployment behind an Application Load Balancer
- Docker image creation for a Python FastAPI application
- Gunicorn and Uvicorn production serving pattern for ASGI apps
- Amazon ECR image tagging and publishing
- Terraform infrastructure provisioning and output management
- ECS task definition revision management
- GitHub Actions CI/CD workflow design
- GitHub OIDC authentication with AWS IAM
- IAM permissions for ECS and ECR deployment workflows
- CloudWatch logging for containerized workloads
- Infrastructure security and version-control hygiene

