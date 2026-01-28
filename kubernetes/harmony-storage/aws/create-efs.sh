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

EFS_NAME="harmony-config-efs"

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install it first and ensure it's configured."
    exit 1
fi

echo "Creating EFS file system for cluster: $CLUSTER_NAME in region: $CLUSTER_REGION"

# Check if EFS with the same name already exists
echo "Checking if EFS with name '$EFS_NAME' already exists..."
EXISTING_EFS_ID=$(aws efs describe-file-systems --region "$CLUSTER_REGION" --query "FileSystems[?Name=='$EFS_NAME'].FileSystemId" --output text)

if [ -n "$EXISTING_EFS_ID" ] && [ "$EXISTING_EFS_ID" != "None" ]; then
    echo "✅ EFS file system with name '$EFS_NAME' already exists!"
    echo "📋 EFS File System ID: $EXISTING_EFS_ID"
    echo ""
    echo "To use this existing EFS, update your my-values.yaml with:"
    echo "   persistence:"
    echo "     efs:"
    echo "       fileSystemId: \"$EXISTING_EFS_ID\""
    exit 0
fi

echo "No existing EFS found with name '$EFS_NAME'. Creating new EFS file system..."

# Get cluster VPC and subnets
echo "Getting cluster VPC and subnet information..."
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$CLUSTER_REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text)
SUBNET_IDS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$CLUSTER_REGION" --query 'cluster.resourcesVpcConfig.subnetIds[]' --output text)

echo "VPC ID: $VPC_ID"
echo "Subnet IDs: $SUBNET_IDS"

# Create EFS file system
echo "Creating EFS file system..."
EFS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value="$EFS_NAME" Key=Cluster,Value="$CLUSTER_NAME" \
  --region "$CLUSTER_REGION" \
  --query 'FileSystemId' --output text)

echo "✅ Created EFS file system: $EFS_ID"

# Wait for EFS to be available (compatible with older AWS CLI)
echo "Waiting for EFS to be available..."
while true; do
  STATE=$(aws efs describe-file-systems --file-system-id "$EFS_ID" --region "$CLUSTER_REGION" --query 'FileSystems[0].LifeCycleState' --output text)
  if [ "$STATE" = "available" ]; then
    echo "EFS file system is now available"
    break
  elif [ "$STATE" = "error" ]; then
    echo "Error: EFS file system creation failed"
    exit 1
  else
    echo "EFS state: $STATE - waiting 10 seconds..."
    sleep 10
  fi
done

# Get the default security group for the VPC
DEFAULT_SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --region "$CLUSTER_REGION" --query 'SecurityGroups[0].GroupId' --output text)

# Get the EKS cluster security group
CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$CLUSTER_REGION" --query 'cluster.resourcesVpcConfig.securityGroupIds[0]' --output text)

