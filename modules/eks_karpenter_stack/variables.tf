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
  default     = "1.32"
}

variable "enable_irsa" {
  description = "Enable IRSA for the EKS cluster."
  type        = bool
  default     = true
}

# Variables for CloudFront and WAF
variable "enable_cloudfront_waf" {
  description = "Set to true to create CloudFront distribution and WAF WebACL for the ALB."
  type        = bool
  default     = false
}

variable "alb_dns_name" {
  description = "DNS name of the Application Load Balancer to be fronted by CloudFront. Required if enable_cloudfront_waf is true."
  type        = string
  default     = ""
}

variable "custom_domain_names" {
  description = "Optional: List of custom domain names (e.g., ['app.example.com']) for the CloudFront distribution. Requires acm_certificate_arn."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "Optional: ACM certificate ARN for the custom domain names specified in custom_domain_names. Required if custom_domain_names is not empty."
  type        = string
  default     = ""
} 