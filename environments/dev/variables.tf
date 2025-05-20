variable "aws_region" {
  description = "The AWS region for the dev environment."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "The name for the EKS cluster in the dev environment."
  type        = string
  default     = "my-dev-eks-cluster"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC in the dev environment."
  type        = string
  default     = "10.1.0.0/16"
} 