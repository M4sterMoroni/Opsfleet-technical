resource "helm_release" "karpenter_crd" {
  namespace        = "kube-system"
  create_namespace = true

  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "v1.4.0" # Matching Karpenter version
}

locals {
  karpenter_helm_config = {
    chart            = "karpenter"
    repository       = "oci://public.ecr.aws/karpenter"
    version          = "v0.36.1" # Specify a recent, stable version of Karpenter chart. Adjust as needed.
    namespace        = var.karpenter_service_account_namespace # Typically kube-system or karpenter
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

  # Wait for the EKS cluster and OIDC provider to be ready
  depends_on = [
    module.eks
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
    value = aws_iam_role.karpenter_controller_role.arn # From iam.tf
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
    # Ensure metrics are enabled (usually on by default, but explicit is good)
    # The exact path for metrics settings can vary slightly by chart version.
    # For recent versions, metrics are under a top-level `metrics` block or `controller.metrics`.
    # Assuming controller.metrics based on common patterns for v0.3x
    name = "controller.metrics.enabled"
    value = "true"
  }
  set {
    name = "controller.metrics.port"
    value = "8080" # Default metrics port for Karpenter
  }
  # Example: If using Prometheus Operator, you might enable ServiceMonitor creation
  # set {
  #   name = "controller.metrics.serviceMonitor.enabled"
  #   value = "true"
  # }

  # Add any other necessary Karpenter Helm chart values
  # For example, resource requests/limits for the controller, affinity, etc.
  values = [
    yamlencode({
      # Example: if you need to set the AWS default instance profile for nodes launched by Karpenter
      # (though EC2NodeClass is the more modern way to specify this)
      # settings = {
      #   aws = {
      #     defaultInstanceProfile = aws_iam_instance_profile.karpenter_node_instance_profile.name
      #   }
      # }

      # Example resource settings for the Karpenter controller pod
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

# Default EC2NodeClass - can be customized or have multiple for different needs
resource "kubernetes_manifest" "karpenter_default_ec2nodeclass" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1" # Use v1beta1 for recent Karpenter versions
    kind       = "EC2NodeClass"
    metadata   = {
      name      = "default" # Name of the EC2NodeClass
      namespace = var.karpenter_service_account_namespace
    }
    spec = {
      amiFamily = "AL2" # Bottlerocket, Ubuntu, etc. are also options
      role      = aws_iam_role.karpenter_node_role.name # From iam.tf
      # Ensure subnets and security groups are tagged for discovery by Karpenter for this NodeClass
      # Or specify them directly using subnetSelectorTerms and securityGroupSelectorTerms
      subnetSelectorTerms = [
        {
          tags = { "karpenter.sh/discovery" = var.cluster_name }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = { "karpenter.sh/discovery" = var.cluster_name } # This should match the EKS cluster's primary SG or node SG
          # It's common to use the cluster's primary security group or a dedicated node security group
          # Ensure module.eks.node_security_group_id or module.eks.cluster_primary_security_group_id is tagged appropriately
        }
      ]
      # Example: If you need to specify specific instance profile
      # instanceProfile = aws_iam_instance_profile.karpenter_node_instance_profile.name

      # Tags to apply to instances launched by this NodeClass
      tags = {
        "karpenter.sh/managed-by" = var.cluster_name
        "InstanceType"            = "karpenter-dynamic"
      }
    }
  }
  depends_on = [helm_release.karpenter] # Ensure Karpenter CRDs are available
}

# Default NodePool - can be customized or have multiple
resource "kubernetes_manifest" "karpenter_default_nodepool" {
  manifest = {
    apiVersion = "karpenter.sh/v1beta1" # Use v1beta1 for recent Karpenter versions
    kind       = "NodePool"
    metadata   = {
      name      = "default" # Name of the NodePool
      namespace = var.karpenter_service_account_namespace
    }
    spec = {
      template = {
        spec = {
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"] # Prioritize Spot, fallback to On-Demand
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64", "arm64"]
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            }
            # Add more specific instance type requirements if needed
            # e.g., instance category, generation, size, etc.
            # {
            #   key = "karpenter.k8s.aws/instance-category",
            #   operator = "In",
            #   values = ["m", "c", "r"]
            # },
            # {
            #   key = "karpenter.k8s.aws/instance-generation",
            #   operator = "Gt",
            #   values = ["5"] # Example: 5th gen or newer for m,c,r series
            # }
          ]
          nodeClassRef = {
            name = kubernetes_manifest.karpenter_default_ec2nodeclass.object.metadata.name
          }
          # Optional: Taints, labels, kubelet configuration for nodes in this pool
        }
      }
      limits = {
        # Optional: Define limits on CPU/memory for this NodePool
        # cpu    = "1000"
        # memory = "4000Gi"
      }
      disruption = {
        consolidationPolicy = "WhenUnderutilized" # Or "WhenEmpty"
        consolidateAfter    = "30s" # How long a node must be eligible for consolidation before Karpenter acts
        # Optional: Define expiration for nodes in this pool
        # expireAfter = "720h" # e.g., 30 days
      }
    }
  }
  depends_on = [kubernetes_manifest.karpenter_default_ec2nodeclass] # Ensure EC2NodeClass exists
} 