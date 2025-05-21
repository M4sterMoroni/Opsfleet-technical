module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0" 

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = var.enable_irsa

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64" 
    instance_types = ["m5.large"] 
  }

  eks_managed_node_groups = {
    initial_core_nodes = {
      name           = "${var.cluster_name}-core-nodes"
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      instance_types = ["m5.large"]
    }
  }
  
  # EKS Addons Configuration
  cluster_addons = {
    vpc-cni = {
      most_recent = true 
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  access_entries = {
    karpenter_node_access = {
      principal_arn = aws_iam_role.karpenter_node_role.arn # From iam.tf
      policy_associations = {
        karpenter_node_policy = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodePolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Tags
  tags = {
    Environment = "dev" # Example tag
    Project     = "EKSKarpenter"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned" 
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
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" 
  role       = aws_iam_role.karpenter_controller.name
}

# This is the instance profile Karpenter will assign to nodes it provisions
resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.karpenter_node.name 
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