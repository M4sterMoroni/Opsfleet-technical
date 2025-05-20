terraform {
  backend "s3" {
    # Replace with your actual S3 bucket
    # bucket         = "your-terraform-state-bucket-name-dev"
    # key            = "dev/eks-karpenter/terraform.tfstate"
    # region         = "us-east-1" # Should match your var.aws_region
    # encrypt        = true
    # use_lockfile   = true # Using S3 native locking
  }
} 