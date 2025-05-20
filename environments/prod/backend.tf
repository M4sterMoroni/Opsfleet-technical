terraform {
  backend "s3" {
    # Replace with your actual S3 bucket and DynamoDB table for PRODUCTION
    # bucket         = "your-terraform-state-bucket-name-prod"
    # key            = "prod/eks-karpenter/terraform.tfstate"
    # region         = "us-east-1" # Should match your var.aws_region
    # encrypt        = true
    # use_lockfile   = true # Using S3 native locking - remove dynamodb_table if this is uncommented
  }
} 