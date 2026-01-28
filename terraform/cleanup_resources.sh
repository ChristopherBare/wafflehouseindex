#!/bin/bash

# This script cleans up existing AWS resources before Terraform deployment
# Only run this if you're sure these resources are expendable

echo "WARNING: This will delete existing AWS resources!"
echo "Only proceed if you're sure these resources can be safely deleted."
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Aborted."
    exit 1
fi

# Set AWS region
AWS_REGION=${AWS_REGION:-us-east-1}
echo "Using AWS region: $AWS_REGION"

# Delete DynamoDB table for locations cache
echo "Deleting DynamoDB table: whi-locations..."
aws dynamodb delete-table --table-name whi-locations --region $AWS_REGION 2>/dev/null || echo "Table does not exist or already deleted"

# Delete IAM role (must detach policies first)
echo "Detaching policies from IAM role: whi-lambda-role..."
aws iam detach-role-policy --role-name whi-lambda-role --policy-arn $(aws iam list-attached-role-policies --role-name whi-lambda-role --query 'AttachedPolicies[0].PolicyArn' --output text) --region $AWS_REGION 2>/dev/null || echo "No policies attached or role doesn't exist"

echo "Deleting IAM role: whi-lambda-role..."
aws iam delete-role --role-name whi-lambda-role --region $AWS_REGION 2>/dev/null || echo "Role does not exist or already deleted"

# Delete IAM policy
echo "Deleting IAM policy: whi-lambda-policy..."
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='whi-lambda-policy'].Arn | [0]" --output text --region $AWS_REGION)
if [ "$POLICY_ARN" != "None" ] && [ ! -z "$POLICY_ARN" ]; then
    aws iam delete-policy --policy-arn $POLICY_ARN --region $AWS_REGION 2>/dev/null || echo "Policy does not exist or already deleted"
else
    echo "Policy does not exist or already deleted"
fi

echo ""
echo "Cleanup complete. You can now run 'terraform apply' without conflicts."
echo "Note: The S3 bucket (whi-terraform-state) and DynamoDB lock table (whi-terraform-lock)"
echo "were NOT deleted as they contain your Terraform state and should remain."