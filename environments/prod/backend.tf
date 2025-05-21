terraform {
  backend "s3" {
    # Replace with your actual S3 bucket and DynamoDB table for PRODUCTION
    # bucket         = "your-terraform-state-bucket-name-prod" # Provided by CI/CD
    # key            = "prod/eks-karpenter/terraform.tfstate"    # Provided by CI/CD
    # region         = "us-east-1" # Should match your var.aws_region / Provided by CI/CD
    encrypt        = true
    use_lockfile   = true # Enables S3 native locking - ensure S3 versioning is on the bucket
  }
} 