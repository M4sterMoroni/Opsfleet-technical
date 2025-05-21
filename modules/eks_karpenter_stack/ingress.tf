resource "aws_wafv2_web_acl" "alb_waf" {
  count = var.enable_cloudfront_waf ? 1 : 0
  name  = "${var.cluster_name}-waf-acl"
  scope = "CLOUDFRONT" # Scope for CloudFront distribution

  default_action {
    allow {}
  }

  # Rule: AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "awsCommonRules"
      sampled_requests_enabled   = true
    }
  }

  # Rule: AWS Managed Rules - Amazon IP Reputation List (optional, can add more)
  # rule {
  #   name     = "AWSManagedRulesAmazonIpReputationList"
  #   priority = 2
  #   override_action {
  #     none {}
  #   }
  #   statement {
  #     managed_rule_group_statement {
  #       vendor_name = "AWS"
  #       name        = "AWSManagedRulesAmazonIpReputationList"
  #     }
  #   }
  #   visibility_config {
  #     cloudwatch_metrics_enabled = true
  #     metric_name                = "awsIpReputation"
  #     sampled_requests_enabled   = true
  #   }
  # }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "albWafAcl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.cluster_name}-waf-acl"
    Environment = var.tags.Environment # Assuming you have a common Environment tag
    Project     = var.tags.Project     # Assuming you have a common Project tag
  }
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  count = var.enable_cloudfront_waf ? 1 : 0

  origin {
    domain_name = var.alb_dns_name # This needs to be the DNS of your ALB
    origin_id   = "ALB-${var.cluster_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # CloudFront to ALB communication can be HTTP
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.cluster_name}"
  default_root_object = "index.html" # Optional: if you have a default root object

  # Aliases for custom domain names
  aliases = var.custom_domain_names

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-${var.cluster_name}"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      headers = ["Host", "Origin", "Referer", "Authorization"] # Forward common headers, adjust as needed
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300 # Cache for 5 minutes by default, adjust based on content
    max_ttl                = 86400 # Cache for 1 day max

    # lambda_function_association {
    #   event_type   = "viewer-request"
    #   lambda_arn   = "arn:aws:lambda:us-east-1:123456789012:function:my-function:1" # Example for Lambda@Edge
    #   include_body = false
    # }
  }

  price_class = "PriceClass_100" # Price Class 100: North America and Europe.

  restrictions {
    geo_restriction {
      restriction_type = "none" # Or whitelist/blacklist specific countries
      # locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    # If using custom domain names, ACM certificate is required
    cloudfront_default_certificate = var.acm_certificate_arn == "" ? true : false
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != "" ? "TLSv1.2_2021" : "TLSv1"
  }

  # Associate WAF Web ACL
  web_acl_id = aws_wafv2_web_acl.alb_waf[0].arn

  logging_config {
    include_cookies = false
    bucket          = "your-cloudfront-logs-s3-bucket.s3.amazonaws.com" # CHANGE THIS or make it a variable
    prefix          = "${var.cluster_name}/"
  }

  tags = {
    Name        = "${var.cluster_name}-cf-distro"
    Environment = var.tags.Environment
    Project     = var.tags.Project
  }

  # Ensure ALB is created if this module also creates it, or it exists.
  # depends_on = [module.your_alb_module] # If ALB is in another module
} 