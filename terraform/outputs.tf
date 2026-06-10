output "alb_url" {
  description = "Application Load Balancer URL."
  value       = "http://${aws_lb.app.dns_name}"
}

output "pipeline_name" {
  description = "CodePipeline name."
  value       = aws_codepipeline.app.name
}

output "ecr_repository_url" {
  description = "ECR repository URL."
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}
