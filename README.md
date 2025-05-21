# EKS Cluster with Karpenter Autoscaling

This repository contains Terraform code to deploy an Amazon EKS (Elastic Kubernetes Service) cluster with Karpenter for advanced autoscaling capabilities. The cluster is deployed in a new dedicated VPC and is configured to support both x86 and ARM64 (Graviton) instance types, leveraging Spot instances for cost optimization.

This project is structured to be CI/CD friendly, using a modular approach where the core infrastructure is defined in a reusable module (`modules/eks_karpenter_stack`) and specific environments (e.g., `dev`, `staging`, `prod`) are defined in the `environments` directory.

## Prerequisites

Before you begin, ensure you have the following installed and configured:

*   **AWS CLI**: Configured with appropriate credentials and a default region. Ensure your IAM user/role has permissions to create the resources defined in this Terraform project (VPC, EKS, IAM roles, EC2 instances, etc.).
*   **Terraform**: Version 1.0 or later.
*   **kubectl**: Configured to interact with Kubernetes clusters.
*   **Helm**: Version 3.8 or later.

## Project Structure

```
.
├── README.md
├── modules
│   └── eks_karpenter_stack  // Reusable module for VPC, EKS, and Karpenter
│       ├── eks.tf
│       ├── karpenter.tf
│       ├── outputs.tf
│       ├── variables.tf
│       ├── versions.tf
│       └── vpc.tf
└── environments
    └── dev                 // Example 'dev' environment
        ├── backend.tf      // Terraform backend configuration (e.g., S3)
        ├── main.tf         // Instantiates the 'eks_karpenter_stack' module
        ├── outputs.tf      // Exports outputs for the dev environment
        ├── variables.tf    // Variables specific to the dev environment
        └── versions.tf     // Provider versions for dev
    └── prod                // Example 'prod' environment
        ├── backend.tf
        ├── main.tf
        ├── outputs.tf
        ├── variables.tf
        └── versions.tf
    #└── staging            // (Future environment)
```

## Deployment Instructions (Example for 'dev' environment)

1.  **Clone the repository:**

    ```bash
    git clone <repository-url>
    cd <repository-directory>
    ```

2.  **Navigate to the environment directory:**

    For example, to deploy the `dev` environment:
    ```bash
    cd environments/dev
    ```

3.  **Configure Terraform Backend (Important for CI/CD and Team Collaboration):**

    Open `backend.tf` and uncomment/configure the S3 backend (or your preferred backend) with your details. This is crucial for storing the Terraform state file remotely.

    Example (`backend.tf` using S3 native locking):
    ```terraform
    terraform {
      backend "s3" {
        bucket         = "your-terraform-state-s3-bucket-for-dev"
        key            = "dev/eks-karpenter/terraform.tfstate"
        region         = "us-east-1" # Or your desired region
        encrypt        = true
        use_lockfile   = true # Enables S3 native locking
      }
    }
    ```
    You will need to create the S3 bucket beforehand.

4.  **Initialize Terraform:**

    This command downloads the necessary provider plugins and modules for the selected environment.

    ```bash
    terraform init
    ```

5.  **Review the Terraform plan:**

    This command shows you what resources Terraform will create, modify, or delete for the `dev` environment.

    ```bash
    terraform plan
    ```
    You can also use a `.tfvars` file for environment-specific variable values (e.g., `terraform plan -var-file=dev.tfvars`).

6.  **Apply the Terraform configuration:**

    This command provisions the EKS cluster and all associated resources for the `dev` environment. Type `yes` when prompted.

    ```bash
    terraform apply
    ```

    This process can take 15-25 minutes.

7.  **Configure kubectl:**

    Once the `terraform apply` is complete for the environment, Terraform will output the necessary commands or values to configure `kubectl`.

    Typically, you can run:

    ```bash
    aws eks update-kubeconfig --name $(terraform output -raw eks_cluster_id) --region $(terraform output -raw aws_region)
    ```

