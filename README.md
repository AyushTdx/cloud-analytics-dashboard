# Cloud Analytics Dashboard Demo

A small end-to-end AWS serverless analytics platform built as a hands-on cloud engineering POC. The project demonstrates a static dashboard, REST API, serverless compute, NoSQL storage, IAM least privilege, CDN delivery, Infrastructure as Code, and a path toward CI/CD.

## What this project demonstrates

- AWS serverless architecture
- Static frontend hosting with Amazon S3 and CloudFront
- CloudFront Origin Access Control (OAC) for a private S3 origin
- REST API with API Gateway
- Python AWS Lambda backend
- DynamoDB transaction storage
- IAM least-privilege access for Lambda
- Terraform-based Infrastructure as Code
- GitHub Actions deployment target
- CloudWatch observability target
- Practical troubleshooting across the browser → CDN → API → compute → database path
- AWS resource cleanup and cost awareness

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         CLOUD ANALYTICS PLATFORM                    │
│                                                                     │
│   USERS / EDGE                                                     │
│                                                                     │
│   ┌───────────┐       HTTPS       ┌──────────────────────┐          │
│   │   User    │ ─────────────────►│      CloudFront      │          │
│   └───────────┘                   │ CDN / HTTPS / Cache  │          │
│                                   └─────────┬────────────┘          │
│                                             │                       │
│                           ┌─────────────────┴─────────────┐         │
│                           │                               │         │
│                      Static Assets                    /api/*        │
│                           │                               │         │
│                           ▼                               ▼         │
│                    ┌────────────┐                  ┌────────────┐  │
│                    │ S3 Bucket  │                  │API Gateway │  │
│                    │   PRIVATE  │                  │    REST    │  │
│                    └────────────┘                  └─────┬──────┘  │
│                                                         │         │
│                                                         ▼         │
│                                                   ┌──────────┐    │
│                                                   │  Lambda  │    │
│                                                   │  Python  │    │
│                                                   └────┬─────┘    │
│                                                        │          │
│                                                        ▼          │
│                                                   ┌──────────┐    │
│                                                   │ DynamoDB │    │
│                                                   │Transactions│  │
│                                                   └──────────┘    │
│                                                                     │
│   DEVOPS / IaC                                                     │
│                                                                     │
│   ┌──────────┐     ┌──────────────┐     ┌──────────┐                │
│   │  GitHub  │────►│GitHub Actions│────►│ Terraform│                │
│   └──────────┘     └──────┬───────┘     └────┬─────┘                │
│                           │                    │                    │
│                           └──── Deploy ────────┘                    │
│                                                                     │
│   OBSERVABILITY / SECURITY                                          │
│                                                                     │
│        ┌────────────┐                         ┌───────────┐          │
│        │ CloudWatch │                         │    IAM    │          │
│        │ Logs/Alarms│                         │ Policies  │          │
│        └────────────┘                         └───────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

### Request flow

```text
Static frontend:
Browser → CloudFront → private S3

Backend API:
Browser → API Gateway → Lambda → DynamoDB
```

## Project status

The POC was implemented incrementally:

- S3 + CloudFront frontend: completed
- DynamoDB transaction table: completed
- Python Lambda API: completed
- API Gateway REST API with `GET /transactions`: completed
- `POST /transactions`: included in the backend/API design
- Frontend API integration: completed for summary metrics and transaction table
- Dynamic daily-volume chart: future enhancement
- CloudFront `/api/*` routing: intended production-style extension
- GitHub Actions CI/CD: planned/next implementation stage
- Terraform: configuration prepared; existing manually created resources should be imported or replaced with a fresh Terraform-managed environment rather than blindly applying over them
- CloudWatch alarms/monitoring: planned hardening stage

## Frontend

The dashboard provides:

- Total transactions
- Completed transactions
- Failed transactions
- Pending transactions
- Average processing time
- Status breakdown
- Recent transaction table
- Seven-day transaction-volume visualization
- API-backed refresh functionality

The dashboard initially used local demo data so the UI could be deployed independently. It was later connected to the API for live summary and transaction data.

The frontend configuration uses an API URL such as:

```javascript
const CONFIG = {
  API_URL: "https://<api-id>.execute-api.<region>.amazonaws.com/Dev/transactions"
};
```

Do not commit credentials or secrets into `config.js`. An API endpoint is not a secret, but environment-specific configuration is generally better managed through deployment configuration in a production application.

## Backend API

The Lambda API reads from DynamoDB and returns a response shaped approximately like:

```json
{
  "summary": {
    "total": 11,
    "completed": 7,
    "failed": 3,
    "pending": 1,
    "avg_processing_time": 2.42
  },
  "transactions": []
}
```

The project exposed the REST endpoint through an API Gateway `Dev` stage.

### DynamoDB

The transaction table stores fields such as:

- `transaction_id`
- `timestamp`
- `automation_name`
- `status`
- `processing_time`
- `customer`
- `error_message`

The Lambda function uses the table name through an environment variable such as `TABLE_NAME`.

## IAM

The Lambda execution role was given only the DynamoDB actions required by the application:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLambdaDynamoDBAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:767397765208:table/demo-transaction-table"
    }
  ]
}
```

For a public repository, consider replacing the account-specific ARN above with a placeholder or Terraform reference. Never publish AWS access keys, secret keys, passwords, private keys, or other credentials.

## Deployment

### Current/manual POC

The original POC was deployed manually to AWS:

1. Upload frontend files to S3.
2. Serve the frontend through CloudFront.
3. Create the DynamoDB table.
4. Create the Lambda function and execution role.
5. Create the API Gateway REST API and `/transactions` resource.
6. Configure Lambda integration.
7. Deploy the API to the `Dev` stage.
8. Configure the frontend to call the API.
9. Test the complete request path.

### Production-style target

For a more production-oriented deployment:

- Keep the S3 bucket private.
- Use CloudFront OAC instead of public S3 access.
- Redirect HTTP to HTTPS.
- Use CloudFront caching appropriately.
- Use Route 53 with a custom domain if required.
- Manage infrastructure with Terraform.
- Use GitHub Actions for automated testing and deployment.
- Add CloudWatch logs, metrics, and alarms.
- Use IAM least privilege.

## Terraform

Terraform configuration covers the target architecture, including:

- S3 bucket
- CloudFront distribution and OAC
- DynamoDB table
- Lambda function and execution role
- Lambda → DynamoDB IAM policy
- API Gateway REST API
- `/transactions` GET/POST methods
- Lambda integration
- API Gateway `Dev` stage

### Important state-management note

The initial POC resources were created manually. Therefore, the Terraform configuration should **not** simply be applied against those resources without checking Terraform state.

Use either:

1. `terraform import` to bring existing resources under Terraform management, or
2. a fresh environment with uniquely named Terraform-managed resources.

Before applying:

```bash
terraform init
terraform plan
terraform apply
```

For Terraform-managed test resources:

```bash
terraform destroy
```

## GitHub repository structure

A clean repository structure for the project is:

```text
cloud-analytics-dashboard/
├── frontend/
│   ├── index.html
│   ├── styles.css
│   ├── app.js
│   └── config.example.js
├── backend/
│   └── lambda/
│       └── handler.py
├── infrastructure/
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── ...
├── .github/
│   └── workflows/
│       └── deploy.yml
├── .gitignore
└── README.md
```

### Do not commit

```text
terraform.tfstate
terraform.tfstate.*
*.pem
.env
AWS access keys
AWS secret keys
other credentials/secrets
```

## Troubleshooting and Lessons Learned

### 1. AWS CLI not recognized

The AWS CLI was installed, but VS Code's existing terminal session did not recognize `aws`. Restarting the terminal refreshed the `PATH`.

### 2. Terraform created an unexpected EC2 instance

The EC2 instance was created because it was declared in the Terraform configuration and approved during `terraform apply`. Reviewing `terraform plan` before applying prevents surprises.

### 3. Lambda → DynamoDB permission failure

Lambda initially required explicit IAM permissions. The execution role was given `dynamodb:Scan` and `dynamodb:PutItem` for the specific table.

### 4. Incorrect IAM `Principal`

A `Principal` was initially placed in an identity policy. It was removed from the identity policy; the Lambda service principal belongs in the role trust policy.

### 5. API Gateway 403

The endpoint initially returned `403` because the deployed API/stage did not yet reflect the required resource/method configuration. The `/transactions` resource, Lambda integration, permission, and `Dev` deployment were verified.

### 6. Static frontend data

The dashboard initially rendered hard-coded demo data. The frontend was changed to call the API with `fetch()` and update the summary cards and transaction table from the response.

### 7. API contract mismatch

The frontend expected `daily_volume`, but the API returned `summary` and `transactions`. Inspecting the actual JSON response exposed the mismatch and the frontend was updated accordingly.

### 8. CloudFront cache

An updated `app.js` uploaded to S3 was not immediately reflected through CloudFront. A cache invalidation and browser hard refresh resolved the stale asset issue.

### 9. `CONFIG is not defined`

`app.js` referenced `CONFIG.API_URL`, but `config.js` had not been loaded before it. The HTML script order was corrected to load `config.js` before `app.js`, followed by a CloudFront invalidation.

### 10. Favicon 403

A missing favicon generated a `403` request in the browser console. It was unrelated to the dashboard functionality and was treated as a non-blocking issue.

### 11. Terraform vs manually created resources

Because the POC resources were initially created manually, Terraform state must be handled carefully. Existing resources should be imported or a clean Terraform environment should be created.

### 12. AWS cleanup

After testing, unused resources were cleaned up to minimize unnecessary AWS charges. Terraform `destroy` should only be used for resources tracked by the relevant Terraform state.

## Debugging approach

The main debugging pattern used throughout the POC was:

```text
1. Identify the failing layer
        ↓
2. Read the actual error / response
        ↓
3. Verify the deployed AWS resource
        ↓
4. Trace the request end-to-end
        ↓
5. Fix the smallest failing component
        ↓
6. Retest the complete flow
```

For this architecture:

```text
Browser
  ↓
CloudFront
  ↓
S3 / API Gateway
  ↓
Lambda
  ↓
DynamoDB
```


### API contract debugging

The frontend failed because it expected a field that the backend did not return. Inspecting the real JSON response quickly isolated the issue and allowed the frontend/backend contract to be aligned.

### CDN caching

The site continued serving an older JavaScript asset after an S3 upload. CloudFront invalidation and browser cache behavior were identified as the cause.

### IAM least privilege

Lambda was granted only the DynamoDB operations required by the application against the specific table.

### Terraform state

Introducing Terraform after manually creating resources highlighted why infrastructure state must remain synchronized with the real AWS environment.

### Layer-by-layer debugging

The project was debugged by isolating the failing layer instead of changing multiple components simultaneously. This is especially useful in distributed cloud architectures.

## Resource cleanup after the POC

The deployed demo resources were cleaned up after testing to avoid leaving unnecessary billable resources running.

Typical manual cleanup order:

1. Disable/delete CloudFront as required.
2. Empty/delete the S3 bucket.
3. Delete the API Gateway REST API.
4. Delete the Lambda function.
5. Delete the DynamoDB table.
6. Remove unused Lambda IAM roles/policies.
7. Optionally remove old CloudWatch log groups.

Keep IAM users/credentials only if they are still required, and rotate/delete unused credentials for security.

## Output

The original POC was available through CloudFront at:

```text
https://d4t3ai7o59vo.cloudfront.net/index.html
```

The AWS resources used for the POC have since been cleaned up, so this URL may no longer be active.

## Future enhancements

- Dynamic seven-day volume aggregation from DynamoDB
- CloudFront `/api/*` routing to API Gateway
- GitHub Actions CI/CD
- Terraform-managed deployment from a clean environment
- Automated CloudFront cache invalidation
- CloudWatch alarms and dashboards
- Better DynamoDB query patterns instead of full table scans as the dataset grows
- API validation and authentication for a production deployment
- Custom domain with Route 53


## Policy for Allowing Lambda Scan and Put to DynamoDB Table
  {
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "VisualEditor0",
			"Effect": "Allow",
			"Action": [
				"dynamodb:PutItem",
				"dynamodb:Scan"
			],
			"Resource": "arn:aws:dynamodb:us-east-1:767397765208:table/demo-transaction-table"
		}
	]
}


## Output

URL (have cleaned up the services after POC to avoid cost): https://d4t3ai7o59voa.cloudfront.net/index.html
![alt text](image.png)


![alt text](image-1.png)


![alt text](image-2.png)


![alt text](image-3.png)