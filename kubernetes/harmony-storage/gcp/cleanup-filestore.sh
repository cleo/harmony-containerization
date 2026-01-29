#!/bin/bash

# cleanup-filestore.sh - Cleanup Google Cloud Filestore resources before tearing down GKE cluster
# This script removes Filestore instances and optionally deletes all data
# that prevent clean GKE cluster deletion.
#
# Usage:
#   ./cleanup-filestore.sh                    # Interactive mode - prompts for each deletion
#   ./cleanup-filestore.sh --delete-storage   # Automatically delete Filestore without prompts
#   ./cleanup-filestore.sh --help             # Show this help message
#
# ⚠️  CRITICAL: Run this BEFORE deleting your GKE cluster to avoid orphaned resources

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - these must be set as environment variables before running the script
# Required environment variables:
# - CLUSTER_NAME: Your GKE cluster name
# - CLUSTER_LOCATION: Your cluster location (region or zone)
# - CLUSTER_ZONE: Zone for Filestore
# - PROJECT_ID: Your GCP project ID
if [ -z "$CLUSTER_NAME" ]; then
    printf "%b\n" "${RED}❌ Error: CLUSTER_NAME environment variable is not set.${NC}"
    echo "Please set it before running this script:"
    echo "  export CLUSTER_NAME=your-cluster-name"
    exit 1
fi

if [ -z "$CLUSTER_ZONE" ]; then
    printf "%b\n" "${RED}❌ Error: CLUSTER_ZONE environment variable is not set.${NC}"
    echo "Please set it before running this script:"
    echo "  export CLUSTER_ZONE=your-zone"
    exit 1
fi

if [ -z "$PROJECT_ID" ]; then
    printf "%b\n" "${RED}❌ Error: PROJECT_ID environment variable is not set.${NC}"
    echo "Please set it before running this script:"
    echo "  export PROJECT_ID=your-project-id"
    exit 1
fi

FILESTORE_NAME="harmony-config-filestore"
FILESTORE_ZONE="$CLUSTER_ZONE"

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
            echo "❌ Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Show help if requested
if [ "$SHOW_HELP" = true ]; then
    echo "Google Cloud Filestore Cleanup Script"
    echo ""
    echo "Usage:"
    echo "  ./cleanup-filestore.sh                    # Interactive mode - prompts for each deletion"
    echo "  ./cleanup-filestore.sh --delete-storage   # Automatically delete Filestore without prompts"
    echo "  ./cleanup-filestore.sh --help             # Show this help message"
    echo ""
    echo "Environment variables required:"
    echo "  CLUSTER_NAME      - Your GKE cluster name"
    echo "  CLUSTER_ZONE      - Zone for Filestore instance"
    echo "  PROJECT_ID        - Your GCP project ID"
    echo ""
    echo "Examples:"
    echo "  source ./setup-env.sh && ./cleanup-filestore.sh"
    echo "  source ./setup-env.sh && ./cleanup-filestore.sh --delete-storage"
    exit 0
fi

echo "🧹 Filestore Cleanup Script for GKE Cluster: $CLUSTER_NAME"
echo "Zone: $CLUSTER_ZONE"
echo "Project: $PROJECT_ID"
echo "=================================================="

if [ "$DELETE_STORAGE" = true ]; then
    echo "🗑️  Automatic storage deletion mode enabled"
    echo "⚠️  WARNING: This will PERMANENTLY delete the Filestore instance!"
    sleep 2
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
if ! command_exists gcloud; then
    echo "❌ gcloud CLI not found. Please install it first."
    exit 1
fi

if ! command_exists kubectl; then
    echo "❌ kubectl not found. Please install it first."
    exit 1
fi

# Find Filestore instance
echo "📋 Finding Filestore instance..."

INSTANCE_EXISTS=$(gcloud filestore instances list \
    --location="$FILESTORE_ZONE" \
    --project="$PROJECT_ID" \
    --format="value(name)" \
    --filter="name:$FILESTORE_NAME" 2>/dev/null || echo "")

if [ -z "$INSTANCE_EXISTS" ]; then
    echo "ℹ️  No Filestore instance named '$FILESTORE_NAME' found in zone $FILESTORE_ZONE"
    echo "Nothing to clean up."
    exit 0
fi

echo "Found Filestore: $FILESTORE_NAME"
echo ""

