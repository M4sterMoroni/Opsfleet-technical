variable "aws_region" {
  description = "AWS region for the EKS cluster."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "The name for the EKS cluster and associated resources."
  type        = string
  default     = "my-eks-cluster"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "karpenter_service_account_name" {
  description = "The name of the Kubernetes service account for Karpenter."
  type        = string
  default     = "karpenter"
}

variable "karpenter_service_account_namespace" {
  description = "The Kubernetes namespace where the Karpenter service account resides."
  type        = string
  default     = "kube-system"
}

# Variables for the EKS module itself (can be extended)
variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "enable_irsa" {
  description = "Whether to create an IAM OIDC provider and enable IRSA."
  type        = bool
  default     = true
} 