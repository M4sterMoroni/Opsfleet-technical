module "eks_karpenter_stack" {
  source = "../../modules/eks_karpenter_stack"

  aws_region      = var.aws_region
  cluster_name    = var.cluster_name
  vpc_cidr        = var.vpc_cidr
  cluster_version = var.cluster_version
} 