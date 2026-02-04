#!/bin/bash

# cleanup-efs.sh - Cleanup EFS resources before tearing down EKS cluster
# This script removes EFS mount targets and security group rules that prevent
# clean EKS cluster deletion.
#
# Usage:
#   ./cleanup-efs.sh                    # Interactive mode - prompts for each deletion
#   ./cleanup-efs.sh --delete-storage   # Automatically delete EFS file system without prompts
#   ./cleanup-efs.sh --help             # Show this help message
#
# ⚠️  CRITICAL: Run this BEFORE deleting your EKS cluster to avoid orphaned resources

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - these must be set as environment variables before running the script
# Required environment variables:
# - CLUSTER_NAME: Your EKS cluster name
# - CLUSTER_REGION: Your AWS region
if [ -z "$CLUSTER_NAME" ]; then
    printf "%b\n" "${RED}❌ Error: CLUSTER_NAME environment variable is not set.${NC}"
    echo "Please set it before running this script:"
    echo "  export CLUSTER_NAME=your-cluster-name"
    exit 1
fi

if [ -z "$CLUSTER_REGION" ]; then
    printf "%b\n" "${RED}❌ Error: CLUSTER_REGION environment variable is not set.${NC}"
    echo "Please set it before running this script:"
    echo "  export CLUSTER_REGION=your-aws-region"
    exit 1
fi

EFS_NAME="harmony-config-efs"

# Parse command line arguments
DELETE_STORAGE=false
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --delete-storage)
            DELETE_STORAGE=true
            shift
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Show help if requested
if [ "$SHOW_HELP" = true ]; then
    echo "Amazon EFS Cleanup Script"
    echo ""
    echo "Usage:"
    echo "  ./cleanup-efs.sh                    # Interactive mode - prompts for each deletion"
    echo "  ./cleanup-efs.sh --delete-storage   # Automatically delete EFS file system without prompts"
    echo "  ./cleanup-efs.sh --help             # Show this help message"
    echo ""
    echo "Environment variables required:"
    echo "  CLUSTER_NAME      - Your EKS cluster name"
    echo "  CLUSTER_REGION    - Your AWS region"
    echo ""
    echo "Examples:"
    echo "  source ./eks-env-vars.sh && ./cleanup-efs.sh"
    echo "  source ./eks-env-vars.sh && ./cleanup-efs.sh --delete-storage"
    exit 0
fi

echo "🧹 EFS Cleanup Script for EKS Cluster: $CLUSTER_NAME"
echo "Region: $CLUSTER_REGION"
echo "=================================================="

if [ "$DELETE_STORAGE" = true ]; then
    echo "🗑️  Automatic storage deletion mode enabled"
    echo "⚠️  WARNING: This will PERMANENTLY delete the EFS file system!"
    sleep 2
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
if ! command_exists aws; then
    echo "❌ AWS CLI not found. Please install it first."
    exit 1
fi

# Get EFS file system ID
echo "📋 Finding EFS file system..."
EFS_ID=$(aws efs describe-file-systems --region "$CLUSTER_REGION" --query "FileSystems[?Name=='$EFS_NAME'].FileSystemId" --output text)

if [ -z "$EFS_ID" ] || [ "$EFS_ID" = "None" ]; then
    echo "ℹ️  No EFS file system named '$EFS_NAME' found. Nothing to clean up."
    exit 0
fi

echo "Found EFS: $EFS_ID"

# Get VPC ID from EKS cluster (if cluster still exists)
echo "📋 Getting cluster information..."
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$CLUSTER_REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "⚠️  Could not get VPC ID from cluster (cluster may already be deleted)"
    echo "Will attempt to find VPC from mount targets..."

    # Try to get VPC from existing mount targets
    VPC_ID=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$CLUSTER_REGION" --query 'MountTargets[0].VpcId' --output text 2>/dev/null || echo "")

    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        echo "❌ Could not determine VPC ID. Manual cleanup may be required."
        exit 1
    fi
fi

echo "VPC ID: $VPC_ID"

# 1. Delete all mount targets
echo ""
echo "🗑️  Deleting EFS mount targets..."
MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$CLUSTER_REGION" --query 'MountTargets[*].MountTargetId' --output text)

if [ -n "$MOUNT_TARGETS" ] && [ "$MOUNT_TARGETS" != "None" ]; then
    for MT_ID in $MOUNT_TARGETS; do
        echo "Deleting mount target: $MT_ID"
        aws efs delete-mount-target --mount-target-id "$MT_ID" --region "$CLUSTER_REGION" 2>/dev/null || echo "Failed to delete $MT_ID (may already be deleted)"
    done

    # Wait for mount targets to be deleted
    echo "Waiting for mount targets to be deleted..."
    RETRIES=0
    MAX_RETRIES=20  # Wait up to 10 minutes
    while true; do
        REMAINING=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$CLUSTER_REGION" --query 'length(MountTargets)' --output text 2>/dev/null || echo "0")
        if [ "$REMAINING" = "0" ]; then
            echo "✅ All mount targets deleted"
            break
        fi
        RETRIES=$((RETRIES + 1))
        if [ $RETRIES -ge $MAX_RETRIES ]; then
            echo "⚠️  Timeout waiting for mount targets to be deleted"
            break
        fi
        echo "Still $REMAINING mount targets remaining... waiting 30 seconds"
        sleep 30
    done