8.  **Verify Cluster and Karpenter (as per previous instructions).**

## Running Workloads on Specific Architectures

To ensure your pod runs on an x86-based instance, you can use a `nodeSelector` or `nodeAffinity` in your pod/deployment manifest.

**Example using `nodeSelector`:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-x86
  labels:
    app: nginx-x86
spec:
  nodeSelector:
    kubernetes.io/arch: "amd64"
  containers:
  - name: nginx
    image: nginx:latest # Nginx official image supports amd64
    ports:
    - containerPort: 80
```

**Example using `nodeAffinity` (more flexible):**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-x86
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app-x86
  template:
    metadata:
      labels:
        app: my-app-x86
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                - "amd64"
      containers:
      - name: my-app-container
        image: your-x86-compatible-image:latest
        ports:
        - containerPort: 8080
```

When you apply these manifests, if no suitable x86 nodes are available, Karpenter will evaluate the pending pods and provision new x86 nodes (likely Spot instances, as configured in the `default-x86-spot` NodePool).

### Running a Pod on an ARM64 (Graviton) Instance

Similarly, to run your pod on an ARM64 (Graviton) instance:

**Example using `nodeSelector`:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-arm64
  labels:
    app: nginx-arm64
spec:
  nodeSelector:
    kubernetes.io/arch: "arm64"
  containers:
  - name: nginx
    image: arm64v8/nginx:latest # Nginx image for arm64
    ports:
    - containerPort: 80
```

**Example using `nodeAffinity`:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-arm64
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app-arm64
  template:
    metadata:
      labels:
        app: my-app-arm64
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                - "arm64"
      containers:
      - name: my-app-container
        image: your-arm64-compatible-image:latest 
        ports:
        - containerPort: 8080
```

When you apply these manifests, Karpenter will provision new ARM64 nodes (likely Spot Graviton instances from the `default-arm64-spot` NodePool) if no suitable ones are currently available.

### Important Considerations for Developers:

*   **Multi-arch Images**: If you have Docker images that support multiple architectures (e.g., built using `docker buildx`), Kubernetes will automatically pull the correct image variant for the node's architecture. If not, ensure you are pointing to the architecture-specific image tag (e.g., `arm64v8/nginx` or `myimage-arm64`).
*   **Karpenter NodePools**: The Terraform module sets up `NodePools` (`default-x86-spot` and `default-arm64-spot`) that define how Karpenter provisions nodes. These include requirements like instance architecture (`amd64`, `arm64`) and capacity type (`spot`). Pods matching these requirements will trigger Karpenter to provision nodes according to the NodePool's specification.
*   **Spot Instances**: Both NodePools are configured to prefer Spot instances for cost savings. Be aware of Spot instance interruptions and design your applications to be fault-tolerant.

## Cleanup (Example for 'dev' environment)

To destroy all the resources created by Terraform in a specific environment (e.g., `dev`):

1.  **Navigate to the environment directory:**

    ```bash
    cd environments/dev
    ```

2.  **Destroy the resources:**

    Type `yes` when prompted.

    ```bash
    terraform destroy
    ```

## Further Enhancements (TODO)

*   Implement more granular IAM permissions for Karpenter controller and nodes within the module.
*   Add detailed monitoring and logging for Karpenter and the EKS cluster. **(Partially Done: EKS control plane logs, Karpenter controller metrics enabled, Fluent Bit IAM role and Helm chart added for log forwarding. Full stack requires user deployment of Prometheus/Grafana & Fluent Bit data consumption.)**
*   Configure advanced network policies. **(Done: AWS VPC CNI Network Policy enforcement enabled.)**
*   Add examples for stateful workloads.
*   Include different NodePools for on-demand instances if specific workloads require them (configurable per environment).
*   Add `staging` and `prod` environment examples with distinct configurations (e.g., different instance sizes, VPC CIDRs, cluster names).
*   Integrate with a CI/CD system (e.g., GitHub Actions, GitLab CI, AWS CodePipeline) to automate deployments per environment.

