output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "database_subnets" { 
  description = "List of IDs of database subnets"
  value = module.vpc.database_subnets
}

output "eks_cluster_id" {
  description = "The name/id of the EKS cluster."
  value       = module.eks.cluster_id
}

output "eks_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "eks_oidc_provider_arn" {
  description = "The ARN of the IAM OIDC provider for the EKS cluster."
  value       = module.eks.oidc_provider_arn
}

output "eks_oidc_provider_url" {
  description = "The URL of the OIDC provider (issuer URL without https://)."
  value       = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role for Karpenter-managed nodes."
  value       = aws_iam_role.karpenter_node_role.arn
}

output "karpenter_node_instance_profile_arn" {
  description = "ARN of the IAM instance profile for Karpenter-managed nodes."
  value       = aws_iam_instance_profile.karpenter_node_instance_profile.arn
}

output "karpenter_controller_role_arn" {
  description = "ARN of the IAM role for the Karpenter controller."
  value       = aws_iam_role.karpenter_controller_role.arn
}

output "karpenter_interruption_queue_arn" {
  description = "ARN of the SQS queue for Karpenter interruption handling."
  value       = aws_sqs_queue.karpenter_interruption_queue.arn
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS queue for Karpenter interruption handling."
  value       = aws_sqs_queue.karpenter_interruption_queue.name
}

output "karpenter_node_iam_instance_profile_name" {
  description = "The name of the IAM instance profile for Karpenter-provisioned nodes."
  value       = aws_iam_instance_profile.karpenter_node_instance_profile.name
}

output "fluent_bit_iam_role_arn" {
  description = "ARN of the IAM role for Fluent Bit to send logs to CloudWatch."
  value       = aws_iam_role.fluent_bit_role.arn
}

output "eks_cluster_primary_security_group_id" {
  description = "The ID of the EKS cluster's primary security group."
  value       = module.eks.cluster_primary_security_group_id
}

output "eks_node_security_group_id" {
  description = "The ID of the security group associated with the EKS managed nodes and often used by self-managed nodes or Fargate profiles."
  value       = module.eks.node_security_group_id
} 