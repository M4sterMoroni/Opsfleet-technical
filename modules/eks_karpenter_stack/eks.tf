module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0" 

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable OIDC provider for IRSA
  enable_irsa = true

  # EKS Managed Node Group for x86 workloads
  eks_managed_node_groups = {
    x86_general_purpose = {
      name           = "x86-general-purpose"
      instance_types = ["m5.large", "m5a.large", "m6i.large"] # Example instance types
      min_size       = 1
      max_size       = 3
      desired_size   = 1

      labels = {
        "arch"        = "x86"
        "purpose"     = "general-purpose"
        "node-group"  = "x86-general-purpose"
      }
      tags = {
        "Name"                                  = "${var.cluster_name}-x86-general-purpose"
        "karpenter.sh/discovery"                = var.cluster_name 
      }
    }

    # EKS Managed Node Group for ARM64 (Graviton) workloads
    arm64_graviton = {
      name           = "arm64-graviton"
      instance_types = ["m6g.large", "m7g.large", "c6g.large"] # Example Graviton instance types
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      ami_type       = "AL2_ARM_64"

      labels = {
        "arch"        = "arm64"
        "purpose"     = "graviton-workloads"
        "node-group"  = "arm64-graviton"
      }
      tags = {
        "Name"                                  = "${var.cluster_name}-arm64-graviton"
        "karpenter.sh/discovery"                = var.cluster_name # Required for Karpenter to discover these nodes if needed
      }
    }
  }

  # Tags for the EKS cluster itself
  tags = {
    "Name"        = var.cluster_name
    "Environment" = "dev" # Example tag
    "Project"     = "startup-k8s" # Example tag
  }
}

# IAM role for Karpenter - needed for Karpenter to manage EC2 instances
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:karpenter:karpenter"
          }
        }
      },
    ]
  })

  tags = {
    Name = "${var.cluster_name}-karpenter-controller"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # For PoC, broad permissions. Restrict in production.
  role       = aws_iam_role.karpenter_controller.name
}

# This is the instance profile Karpenter will assign to nodes it provisions
resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name # Reference the node role defined below
   tags = {
    Name = "${var.cluster_name}-karpenter-node"
  }
}

# IAM Role that will be used by the nodes launched by Karpenter
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = {
    Name = "${var.cluster_name}-karpenter-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_node_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr_readonly_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node.name
}

# Required for SSM access (e.g. for AMI lookups or advanced troubleshooting)
resource "aws_iam_role_policy_attachment" "karpenter_node_ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node.name
}

# Allows nodes to publish metrics to CloudWatch
resource "aws_iam_role_policy_attachment" "karpenter_node_cloudwatch_agent_server_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.karpenter_node.name
} 