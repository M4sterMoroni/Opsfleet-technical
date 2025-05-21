module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0" 

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  enable_irsa = var.enable_irsa

  # EKS Managed Node Groups - Define a minimal one for core services if not using Fargate for everything
  # For a pure Karpenter setup, this might be very small or eventually removed if core components run on Fargate
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64" # Or AL2_ARM_64 if preferred for core nodes
    instance_types = ["m5.large"] # Small instance type for core components
    # associate_cluster_primary_security_group = true # Often useful
  }

  eks_managed_node_groups = {
    initial_core_nodes = {
      name           = "${var.cluster_name}-core-nodes"
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      instance_types = ["m5.large"]
      # These core nodes will use the default role created by the EKS module.
      # Karpenter nodes will use the specific karpenter_node_role.
    }
  }
  
  access_entries = {
    karpenter_node_access = {
      principal_arn = aws_iam_role.karpenter_node_role.arn # From iam.tf
      # The AmazonEKSNodePolicy grants the necessary permissions for nodes to join and operate.
      # The username (system:node:{{EC2PrivateDNSName}}) and groups (system:bootstrappers, system:nodes)
      # are effectively covered by this policy and EKS internal node registration mechanisms.
      policy_associations = {
        karpenter_node_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodePolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
      # type = "EC2_LINUX" # This can be specified if needed, defaults usually work for IAM roles.
    }
    # Add other access entries if needed
  }

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Tags
  tags = {
    Environment = "dev" # Example tag
    Project     = "EKSKarpenter"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned" # For resource discovery
  }

  # Add other EKS module configurations as needed
  # e.g., cluster_endpoint_public_access, etc.
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