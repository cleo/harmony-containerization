#!/usr/bin/env bash

# cleanup-filestore.sh - Clean up Google Cloud Filestore resources
#
# Prerequisites:
#   - Environment variables set (run: source ./setup-env.sh)
#   - gcloud CLI configured
#
# Usage:
#   ./cleanup-filestore.sh              # Interactive mode with prompts
#   ./cleanup-filestore.sh --delete-storage  # Automatic deletion without prompts
#   ./cleanup-filestore.sh --help       # Show help
#
# ⚠️  CRITICAL: Run this BEFORE deleting your GKE cluster to avoid orphaned resources

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check prerequisites
if ! command -v gcloud &> /dev/null; then
    printf "%b\n" "${RED}❌ gcloud CLI not found. Please install it first and ensure it's configured.${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    printf "%b\n" "${RED}❌ kubectl not found. Please install it first.${NC}"
    exit 1
fi

# Configuration
FILESTORE_NAME="harmony-config-filestore"
AUTO_DELETE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --delete-storage)
            AUTO_DELETE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --delete-storage    Automatically delete storage without prompts"
            echo "  --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      # Interactive mode"
            echo "  $0 --delete-storage     # Automatic deletion"
            exit 0
            ;;
        *)
            printf "%b\n" "${RED}Unknown option: $1${NC}"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

printf "%b\n" "${GREEN}=== Google Cloud Filestore Cleanup ===${NC}\n"

# Validate required environment variables
if [ -z "$CLUSTER_NAME" ] || [ -z "$CLUSTER_LOCATION" ] || [ -z "$CLUSTER_ZONE" ] || [ -z "$PROJECT_ID" ]; then
    printf "%b\n" "${RED}ERROR: Required environment variables not set${NC}"
    echo "Please run: source ./setup-env.sh"
    exit 1
fi

printf "%b\n" "${BLUE}Cluster:${NC}  $CLUSTER_NAME"
printf "%b\n" "${BLUE}Location:${NC} $CLUSTER_LOCATION"
printf "%b\n" "${BLUE}Zone:${NC}     $CLUSTER_ZONE"
printf "%b\n" "${BLUE}Project:${NC}  $PROJECT_ID"
echo ""

# Use CLUSTER_ZONE for Filestore instance location
FILESTORE_ZONE="$CLUSTER_ZONE"

# Step 1: Find Filestore instance
printf "%b\n" "${GREEN}Step 1: Looking for Filestore instance...${NC}"

INSTANCE_EXISTS=$(gcloud filestore instances list \
    --location="$FILESTORE_ZONE" \
    --project="$PROJECT_ID" \
    --format="value(name)" \
    --filter="name:$FILESTORE_NAME" 2>/dev/null || echo "")

if [ -z "$INSTANCE_EXISTS" ]; then
    printf "%b\n" "${YELLOW}No Filestore instance named '$FILESTORE_NAME' found in zone $FILESTORE_ZONE${NC}"
    echo "Nothing to clean up."
    exit 0
fi

printf "%b\n" "${GREEN}Found Filestore instance: $FILESTORE_NAME${NC}"
echo ""

# Get instance details
INSTANCE_INFO=$(gcloud filestore instances describe "$FILESTORE_NAME" \
    --location="$FILESTORE_ZONE" \
    --project="$PROJECT_ID" \
    --format="json" 2>/dev/null)

IP_ADDRESS=$(echo "$INSTANCE_INFO" | grep -o '"ipAddresses"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[^"]*"' | grep -o '"[0-9.]*"' | tr -d '"')
CAPACITY=$(echo "$INSTANCE_INFO" | grep -o '"capacityGb"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '[0-9]*')
TIER=$(echo "$INSTANCE_INFO" | grep -o '"tier"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)

printf "%b\n" "${BLUE}Instance Details:${NC}"
echo "  Name:       $FILESTORE_NAME"
echo "  IP Address: $IP_ADDRESS"
echo "  Capacity:   ${CAPACITY}GB"
echo "  Tier:       $TIER"
echo "  Zone:       $FILESTORE_ZONE"
echo ""

# Step 2: Clean up Kubernetes resources
printf "%b\n" "${GREEN}Step 2: Checking for Kubernetes resources...${NC}"

# Check for PVCs using this Filestore
PVCS=$(kubectl get pvc -A -o json 2>/dev/null | grep -o '"harmony-pvc"' || echo "")

if [ -n "$PVCS" ]; then
    printf "%b\n" "${YELLOW}Found PVCs that may be using this Filestore${NC}"
    echo "Listing PVCs:"
    kubectl get pvc -A | grep -i harmony || true
    echo ""
    
    if [ "$AUTO_DELETE" = false ]; then
        read -p "Delete these PVCs? (y/n): " DELETE_PVCS
        if [[ "$DELETE_PVCS" =~ ^[Yy]$ ]]; then
            kubectl delete pvc -n harmony harmony-pvc 2>/dev/null || echo "PVC not found or already deleted"
            printf "%b\n" "${GREEN}✓ PVCs deleted${NC}"
        fi
    else
        kubectl delete pvc -n harmony harmony-pvc 2>/dev/null || echo "PVC not found or already deleted"
        printf "%b\n" "${GREEN}✓ PVCs deleted${NC}"
    fi
else
    echo "No PVCs found"
fi

echo ""

# Step 3: Delete Filestore instance
printf "%b\n" "${GREEN}Step 3: Filestore instance deletion...${NC}"
echo ""
printf "%b\n" "${RED}⚠️  WARNING: This will delete the Filestore instance and ALL data${NC}"
printf "%b\n" "${RED}⚠️  This action CANNOT be undone!${NC}"
echo ""

if [ "$AUTO_DELETE" = false ]; then
    read -p "Are you sure you want to delete the Filestore instance? (yes/no): " CONFIRM_DELETE
    
    if [ "$CONFIRM_DELETE" != "yes" ]; then
        echo "Deletion cancelled."
        echo ""
        printf "%b\n" "${YELLOW}Note: The Filestore instance still exists and will continue to incur charges${NC}"
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

printf "%b\n" "${GREEN}✓ Filestore instance deleted${NC}"
echo ""

# Step 4: Clean up configuration file
if [ -f "filestore-storage-info.txt" ]; then
    printf "%b\n" "${GREEN}Step 4: Cleaning up configuration files...${NC}"
    rm -f filestore-storage-info.txt
    printf "%b\n" "${GREEN}✓ Configuration file removed${NC}"
    echo ""
fi

# Summary
printf "%b\n" "${GREEN}=== Cleanup Complete ===${NC}"
echo ""
printf "%b\n" "${BLUE}Resources Removed:${NC}"
echo "  ✓ Filestore instance: $FILESTORE_NAME"
echo "  ✓ Configuration files"
echo ""
printf "%b\n" "${GREEN}All Filestore resources have been cleaned up${NC}"
echo ""
printf "%b\n" "${BLUE}Next Steps:${NC}"
echo "  - You can now safely delete your GKE cluster if needed"
echo "  - To recreate the Filestore instance, run: ./create-filestore.sh"