# Get instance details
INSTANCE_INFO=$(gcloud filestore instances describe "$FILESTORE_NAME" \
    --location="$FILESTORE_ZONE" \
    --project="$PROJECT_ID" \
    --format="json" 2>/dev/null)

IP_ADDRESS=$(echo "$INSTANCE_INFO" | grep -o '"ipAddresses"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[^"]*"' | grep -o '"[0-9.]*"' | tr -d '"')
CAPACITY=$(echo "$INSTANCE_INFO" | grep -o '"capacityGb"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '[0-9]*')
TIER=$(echo "$INSTANCE_INFO" | grep -o '"tier"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

echo "Instance Details:"
echo "  Name:       $FILESTORE_NAME"
echo "  IP Address: $IP_ADDRESS"
echo "  Capacity:   ${CAPACITY}GB"
echo "  Tier:       $TIER"
echo "  Zone:       $FILESTORE_ZONE"
echo ""

# Clean up Kubernetes resources
echo "📋 Checking for Kubernetes resources..."

# Check for PVCs using this Filestore
PVCS=$(kubectl get pvc -A -o json 2>/dev/null | grep -o '"harmony-pvc"' || echo "")

if [ -n "$PVCS" ]; then
    echo "⚠️  Found PVCs that may be using this Filestore"
    echo "Listing PVCs:"
    kubectl get pvc -A | grep -i harmony || true
    echo ""
    
    if [ "$DELETE_STORAGE" = false ]; then
        read -p "Delete these PVCs? (y/n): " DELETE_PVCS
        if [[ "$DELETE_PVCS" =~ ^[Yy]$ ]]; then
            kubectl delete pvc -n harmony harmony-pvc 2>/dev/null || echo "PVC not found or already deleted"
            echo "✅ PVCs deleted"
        fi
    else
        kubectl delete pvc -n harmony harmony-pvc 2>/dev/null || echo "PVC not found or already deleted"
        echo "✅ PVCs deleted"
    fi
else
    echo "No PVCs found"
fi

echo ""

# Delete Filestore instance
echo "🗑️  Filestore instance deletion..."
echo ""
echo "⚠️  WARNING: This will delete the Filestore instance and ALL data"
echo "⚠️  This action CANNOT be undone!"
echo ""

if [ "$DELETE_STORAGE" = false ]; then
    read -p "Are you sure you want to delete the Filestore instance? (yes/no): " CONFIRM_DELETE
    
    if [ "$CONFIRM_DELETE" != "yes" ]; then
        echo "Deletion cancelled."
        echo ""
        echo "ℹ️  Note: The Filestore instance still exists and will continue to incur charges"
        echo "To delete it later, run this script again with --delete-storage"
        exit 0
    fi
fi

echo "Deleting Filestore instance: $FILESTORE_NAME"
echo "This may take several minutes..."
echo ""

gcloud filestore instances delete "$FILESTORE_NAME" \
    --location="$FILESTORE_ZONE" \
    --project="$PROJECT_ID" \
    --quiet

echo "✅ Filestore instance deletion initiated"
echo "⚠️  Note: Filestore deletion may take several minutes to complete"
echo ""

# Clean up info file if it exists
if [ -f "./filestore-storage-info.txt" ]; then
    echo ""
    DELETE_CONFIG=false
    if [ "$DELETE_STORAGE" = true ]; then
        echo "🗑️  Automatically removing configuration file (--delete-storage mode)..."
        DELETE_CONFIG=true
    else
        read -p "Remove local configuration file './filestore-storage-info.txt'? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            DELETE_CONFIG=true
        fi
    fi

    if [ "$DELETE_CONFIG" = true ]; then
        rm "./filestore-storage-info.txt"
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
    echo "  ✓ Filestore instance: $FILESTORE_NAME"
fi
echo "  ✓ Configuration files"
echo ""
echo "All Filestore resources have been cleaned up"
echo ""
echo "Next Steps:"
echo "  - You can now safely delete your GKE cluster if needed"
echo "  - To recreate the Filestore instance, run: ./create-filestore.sh"
echo ""
echo "Useful commands for verification:"
echo "# Check if Filestore instance still exists:"
echo "gcloud filestore instances list --location=$FILESTORE_ZONE --project=$PROJECT_ID"