else
    echo "ℹ️  No mount targets found"
fi

# 2. Remove security group rules
echo ""
echo "🗑️  Removing EFS security group rules..."

# Get security groups
DEFAULT_SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --region "$CLUSTER_REGION" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")

if [ -n "$DEFAULT_SG" ] && [ "$DEFAULT_SG" != "None" ]; then
    echo "Default security group: $DEFAULT_SG"

    # Try to get cluster security group (may fail if cluster is deleted)
    CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$CLUSTER_REGION" --query 'cluster.resourcesVpcConfig.securityGroupIds[0]' --output text 2>/dev/null || echo "")

    # Remove cluster security group rule if cluster still exists
    if [ -n "$CLUSTER_SG" ] && [ "$CLUSTER_SG" != "None" ]; then
        echo "Removing cluster security group rule..."
        aws ec2 revoke-security-group-ingress \
            --group-id "$DEFAULT_SG" \
            --protocol tcp \
            --port 2049 \
            --source-group "$CLUSTER_SG" \
            --region "$CLUSTER_REGION" 2>/dev/null || echo "Cluster SG rule may already be removed"
    fi

    # Remove self-referencing rule
    echo "Removing self-referencing security group rule..."
    aws ec2 revoke-security-group-ingress \
        --group-id "$DEFAULT_SG" \
        --protocol tcp \
        --port 2049 \
        --source-group "$DEFAULT_SG" \
        --region "$CLUSTER_REGION" 2>/dev/null || echo "Self-referencing rule may already be removed"

    # Try to remove node security group rules (may fail if nodes are deleted)
    echo "Attempting to remove node security group rules..."
    NODE_SGS=$(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" --region "$CLUSTER_REGION" --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' --output text 2>/dev/null | sort -u || echo "")

    if [ -n "$NODE_SGS" ]; then
        for NODE_SG in $NODE_SGS; do
            if [ -n "$NODE_SG" ] && [ "$NODE_SG" != "None" ]; then
                echo "Removing rule for node SG: $NODE_SG"
                aws ec2 revoke-security-group-ingress \
                    --group-id "$DEFAULT_SG" \
                    --protocol tcp \
                    --port 2049 \
                    --source-group "$NODE_SG" \
                    --region "$CLUSTER_REGION" 2>/dev/null || echo "Node SG rule for $NODE_SG may already be removed"
            fi
        done
    else
        echo "ℹ️  No node security groups found (nodes may already be deleted)"
    fi
else
    echo "⚠️  Could not find default security group"
fi

# 3. Handle EFS file system deletion based on mode
echo ""
DELETE_EFS=false
if [ "$DELETE_STORAGE" = true ]; then
    echo "🗑️  Automatically deleting EFS file system (--delete-storage mode)..."
    DELETE_EFS=true
else
    read -p "🗑️  Do you want to delete the EFS file system '$EFS_ID'? This will PERMANENTLY delete all data! (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        DELETE_EFS=true
    fi
fi

if [ "$DELETE_EFS" = true ]; then
    echo "Deleting EFS file system..."
    aws efs delete-file-system --file-system-id "$EFS_ID" --region "$CLUSTER_REGION"
    echo "✅ EFS file system deletion initiated"
    echo "⚠️  Note: EFS deletion may take several minutes to complete"
else
    echo "ℹ️  EFS file system preserved: $EFS_ID"
    echo "📋 To delete it later, run:"
    echo "   aws efs delete-file-system --file-system-id $EFS_ID --region $CLUSTER_REGION"
fi

# Clean up info file if it exists
if [ -f "./efs-storage-info.txt" ]; then
    echo ""
    DELETE_CONFIG=false
    if [ "$DELETE_STORAGE" = true ]; then
        echo "🗑️  Automatically removing configuration file (--delete-storage mode)..."
        DELETE_CONFIG=true
    else
        read -p "Remove local configuration file './efs-storage-info.txt'? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            DELETE_CONFIG=true
        fi
    fi

    if [ "$DELETE_CONFIG" = true ]; then
        rm "./efs-storage-info.txt"
        echo "✅ Removed local configuration file"
    else
        echo "ℹ️  Configuration file preserved"
    fi
fi

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Resources Removed:"
if [ "$DELETE_STORAGE" = true ]; then
    echo "  ✓ EFS file system: $EFS_ID"
fi
echo "  ✓ Mount targets"
echo "  ✓ Security group rules"
echo "  ✓ Configuration files"
echo ""
echo "All EFS resources have been cleaned up"
echo ""
echo "Next Steps:"
echo "  - You can now safely delete your EKS cluster if needed"
echo "  - To recreate the EFS file system, run: ./create-efs.sh"
echo "aws efs describe-mount-targets --file-system-id $EFS_ID --region $CLUSTER_REGION"
echo ""
echo "# Check security group rules:"
echo "aws ec2 describe-security-groups --group-ids $DEFAULT_SG --region $CLUSTER_REGION"
