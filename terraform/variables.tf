variable "aws_region" {
  description = "AWS region for the project."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used in resource names."
  type        = string
  default     = "ecs-cicd-webapp"
}

variable "github_owner" {
  description = "GitHub username or organization."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_branch" {
  description = "Branch that triggers the pipeline."
  type        = string
  default     = "main"
}

variable "codestar_connection_arn" {
  description = "ARN of an AVAILABLE AWS CodeStar connection to GitHub."
  type        = string
}

variable "notification_email" {
  description = "Email address for SNS pipeline notifications."
  type        = string
}

variable "desired_count" {
  description = "Number of ECS tasks to run."
  type        = number
  default     = 2
}

variable "tags" {
  type = map(string)
  default = {
    Project = "aws-2048-cicd"
  }
}