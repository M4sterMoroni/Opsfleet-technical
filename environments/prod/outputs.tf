# Outputs from the eks_karpenter_stack module

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.eks_karpenter_stack.vpc_id
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.eks_karpenter_stack.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.eks_karpenter_stack.private_subnets
}

output "eks_cluster_id" {
  description = "The name/id of the EKS cluster."
  value       = module.eks_karpenter_stack.eks_cluster_id
}

output "eks_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the EKS cluster."
  value       = module.eks_karpenter_stack.eks_cluster_arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server."
  value       = module.eks_karpenter_stack.eks_cluster_endpoint
}

output "eks_cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL for the EKS cluster."
  value       = module.eks_karpenter_stack.eks_cluster_oidc_issuer_url
}

output "eks_cluster_oidc_provider_arn" {
  description = "The OIDC provider ARN for the EKS cluster."
  value       = module.eks_karpenter_stack.eks_cluster_oidc_provider_arn
}

output "karpenter_controller_iam_role_arn" {
  description = "The ARN of the IAM role for the Karpenter controller."
  value       = module.eks_karpenter_stack.karpenter_controller_iam_role_arn
}

output "karpenter_node_iam_instance_profile_name" {
  description = "The name of the IAM instance profile for Karpenter-provisioned nodes."
  value       = module.eks_karpenter_stack.karpenter_node_iam_instance_profile_name
}

output "aws_region" {
  description = "AWS region for this environment"
  value       = var.aws_region
} 