data "aws_iam_policy_document" "karpenter_node_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_node_role" {
  name               = "${var.cluster_name}-KarpenterNodeRole"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_assume_role_policy.json
  path               = "/"

  tags = {
    Name                                      = "${var.cluster_name}-KarpenterNodeRole"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_node_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node_role.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node_role.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node_role.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Required for SSM agent to run on nodes, used by Karpenter for some AMI lookups
  role       = aws_iam_role.karpenter_node_role.name
}

resource "aws_iam_instance_profile" "karpenter_node_instance_profile" {
  name = "${var.cluster_name}-KarpenterNodeProfile"
  role = aws_iam_role.karpenter_node_role.name

  tags = {
    Name                                      = "${var.cluster_name}-KarpenterNodeProfile"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

locals {
  karpenter_controller_policy_name = "${var.cluster_name}-KarpenterControllerPolicy"
  karpenter_interruption_queue_name = var.cluster_name # Using cluster_name for the queue name as per CFN template
}

# --- Karpenter Controller IAM Role and Policy ---
data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn] # Directly from EKS module output
    }

    condition {
      test     = "StringEquals"
      # Use replace to remove "https://" from the OIDC issuer URL for the condition
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.karpenter_service_account_namespace}:${var.karpenter_service_account_name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller_role" {
  name               = "${var.cluster_name}-KarpenterControllerRole"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json
  path               = "/"

  tags = {
    Name                                      = "${var.cluster_name}-KarpenterControllerRole"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

resource "aws_iam_policy" "karpenter_controller_policy" {
  name        = local.karpenter_controller_policy_name
  path        = "/"
  description = "IAM policy for Karpenter controller for cluster ${var.cluster_name}"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowScopedEC2InstanceAccessActions"
        Effect   = "Allow"
        Action   = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::image/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::snapshot/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:security-group/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:subnet/*"
        ]
      },
      {
        Sid    = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:spot-instances-request/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:RequestTag/eks:eks-cluster-name"                     = var.cluster_name
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:spot-instances-request/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:RequestTag/eks:eks-cluster-name"                     = var.cluster_name,
            "ec2:CreateAction"                                        = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceTagging"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
          StringEqualsIfExists = {
            "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name
          }
          ForAllValuesStringEquals = {
            "aws:TagKeys" = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowRegionalReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}::parameter/aws/service/*"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid    = "AllowInterruptionQueueActions"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter_interruption_queue.arn
      },
      {
        Sid    = "AllowPassingInstanceRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.karpenter_node_role.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["ec2.amazonaws.com", "ec2.amazonaws.com.cn"]
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileCreationActions"
        Effect = "Allow"
        Action = ["iam:CreateInstanceProfile"]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"    = "owned",
            "aws:RequestTag/eks:eks-cluster-name"                        = var.cluster_name,
            "aws:RequestTag/topology.kubernetes.io/region"               = data.aws_region.current.name # Karpenter adds this tag
          }
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*" # Karpenter adds this tag
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileTagActions"
        Effect = "Allow"
        Action = ["iam:TagInstanceProfile"]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:ResourceTag/topology.kubernetes.io/region"            = data.aws_region.current.name,
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:RequestTag/eks:eks-cluster-name"                     = var.cluster_name,
            "aws:RequestTag/topology.kubernetes.io/region"            = data.aws_region.current.name
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"   = "*",
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileActions"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:ResourceTag/topology.kubernetes.io/region"            = data.aws_region.current.name
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Action   = "iam:GetInstanceProfile"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = module.eks.cluster_arn
      }
    ]
  })

  tags = {
    Name                                      = local.karpenter_controller_policy_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_policy_attach" {
  role       = aws_iam_role.karpenter_controller_role.name
  policy_arn = aws_iam_policy.karpenter_controller_policy.arn
}

# --- Karpenter Interruption Handling Resources ---
resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name                        = local.karpenter_interruption_queue_name
  message_retention_seconds   = 300
  sqs_managed_sse_enabled     = true # Enable server-side encryption using SQS owned encryption keys

  tags = {
    Name                                      = local.karpenter_interruption_queue_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption_queue_policy" {
  queue_url = aws_sqs_queue.karpenter_interruption_queue.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Id        = "EC2InterruptionPolicy"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = ["events.amazonaws.com", "sqs.amazonaws.com"] # Allow EventBridge and SQS itself to send messages
        }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter_interruption_queue.arn
      },
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.karpenter_interruption_queue.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_scheduled_change_rule" {
  name          = "${var.cluster_name}-KarpenterScheduledChange"
  description   = "EventBridge rule for AWS Health Scheduled Change events for Karpenter"
  event_pattern = jsonencode({
    source      = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
  })

  tags = {
    Name                                      = "${var.cluster_name}-KarpenterScheduledChange"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_scheduled_change_target" {
  rule      = aws_cloudwatch_event_rule.karpenter_scheduled_change_rule.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption_rule" {
  name        = "${var.cluster_name}-KarpenterSpotInterruption"
  description = "EventBridge rule for EC2 Spot Instance Interruption Warnings for Karpenter"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = {
    Name                                      = "${var.cluster_name}-KarpenterSpotInterruption"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption_target" {
  rule      = aws_cloudwatch_event_rule.karpenter_spot_interruption_rule.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance_rule" {
  name        = "${var.cluster_name}-KarpenterRebalance"
  description = "EventBridge rule for EC2 Instance Rebalance Recommendations for Karpenter"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = {
    Name                                      = "${var.cluster_name}-KarpenterRebalance"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance_target" {
  rule      = aws_cloudwatch_event_rule.karpenter_rebalance_rule.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state_change_rule" {
  name        = "${var.cluster_name}-KarpenterInstanceStateChange"
  description = "EventBridge rule for EC2 Instance State-change Notifications for Karpenter"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })
  tags = {
    Name                                      = "${var.cluster_name}-KarpenterInstanceStateChange"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state_change_target" {
  rule      = aws_cloudwatch_event_rule.karpenter_instance_state_change_rule.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter_interruption_queue.arn
}

# --- Fluent Bit IAM Role for CloudWatch Logs (IRSA) ---
data "aws_iam_policy_document" "fluent_bit_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      # Assuming Fluent Bit runs in 'logging' namespace with 'fluent-bit' service account
      # Users will need to create this SA and namespace, or adjust these values.
      values   = ["system:serviceaccount:logging:fluent-bit"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fluent_bit_role" {
  name               = "${var.cluster_name}-FluentBitRole"
  assume_role_policy = data.aws_iam_policy_document.fluent_bit_assume_role_policy.json
  path               = "/"

  tags = {
    Name                                      = "${var.cluster_name}-FluentBitRole"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_iam_policy" "fluent_bit_cloudwatch_logs_policy" {
  name        = "${var.cluster_name}-FluentBitCloudWatchLogsPolicy"
  path        = "/"
  description = "Allows Fluent Bit to send logs to CloudWatch Logs for cluster ${var.cluster_name}"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "cloudwatch:PutLogEvents",
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:*:*" # Wide for simplicity, can be scoped down
      }
    ]
  })

  tags = {
    Name                                      = "${var.cluster_name}-FluentBitCloudWatchLogsPolicy"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_iam_role_policy_attachment" "fluent_bit_cloudwatch_logs_attach" {
  role       = aws_iam_role.fluent_bit_role.name
  policy_arn = aws_iam_policy.fluent_bit_cloudwatch_logs_policy.arn
} 