#!/bin/bash

# Configuration - these must be set as environment variables before running the script
# Required environment variables:
# - CLUSTER_NAME: Your EKS cluster name
# - CLUSTER_REGION: Your AWS region
if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: CLUSTER_NAME environment variable is not set."
    echo "Please set it before running this script:"
    echo "  export CLUSTER_NAME=your-cluster-name"
    exit 1
fi

if [ -z "$CLUSTER_REGION" ]; then
    echo "Error: CLUSTER_REGION environment variable is not set."
    echo "Please set it before running this script:"
    echo "  export CLUSTER_REGION=your-aws-region"
    exit 1
fi

ADDON_NAME="aws-efs-csi-driver"
ROLE_NAME="AmazonEKS_EFS_CSI_DriverRole"
POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
TRUST_POLICY_FILE="efs-csi-trust-policy.json"

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install it first and ensure it's configured."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install it first and ensure it's configured for your cluster."
    exit 1
fi

echo "Using configuration:"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Region: $CLUSTER_REGION"
echo ""

# --- Prerequisites Check ---

# Check for AWS CLI
if ! command -v aws &> /dev/null
then
    echo "Error: AWS CLI is not installed or not in PATH."
    exit 1
fi

echo "--- Starting EFS CSI Driver Installation for cluster: ${CLUSTER_NAME} in region: ${CLUSTER_REGION} ---"

# --- Step 1: Set and Export Variables ---

echo "1. Retrieving AWS Account ID and OIDC Issuer URL..."

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Get the FULL OIDC Issuer URL
OIDC_ISSUER_URL=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$CLUSTER_REGION" --query "cluster.identity.oidc.issuer" --output text 2>/dev/null)
OIDC_ARN_PREFIX=${OIDC_ISSUER_URL#https://}

if [ -z "$OIDC_ISSUER_URL" ]; then
    echo "Error: Could not retrieve OIDC Issuer URL. Check if the cluster name or region is correct."
    exit 1
fi

export AWS_ACCOUNT_ID
export OIDC_ISSUER_URL
export OIDC_ARN_PREFIX

echo "   Account ID: ${AWS_ACCOUNT_ID}"
echo "   OIDC URL: ${OIDC_ISSUER_URL}"
echo "   ARN Prefix: $OIDC_ARN_PREFIX"

# --- Step 2: Create the IAM Role Trust Policy ---

echo "2. Generating IAM Trust Policy file: ${TRUST_POLICY_FILE}"

# Create the trust policy document directly with variable substitution
cat <<EOFTRUST > "$TRUST_POLICY_FILE"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ARN_PREFIX}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ARN_PREFIX}:aud": "sts.amazonaws.com",
          "${OIDC_ARN_PREFIX}:sub": "system:serviceaccount:kube-system:efs-csi-controller-sa"
        }
      }
    }
  ]
}
EOFTRUST

# --- Step 3: Create and Configure the IAM Role ---

echo "3. Creating IAM Role (${ROLE_NAME}) and attaching policy..."

# Attempt to create the IAM role.
# If the role already exists, the error message is redirected to /dev/null,
# and a specific message is printed. The script then continues.
if aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://"$TRUST_POLICY_FILE" 2>/dev/null; then
    echo "   Success: Role created."
else
    # Check if the error was specifically "EntityAlreadyExists"
    # Note: A direct check for the specific error is cleaner, but checking the role existence
    # and creation is the standard reliable idempotent approach for IAM roles.
    ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "   Info: Role already exists. Continuing with policy attachment and update."
        # Crucially, update the existing role's trust policy in case it was wrong previously
        aws iam update-assume-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-document file://"$TRUST_POLICY_FILE"
    else
        echo "   Error: Failed to create role for an unknown reason."
        exit 1
    fi
fi

# Attach the required AWS managed policy (safe to run multiple times)
echo "   Attaching managed policy: ${POLICY_ARN}"
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN" 2>/dev/null

# Capture the Role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)
echo "   Role ARN retrieved: ${ROLE_ARN}"

# Give IAM a moment to propagate the role (important for EKS/IRSA)
echo "   Waiting for role propagation (10 seconds)..."
sleep 10

# --- Step 4: Install the EFS CSI Driver Add-on ---

echo "4. Checking and updating EKS Add-on: ${ADDON_NAME}..."

# Check if the add-on exists to determine whether to use create-addon or update-addon
# Commands in 'if' conditions don't trigger set -e exits, making this cleaner than || true
if CURRENT_VERSION=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$ADDON_NAME" --region "$CLUSTER_REGION" --query "addon.addonVersion" --output text 2>/dev/null); then
    echo "   Add-on found (Version: ${CURRENT_VERSION}). Forcing update to reconcile permissions."
    # Use UPDATE-ADDON to fix the 403 error by forcing a restart with the corrected role ARN
    aws eks update-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$ADDON_NAME" \
        --addon-version "$CURRENT_VERSION" \
        --service-account-role-arn "$ROLE_ARN" \
        --resolve-conflicts OVERWRITE \
        --region "$CLUSTER_REGION"
else
    # Add-on does not exist, proceed with creation
    echo "   Add-on not found. Creating new add-on."
    # Find the latest compatible version (if not explicitly set)
    # Using 'latest' or a retrieved value is safer than hardcoding if cluster version is unknown
    COMPATIBLE_VERSION=$(aws eks describe-addon-versions --addon-name "$ADDON_NAME" --kubernetes-version $(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$CLUSTER_REGION" --query "cluster.version" --output text) --region "$CLUSTER_REGION" --query "addons[0].addonVersions[0].addonVersion" --output text)

    aws eks create-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name "$ADDON_NAME" \
      --addon-version "$COMPATIBLE_VERSION" \
      --service-account-role-arn "$ROLE_ARN" \
      --resolve-conflicts OVERWRITE \
      --region "$CLUSTER_REGION"
fi

# --- Step 5: Verification ---

echo "5. Verifying add-on status (this may take a minute or two)..."

ADDON_STATUS=""
while [ "$ADDON_STATUS" != "ACTIVE" ]; do
    ADDON_STATUS=$(aws eks describe-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name ${ADDON_NAME} \
        --region "$CLUSTER_REGION" \
        --query "addon.status" --output text 2>/dev/null)

    if [ "$ADDON_STATUS" == "ACTIVE" ]; then
        echo "   Success: Amazon EFS CSI Driver add-on is ACTIVE."
        break
    elif [ "$ADDON_STATUS" == "DEGRADED" ] || [ "$ADDON_STATUS" == "CREATE_FAILED" ]; then
        echo "   Error: Add-on status is ${ADDON_STATUS}. Check the EKS console for details."
        exit 1
    fi
    echo "   Current status: ${ADDON_STATUS}. Waiting 15 seconds..."
    sleep 15
done

# Cleanup temporary files
rm "$TRUST_POLICY_FILE"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next Steps:"
echo "  1. Run ./create-efs.sh to create an EFS file system"
echo "  2. Update harmony-storage chart values with EFS ID"
echo "  3. Deploy the harmony-storage Helm chart"
echo ""
echo "Verification Commands:"
echo "  kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver"
