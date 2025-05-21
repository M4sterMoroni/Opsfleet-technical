variable "aws_region" {
  description = "The AWS region for the production environment."
  type        = string
  default     = "us-east-1" 
}

variable "cluster_name" {
  description = "The name for the EKS cluster in the production environment."
  type        = string
  default     = "my-prod-eks-cluster"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC in the production environment."
  type        = string
  default     = "10.2.0.0/16"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster in the production environment."
  type        = string
  default     = "1.30" # Specify the desired EKS version for production
} 