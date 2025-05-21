resource "helm_release" "karpenter_crd" {
  namespace        = var.karpenter_service_account_namespace
  create_namespace = true

  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = local.karpenter_helm_config.version
  depends_on = [
    module.eks
  ]
}

locals {
  karpenter_helm_config = {
    chart            = "karpenter"
    repository       = "oci://public.ecr.aws/karpenter"
    version          = "v0.36.1" # Specify a recent, stable version of Karpenter chart. Adjust as needed.
    namespace        = var.karpenter_service_account_namespace
    create_namespace = true      # Ensure the namespace exists if deploying to a dedicated 'karpenter' ns
  }
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  chart      = local.karpenter_helm_config.chart
  repository = local.karpenter_helm_config.repository
  version    = local.karpenter_helm_config.version
  namespace  = local.karpenter_helm_config.namespace
  create_namespace = local.karpenter_helm_config.create_namespace

  # Wait for the EKS cluster and OIDC provider to be ready, and CRDs to be applied
  depends_on = [
    module.eks,
    helm_release.karpenter_crd
  ]

  set {
    name  = "serviceAccount.create"
    value = "true" # Let the chart create the service account
  }
  set {
    name  = "serviceAccount.name"
    value = var.karpenter_service_account_name
  }
  set {
    name  = "serviceAccount.annotations.eks.amazonaws.com/role-arn"
    value = aws_iam_role.karpenter_controller_role.arn 
  }
  set {
    name  = "settings.aws.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "settings.aws.clusterEndpoint"
    value = module.eks.cluster_endpoint # From eks.tf output
  }
  set {
    name  = "settings.aws.interruptionQueueName"
    value = aws_sqs_queue.karpenter_interruption_queue.name # From iam.tf
  }
  set {
    name = "controller.metrics.enabled"
    value = "true"
  }
  set {
    name = "controller.metrics.port"
    value = "8080" # Default metrics port for Karpenter
  }
  values = [
    yamlencode({
      controller = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    })
  ]
}

# --- EC2NodeClass Definitions --- #

resource "kubernetes_manifest" "karpenter_ec2nodeclass_x86" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name      = "default-x86"
      namespace = var.karpenter_service_account_namespace
    }
    spec = {
      amiFamily = "AL2"
      role      = aws_iam_role.karpenter_node_role.name
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
      namespace = var.karpenter_service_account_namespace
    }
    spec = {
      amiFamily = "Bottlerocket"
      role      = aws_iam_role.karpenter_node_role.name
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
      namespace = var.karpenter_service_account_namespace
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
            name  = kubernetes_manifest.karpenter_ec2nodeclass_x86.object.metadata.name
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
        expireAfter         = "7d" 
      }
    }
  }
  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_x86, helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_nodepool_arm64_spot" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name      = "default-arm64-spot"
      namespace = var.karpenter_service_account_namespace
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
            name  = kubernetes_manifest.karpenter_ec2nodeclass_arm64.object.metadata.name
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
  depends_on = [kubernetes_manifest.karpenter_ec2nodeclass_arm64, helm_release.karpenter]
}