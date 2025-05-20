resource "helm_release" "karpenter_crd" {
  namespace        = "kube-system"
  create_namespace = true

  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "v1.4.0" # Matching Karpenter version
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "v1.4.0"

  depends_on = [
    helm_release.karpenter_crd,
    aws_iam_role.karpenter_controller, 
    module.eks.eks_cluster 
  ]

  set {
    name  = "serviceAccount.annotations.eks.amazonaws.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }
  set {
    name  = "settings.aws.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "settings.aws.clusterEndpoint"
    value = module.eks.cluster_endpoint
  }
  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter_node.name
  }
  set {
    name  = "settings.aws.interruptionQueueName"
    value = "${var.cluster_name}-karpenter-interruption-queue" # This queue will be created by Karpenter itself if not present
  }

  set {
    name = "controller.resources.requests.cpu"
    value = "1"
  }
  set {
    name = "controller.resources.requests.memory"
    value = "1Gi"
  }
  set {
    name = "controller.resources.limits.cpu"
    value = "1"
  }
  set {
    name = "controller.resources.limits.memory"
    value = "1Gi"
  }
}

# --- EC2NodeClass Definitions --- #

resource "kubernetes_manifest" "karpenter_ec2nodeclass_x86" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name      = "default-x86"
      namespace = "karpenter"
    }
    spec = {
      amiFamily = "AL2"
      role      = aws_iam_role.karpenter_node.name # Role for nodes launched by Karpenter
      subnetSelectorTerms = [
        {
          tags = { "karpenter.sh/discovery" = var.cluster_name }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = { "karpenter.sh/discovery" = var.cluster_name }
        }
      ]
      tags = {
        "karpenter.sh/discovery" = var.cluster_name
        "purpose"                = "karpenter-x86-nodes"
      }
    }
  }
  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_ec2nodeclass_arm64" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name      = "default-arm64"
      namespace = "karpenter"
    }
    spec = {
      amiFamily = "Bottlerocket" # Bottlerocket is a good choice for ARM64
      role      = aws_iam_role.karpenter_node.name
      subnetSelectorTerms = [
        {
          tags = { "karpenter.sh/discovery" = var.cluster_name }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = { "karpenter.sh/discovery" = var.cluster_name }
        }
      ]
      tags = {
        "karpenter.sh/discovery" = var.cluster_name
        "purpose"                = "karpenter-arm64-nodes"
      }
    }
  }
  depends_on = [helm_release.karpenter]
}

# --- NodePool Definitions --- #

resource "kubernetes_manifest" "karpenter_nodepool_x86_spot" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name      = "default-x86-spot"
      namespace = "karpenter"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "type" = "karpenter-x86-spot"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = kubernetes_manifest.karpenter_ec2nodeclass_x86.metadata.name
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["2"] } 
          ]
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      disruption = {
        consolidationPolicy = "WhenUnderutilized"
        consolidateAfter    = "30s"
        expireAfter         = "7d" # Equivalent to AWSNodeTemplate ttlSecondsUntilExpired
      }
    }
  }
  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_x86]
}

resource "kubernetes_manifest" "karpenter_nodepool_arm64_spot" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name      = "default-arm64-spot"
      namespace = "karpenter"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "type" = "karpenter-arm64-spot"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = kubernetes_manifest.karpenter_ec2nodeclass_arm64.metadata.name
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["arm64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] }, # Graviton instances fall into these
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["2"] } 
          ]
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
      disruption = {
        consolidationPolicy = "WhenUnderutilized"
        consolidateAfter    = "30s"
        expireAfter         = "7d"
      }
    }
  }
  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_arm64]
} 