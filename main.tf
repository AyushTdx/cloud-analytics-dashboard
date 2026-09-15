terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "cloud-analytics-dev"
}

# ============================================================
# S3 BUCKET - FRONTEND
# ============================================================

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


# ============================================================
# CLOUDFRONT
# ============================================================

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-oac"
  description                       = "CloudFront access to private frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {

  enabled             = true
  comment             = "Cloud Analytics Dashboard"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {

    target_origin_id       = "s3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"

    compress = true

    allowed_methods = [
      "GET",
      "HEAD"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    forwarded_values {

      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {

    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


# ============================================================
# S3 BUCKET POLICY
# Allow CloudFront to read private S3 objects
# ============================================================

data "aws_iam_policy_document" "frontend_bucket" {

  statement {

    sid    = "AllowCloudFrontReadOnly"
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "cloudfront.amazonaws.com"
      ]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.frontend.arn}/*"
    ]

    condition {

      test     = "StringEquals"
      variable = "AWS:SourceArn"

      values = [
        aws_cloudfront_distribution.frontend.arn
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {

  bucket = aws_s3_bucket.frontend.id

  policy = data.aws_iam_policy_document.frontend_bucket.json
}


# ============================================================
# DYNAMODB
# ============================================================

resource "aws_dynamodb_table" "transactions" {

  name         = "demo-transaction-table"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "transaction_id"

  attribute {
    name = "transaction_id"
    type = "S"
  }
}


# ============================================================
# IAM ROLE FOR LAMBDA
# ============================================================

resource "aws_iam_role" "lambda" {

  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


# ============================================================
# YOUR DYNAMODB POLICY
# Scan + PutItem
# ============================================================

resource "aws_iam_role_policy" "lambda_dynamodb" {

  name = "${var.project_name}-dynamodb-access"

  role = aws_iam_role.lambda.id

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Sid    = "AllowLambdaDynamoDBAccess"
        Effect = "Allow"

        Action = [
          "dynamodb:Scan",
          "dynamodb:PutItem"
        ]

        Resource = aws_dynamodb_table.transactions.arn
      }
    ]
  })
}


# ============================================================
# LAMBDA BASIC EXECUTION ROLE
# CloudWatch Logs
# ============================================================

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {

  role = aws_iam_role.lambda.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# ============================================================
# LAMBDA FUNCTION
# ============================================================

data "archive_file" "lambda" {

  type = "zip"

  source_file = "${path.root}/../../backend/lambda/handler.py"

  output_path = "${path.root}/lambda.zip"
}

resource "aws_lambda_function" "api" {

  function_name = "${var.project_name}-api-handler"

  role = aws_iam_role.lambda.arn

  filename = data.archive_file.lambda.output_path

  source_code_hash = data.archive_file.lambda.output_base64sha256

  runtime = "python3.12"

  handler = "handler.lambda_handler"

  environment {

    variables = {
      TABLE_NAME = aws_dynamodb_table.transactions.name
    }
  }
}


# ============================================================
# API GATEWAY REST API
# ============================================================

resource "aws_api_gateway_rest_api" "api" {

  name = "${var.project_name}-api"
}


# ============================================================
# /transactions RESOURCE
# ============================================================

resource "aws_api_gateway_resource" "transactions" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  parent_id = aws_api_gateway_rest_api.api.root_resource_id

  path_part = "transactions"
}


# ============================================================
# GET /transactions
# ============================================================

resource "aws_api_gateway_method" "get_transactions" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.transactions.id

  http_method = "GET"

  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_transactions" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.transactions.id

  http_method = aws_api_gateway_method.get_transactions.http_method

  integration_http_method = "POST"

  type = "AWS_PROXY"

  uri = aws_lambda_function.api.invoke_arn
}


# ============================================================
# POST /transactions
# ============================================================

resource "aws_api_gateway_method" "post_transactions" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.transactions.id

  http_method = "POST"

  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_transactions" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  resource_id = aws_api_gateway_resource.transactions.id

  http_method = aws_api_gateway_method.post_transactions.http_method

  integration_http_method = "POST"

  type = "AWS_PROXY"

  uri = aws_lambda_function.api.invoke_arn
}


# ============================================================
# API GATEWAY → LAMBDA PERMISSION
# ============================================================

resource "aws_lambda_permission" "api_gateway" {

  statement_id = "AllowExecutionFromAPIGateway"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.api.function_name

  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}


# ============================================================
# API GATEWAY DEPLOYMENT
# ============================================================

resource "aws_api_gateway_deployment" "dev" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {

    redeployment = sha1(
      jsonencode([
        aws_api_gateway_method.get_transactions.id,
        aws_api_gateway_integration.get_transactions.id,

        aws_api_gateway_method.post_transactions.id,
        aws_api_gateway_integration.post_transactions.id
      ])
    )
  }

  lifecycle {

    create_before_destroy = true
  }

  depends_on = [

    aws_api_gateway_integration.get_transactions,

    aws_api_gateway_integration.post_transactions
  ]
}


# ============================================================
# DEV STAGE
# ============================================================

resource "aws_api_gateway_stage" "dev" {

  rest_api_id = aws_api_gateway_rest_api.api.id

  deployment_id = aws_api_gateway_deployment.dev.id

  stage_name = "Dev"
}


# ============================================================
# OUTPUTS
# ============================================================

output "frontend_bucket_name" {

  value = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {

  value = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {

  value = aws_cloudfront_distribution.frontend.domain_name
}

output "dynamodb_table_name" {

  value = aws_dynamodb_table.transactions.name
}

output "lambda_function_name" {

  value = aws_lambda_function.api.function_name
}

output "api_gateway_url" {

  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.dev.stage_name}/transactions"
}