## CI/CD Automation with GitHub Actions

This project includes GitHub Actions workflows located in the `.github/workflows` directory to automate testing, security scanning, and deployment of the infrastructure.

*   **`ci.yml` (Continuous Integration):** Triggered on pull requests to `main` and `develop` branches. It performs:
    *   Terraform code formatting checks (`fmt`).
    *   Terraform initialization (`init`) and validation (`validate`).
    *   **Checkov Scan**: Infrastructure-as-Code security scanning using [Checkov](https://www.checkov.io/). Results are uploaded to the GitHub Security tab.
    *   Terraform plan generation (`plan`) for the `dev` environment (by default). The plan is commented on the pull request.
*   **`cd.yml` (Continuous Deployment):** Triggered on pushes to `main` and `develop` branches:
    *   **`develop` branch:** Automatically deploys (applies) changes to the `dev` environment.
    *   **`main` branch:** Generates a Terraform plan for the `prod` environment. Deployment to `prod` requires manual approval within GitHub Actions.

### AWS Authentication using OpenID Connect (OIDC)

The workflows use OpenID Connect (OIDC) to securely authenticate with AWS, eliminating the need for long-lived AWS access keys stored as GitHub secrets. This involves setting up a trust relationship between GitHub Actions and AWS IAM.

**Steps to configure AWS for OIDC:**

1.  **Create an IAM OIDC Identity Provider in AWS:**
    *   In the AWS IAM console, navigate to "Identity providers" and click "Add provider".
    *   Select "OpenID Connect".
    *   Provider URL: `https://token.actions.githubusercontent.com`
    *   Audience: `sts.amazonaws.com`
    *   Click "Get thumbprint" and then "Add provider".

2.  **Create IAM Roles for GitHub Actions (for each environment - `dev`, `prod`):**
    *   In the IAM console, go to "Roles" and click "Create role".
    *   **Trusted entity type:** Select "Web identity".
    *   **Identity provider:** Choose the OIDC provider created in the previous step.
    *   **Audience:** Select `sts.amazonaws.com`.
    *   **GitHub repository access (Condition):** To restrict which repository and branches can assume this role, add a condition for the `StringLike` operator on `token.actions.githubusercontent.com:sub`:
        *   For the **dev** role (e.g., triggered by the `develop` branch):
            `repo:YOUR_GITHUB_ORG/YOUR_GITHUB_REPO:ref:refs/heads/develop`
        *   For the **prod** role (e.g., triggered by the `main` branch):
            `repo:YOUR_GITHUB_ORG/YOUR_GITHUB_REPO:ref:refs/heads/main`
        *   Replace `YOUR_GITHUB_ORG/YOUR_GITHUB_REPO` with your actual GitHub organization and repository name.
    *   **Permissions:** Attach IAM policies that grant the necessary permissions for Terraform to manage all resources defined in this project (VPC, EKS, IAM roles, EC2 instances, etc.). It's recommended to follow the principle of least privilege.
    *   **Role Name:** Give your roles meaningful names (e.g., `GitHubActions-Terraform-Dev`, `GitHubActions-Terraform-Prod`).
    *   Take note of the **ARN** for each role created.

### Required GitHub Secrets

Navigate to your GitHub repository's "Settings" > "Secrets and variables" > "Actions" and configure the following secrets:

*   **`AWS_IAM_ROLE_ARN_DEV`**: The ARN of the IAM role created for the `dev` environment that GitHub Actions will assume.
*   **`AWS_IAM_ROLE_ARN_PROD`**: The ARN of the IAM role created for the `prod` environment.
*   **`TF_STATE_BUCKET_DEV`**: The S3 bucket name for the `dev` environment's Terraform state.
*   **`TF_STATE_KEY_DEV`**: The S3 key for the `dev` environment's Terraform state (e.g., `dev/eks-karpenter/terraform.tfstate`).
*   **`TF_STATE_BUCKET_PROD`**: The S3 bucket name for the `prod` environment's Terraform state.
*   **`TF_STATE_KEY_PROD`**: The S3 key for the `prod` environment's Terraform state (e.g., `prod/eks-karpenter/terraform.tfstate`).
*   **`TF_STATE_REGION`**: The AWS region where your S3 state buckets are located (e.g., `us-east-1`).

**(Optional) Repository Variables:**

*   `AWS_REGION`: Can be used by the `aws-actions/configure-aws-credentials` action if `TF_STATE_REGION` secret is not set or if a general default region is preferred for other AWS CLI commands within workflows.

### Terraform Backend Configuration for CI/CD

The `backend.tf` files within each environment directory (`environments/dev/backend.tf`, `environments/prod/backend.tf`) should have the `bucket`, `key`, and `region` attributes for the S3 backend commented out or removed. The GitHub Actions workflows dynamically provide these settings during `terraform init` using the secrets configured above.

Example `environments/dev/backend.tf`:

```terraform
terraform {
  backend "s3" {
    # bucket         = "your-terraform-state-s3-bucket-for-dev" # Provided by CI/CD
    # key            = "dev/eks-karpenter/terraform.tfstate"    # Provided by CI/CD
    # region         = "us-east-1"                                # Provided by CI/CD
    encrypt        = true
    use_lockfile   = true # Enables S3 native locking
  }
}
```

## Monitoring and Logging

This module facilitates the collection of important logs and metrics:

*   **EKS Control Plane Logs**: All EKS control plane log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) are enabled and configured to be sent to AWS CloudWatch Logs. This is handled by the EKS module.
*   **Karpenter Controller Metrics**: The Karpenter controller is configured via its Helm chart to expose Prometheus-compatible metrics on port `8080`. You will need to deploy a Prometheus instance (such as Amazon Managed Service for Prometheus - AMP, or a self-managed Prometheus) and configure it to scrape the Karpenter controller pods.
*   **Karpenter Controller Logs**: Logs from the Karpenter controller pods can be collected using a standard Kubernetes logging solution and sent to a central logging system.
*   **Application & Node Logs (Log Forwarding Agent)**:
    *   **IAM Role**: An IAM role (`${var.cluster_name}-FluentBitRole`, output as `fluent_bit_iam_role_arn`) is created by this module with the necessary permissions for a logging agent like Fluent Bit to send logs to CloudWatch Logs. This role is pre-configured to trust a service account named `fluent-bit` in the `logging` namespace. You can adjust the trusted service account name and namespace in `modules/eks_karpenter_stack/iam.tf` if needed.
    *   **Logging Agent Deployment**: You are responsible for deploying a logging agent (e.g., Fluent Bit, Datadog, Splunk) to your cluster. When configuring your chosen agent, ensure its Kubernetes service account is configured to assume the IAM role provided by this module (`fluent_bit_iam_role_arn`) to grant it permissions to send logs to AWS CloudWatch Logs (or other desired destinations if you customize the role's policy).

### Example: Deploying Fluent Bit in an Environment (e.g., `environments/prod/logging.tf`)

If you choose to use Fluent Bit, you can deploy it via its Helm chart in your environment-specific Terraform configuration. Here's a conceptual example:

```terraform
# environments/prod/logging.tf

provider "helm" {
  kubernetes {
    host                   = module.eks_karpenter_stack.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_karpenter_stack.eks_cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token # Assumes you have a data source for EKS auth
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks_karpenter_stack.eks_cluster_id
}

locals {
  fluent_bit_helm_config = {
    chart      = "aws-for-fluent-bit"
    repository = "https://aws.github.io/eks-charts"
    version    = "0.1.31" # Or your desired version
    namespace  = "logging"  # Should match namespace in the IAM role trust
    create_namespace = true
  }
  fluent_bit_log_group_name_prefix = "/aws/containerinsights/${module.eks_karpenter_stack.eks_cluster_id}"
}

resource "helm_release" "fluent_bit_prod" {
  name       = "fluent-bit"
  chart      = local.fluent_bit_helm_config.chart
  repository = local.fluent_bit_helm_config.repository
  version    = local.fluent_bit_helm_config.version
  namespace  = local.fluent_bit_helm_config.namespace
  create_namespace = local.fluent_bit_helm_config.create_namespace

  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "fluent-bit" # Should match SA name in IAM role trust
  }
  set {
    name  = "serviceAccount.annotations.eks\.amazonaws\.com/role-arn" # Note: dot needs escaping for terraform set block
    value = module.eks_karpenter_stack.fluent_bit_iam_role_arn
  }

  values = [
    yamlencode({
      cloudWatchLogs = {
        enabled    = true
        region     = module.eks_karpenter_stack.aws_region # Use region from module output
        logGroupName = "${local.fluent_bit_log_group_name_prefix}/application"
      }
    })
  ]

  depends_on = [
    module.eks_karpenter_stack # Ensure cluster and IAM role are ready
  ]
}
```

### Visualizing Karpenter Metrics with Prometheus and Grafana

While this module does not deploy a full Prometheus and Grafana stack, here's a conceptual overview:

1.  **Deploy Prometheus**: Use the `kube-prometheus-stack` Helm chart or set up Amazon Managed Service for Prometheus (AMP).
2.  **Configure Scraping**: Ensure Prometheus is configured to scrape the Karpenter controller service. If using `kube-prometheus-stack`, a `ServiceMonitor` CRD might be automatically created by the Karpenter chart if enabled (check Karpenter chart options), or you may need to create one or add to Prometheus's scrape_configs.
    ```yaml
    # Example ServiceMonitor for Karpenter (if not created by chart)
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: karpenter-metrics
      namespace: kube-system # Or your Karpenter namespace
      labels:
        release: prometheus # Or your Prometheus release label
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: karpenter # Label of the Karpenter metrics service
      namespaceSelector:
        matchNames:
        - kube-system # Or your Karpenter namespace
      endpoints:
      - port: http-metrics # Name of the port in Karpenter's service (e.g., 8080)
        interval: 15s
    ```
3.  **Deploy Grafana**: Use the Grafana Helm chart or an existing Grafana instance.
4.  **Add Prometheus Data Source**: Configure Grafana to use your Prometheus instance as a data source.
5.  **Import Karpenter Dashboard**: Karpenter provides sample Grafana dashboards. You can find them in the [Karpenter GitHub repository](https://github.com/aws/karpenter/tree/main/grafana) and import them into your Grafana.

## Network Policies

This module enables Kubernetes Network Policy enforcement via the AWS VPC CNI plugin. This allows you to define fine-grained network traffic rules between your pods using standard `NetworkPolicy` Kubernetes resources.

By default, if no network policies are applied to a namespace, all ingress and egress traffic is allowed to and from pods in that namespace. Once any network policy is applied to a pod, it becomes "isolated," and only traffic explicitly allowed by a policy will be permitted.

### Example: Deny all traffic to an application

To deny all ingress traffic to pods with the label `app: my-secure-app` in the `default` namespace, you could apply the following:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-my-secure-app
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: my-secure-app
  policyTypes:
  - Ingress
  # No ingress rules defined, so all ingress is denied
```

### Example: Allow traffic from a specific namespace

To allow pods in namespace `frontend-ns` to connect to pods labelled `app: my-backend` on port `8080` in namespace `backend-ns`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: backend-ns
spec:
  podSelector:
    matchLabels:
      app: my-backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend-ns # or a custom label for the namespace
    ports:
    - protocol: TCP
      port: 8080
```
