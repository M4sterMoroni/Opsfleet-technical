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
*   Add detailed monitoring and logging for Karpenter and the EKS cluster.
*   Configure advanced network policies.
*   Add examples for stateful workloads.
*   Include different NodePools for on-demand instances if specific workloads require them (configurable per environment).
*   Add `staging` and `prod` environment examples with distinct configurations (e.g., different instance sizes, VPC CIDRs, cluster names).
*   Integrate with a CI/CD system (e.g., GitHub Actions, GitLab CI, AWS CodePipeline) to automate deployments per environment.