# Get all node security groups
NODE_SGS=$(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --region "$CLUSTER_REGION" --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' --output text | sort -u)

echo "Default VPC Security Group: $DEFAULT_SG"
echo "EKS Cluster Security Group: $CLUSTER_SG"
echo "EKS Node Security Groups: $NODE_SGS"

# Add security group rule to allow NFS traffic from EKS cluster to EFS
echo "Adding security group rule to allow NFS traffic from cluster..."
aws ec2 authorize-security-group-ingress \
  --group-id "$DEFAULT_SG" \
  --protocol tcp \
  --port 2049 \
  --source-group "$CLUSTER_SG" \
  --region "$CLUSTER_REGION" 2>/dev/null || echo "Cluster security group rule might already exist"

# Add security group rules for each node security group
for NODE_SG in $NODE_SGS; do
  echo "Adding security group rule for node SG: $NODE_SG"
  aws ec2 authorize-security-group-ingress \
    --group-id "$DEFAULT_SG" \
    --protocol tcp \
    --port 2049 \
    --source-group "$NODE_SG" \
    --region "$CLUSTER_REGION" 2>/dev/null || echo "Node security group rule for $NODE_SG might already exist"
done

# Also allow NFS traffic from the default security group to itself (for cross-AZ communication)
aws ec2 authorize-security-group-ingress \
  --group-id "$DEFAULT_SG" \
  --protocol tcp \
  --port 2049 \
  --source-group "$DEFAULT_SG" \
  --region "$CLUSTER_REGION" 2>/dev/null || echo "Self-referencing security group rule might already exist"

# Create mount targets for each subnet
echo "Creating mount targets..."
for SUBNET_ID in $SUBNET_IDS; do
  echo "Creating mount target in subnet: $SUBNET_ID"
  MT_RESULT=$(aws efs create-mount-target \
    --file-system-id "$EFS_ID" \
    --subnet-id "$SUBNET_ID" \
    --security-groups "$DEFAULT_SG" \
    --region "$CLUSTER_REGION" 2>&1)

  if echo "$MT_RESULT" | grep -q "MountTargetId"; then
    MT_ID=$(echo "$MT_RESULT" | grep -o '"MountTargetId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Created mount target: $MT_ID"
  elif echo "$MT_RESULT" | grep -q "MountTargetConflict"; then
    echo "ℹ️  Mount target already exists for subnet $SUBNET_ID"
  else
    echo "❌ Error creating mount target for subnet $SUBNET_ID: $MT_RESULT"
  fi
done

# Wait for all mount targets to be available
echo "Waiting for all mount targets to be available..."
MOUNT_TARGET_RETRIES=0
MAX_MOUNT_TARGET_RETRIES=30  # Wait up to 30 minutes
while true; do
  ALL_AVAILABLE=true
  for SUBNET_ID in $SUBNET_IDS; do
    MT_STATE=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$CLUSTER_REGION" --query "MountTargets[?SubnetId=='$SUBNET_ID'].LifeCycleState" --output text)
    if [ "$MT_STATE" != "available" ]; then
      ALL_AVAILABLE=false
      break
    fi
  done
  if $ALL_AVAILABLE; then
    echo "✅ All EFS mount targets are now available"
    break
  fi
  MOUNT_TARGET_RETRIES=$((MOUNT_TARGET_RETRIES + 1))
  if [ $MOUNT_TARGET_RETRIES -ge $MAX_MOUNT_TARGET_RETRIES ]; then
    echo "⚠️  Warning: Not all mount targets are available after $MAX_MOUNT_TARGET_RETRIES attempts (30 minutes)"
    echo "Proceeding anyway - they may become available during pod startup"
    break
  fi
  echo "Mount target availability check $MOUNT_TARGET_RETRIES/$MAX_MOUNT_TARGET_RETRIES - waiting 1 minute..."
  sleep 60
done

# Create a summary file
cat > "./efs-storage-info.txt" << EOF
Amazon EFS Storage Configuration
===============================
Created: $(date)
Cluster: $CLUSTER_NAME
Region: $CLUSTER_REGION

Storage Details:
- EFS File System ID: $EFS_ID
- EFS Name: $EFS_NAME
- VPC ID: $VPC_ID

Helm Configuration:
persistence:
  efs:
    fileSystemId: "$EFS_ID"

Cleanup Command:
./cleanup-efs.sh
EOF

echo ""
echo "=== EFS File System Created Successfully ==="
echo ""
echo "EFS Details:"
echo "  File System ID: $EFS_ID"
echo "  Region:         $CLUSTER_REGION"
echo ""
echo "Next Steps:"
echo "  1. Update your harmony-storage/my-values.yaml:"
echo "     global.platform: \"aws\""
echo "     storageClass.efs.fileSystemId: \"$EFS_ID\""
echo ""
echo "  2. Install the harmony-storage chart:"
echo "     helm install harmony-storage . -f my-values.yaml -n harmony --create-namespace"
echo ""
echo "Verification Commands:"
echo "  aws efs describe-file-systems --file-system-id $EFS_ID --region $CLUSTER_REGION"
echo "  kubectl get storageclass -n harmony"
echo ""
echo "Configuration details saved to: ./efs-storage-info.txt"
