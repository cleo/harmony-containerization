#!/usr/bin/env bash

# create-filestore.sh - Create Google Cloud Filestore instance for GKE cluster
#
# Prerequisites:
#   - Environment variables set (run: source ./setup-env.sh)
#   - gcloud CLI configured
#   - NFS CSI driver installed (run: ./install-nfs-csi-driver.sh)

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

# Validate required environment variables
if [ -z "$CLUSTER_NAME" ] || [ -z "$CLUSTER_LOCATION" ] || [ -z "$CLUSTER_ZONE" ] || [ -z "$PROJECT_ID" ]; then
    printf "%b\n" "${RED}ERROR: Required environment variables not set${NC}"
    echo "Please run: source ./setup-env.sh"
    exit 1
fi

printf "%b\n" "${GREEN}=== Creating Google Cloud Filestore Instance ===${NC}\n"
echo "Using configuration:"
printf "%b\n" "${BLUE}  Cluster:${NC}  $CLUSTER_NAME"
printf "%b\n" "${BLUE}  Location:${NC} $CLUSTER_LOCATION"
printf "%b\n" "${BLUE}  Zone:${NC}     $CLUSTER_ZONE"
printf "%b\n" "${BLUE}  Project:${NC}  $PROJECT_ID"
echo ""

# Configuration
FILESTORE_NAME="harmony-config-filestore"
SHARE_NAME="harmony_data"
TIER="BASIC_HDD"  # Options: BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD, ENTERPRISE
CAPACITY="1TB"    # Minimum: BASIC_HDD=1TB, BASIC_SSD=2.5TB
DESCRIPTION="Harmony shared configuration storage"

# Use CLUSTER_ZONE for Filestore instance location
FILESTORE_ZONE="$CLUSTER_ZONE"
REGION=$(echo "$CLUSTER_ZONE" | sed 's/-[a-z]$//')

# Step 1: Check for existing Filestore instance
printf "%b\n" "${GREEN}Step 1: Checking for existing Filestore instance...${NC}"

EXISTING_INSTANCE=$(gcloud filestore instances list \
    --location="$FILESTORE_ZONE" \
    --project="$PROJECT_ID" \
    --format="value(name)" \
    --filter="name:$FILESTORE_NAME" 2>/dev/null || echo "")

if [ -n "$EXISTING_INSTANCE" ]; then
    printf "%b\n" "${YELLOW}Filestore instance '$FILESTORE_NAME' already exists${NC}"
    echo ""
    
    # Get existing instance details
    IP_ADDRESS=$(gcloud filestore instances describe "$FILESTORE_NAME" \
        --location="$FILESTORE_ZONE" \
        --project="$PROJECT_ID" \
        --format="value(networks.ipAddresses[0])")
    
    FILE_SHARE_NAME=$(gcloud filestore instances describe "$FILESTORE_NAME" \
        --location="$FILESTORE_ZONE" \
        --project="$PROJECT_ID" \
        --format="value(fileShares[0].name)")
    
    printf "%b\n" "${GREEN}Existing Instance Details:${NC}"
    echo "  Name:       $FILESTORE_NAME"
    echo "  IP Address: $IP_ADDRESS"
    echo "  Share Name: $FILE_SHARE_NAME"
    echo "  Zone:       $FILESTORE_ZONE"
    echo ""
    
    # Save to file
    cat > filestore-storage-info.txt <<EOF
# Google Cloud Filestore Configuration
# Generated: $(date)
# Project: $PROJECT_ID
# Cluster: $CLUSTER_NAME
# Zone: $FILESTORE_ZONE

FILESTORE_INSTANCE_NAME=$FILESTORE_NAME
FILESTORE_IP_ADDRESS=$IP_ADDRESS
FILESTORE_SHARE_NAME=$FILE_SHARE_NAME
FILESTORE_ZONE=$FILESTORE_ZONE

# Use these values in your harmony-storage Helm chart my-values.yaml:
# storageClass.filestore.ip: "$IP_ADDRESS"
# storageClass.filestore.share: "$FILE_SHARE_NAME"
EOF
    
    printf "%b\n" "${GREEN}✓ Configuration saved to: filestore-storage-info.txt${NC}"
    exit 0
fi

echo "No existing instance found. Creating new instance..."
echo ""

# Step 2: Get cluster VPC network
printf "%b\n" "${GREEN}Step 2: Getting cluster VPC network information...${NC}"

VPC_NETWORK=$(gcloud container clusters describe "$CLUSTER_NAME" \
    --location="$CLUSTER_LOCATION" \
    --project="$PROJECT_ID" \
    --format="value(network)")

if [ -z "$VPC_NETWORK" ]; then
    printf "%b\n" "${RED}ERROR: Could not determine cluster VPC network${NC}"
    exit 1
fi

# Extract network name from full path
NETWORK_NAME=$(basename "$VPC_NETWORK")

echo "  VPC Network: $NETWORK_NAME"
echo ""

# Step 3: Create Filestore instance
printf "%b\n" "${GREEN}Step 3: Creating Filestore instance...${NC}"
echo "  Name:        $FILESTORE_NAME"
echo "  Tier:        $TIER"
echo "  Capacity:    $CAPACITY"
echo "  Share Name:  $SHARE_NAME"
echo "  Network:     $NETWORK_NAME"
echo "  Zone:        $FILESTORE_ZONE"
echo ""
echo "This may take 5-10 minutes..."
echo ""

gcloud filestore instances create "$FILESTORE_NAME" \
    --location="$FILESTORE_ZONE" \
    --tier="$TIER" \
    --file-share="name=$SHARE_NAME,capacity=$CAPACITY" \
    --network="name=$NETWORK_NAME" \
    --description="$DESCRIPTION" \
    --project="$PROJECT_ID"

printf "%b\n" "${GREEN}✓ Filestore instance created${NC}"
echo ""

# Step 4: Get instance details
printf "%b\n" "${GREEN}Step 4: Retrieving instance details...${NC}"

IP_ADDRESS=$(gcloud filestore instances describe "$FILESTORE_NAME" \
    --location="$FILESTORE_ZONE" \
    --project="$PROJECT_ID" \
    --format="value(networks.ipAddresses[0])")

if [ -z "$IP_ADDRESS" ]; then
    printf "%b\n" "${RED}ERROR: Could not retrieve Filestore IP address${NC}"
    exit 1
fi

echo "  IP Address: $IP_ADDRESS"
echo "  Share Name: $SHARE_NAME"
echo ""

# Step 5: Save configuration
printf "%b\n" "${GREEN}Step 5: Saving configuration...${NC}"

cat > filestore-storage-info.txt <<EOF
# Google Cloud Filestore Configuration
# Generated: $(date)
# Project: $PROJECT_ID
# Cluster: $CLUSTER_NAME
# Zone: $FILESTORE_ZONE

FILESTORE_INSTANCE_NAME=$FILESTORE_NAME
FILESTORE_IP_ADDRESS=$IP_ADDRESS
FILESTORE_SHARE_NAME=$SHARE_NAME
FILESTORE_ZONE=$FILESTORE_ZONE
FILESTORE_TIER=$TIER
FILESTORE_CAPACITY=$CAPACITY

# Use these values in your harmony-storage Helm chart my-values.yaml:
# global:
#   platform: "gcp"
#
# storageClass:
#   filestore:
#     ip: "$IP_ADDRESS"
#     share: "$SHARE_NAME"
EOF

printf "%b\n" "${GREEN}✓ Configuration saved to: filestore-storage-info.txt${NC}"
echo ""

# Display summary
printf "%b\n" "${GREEN}=== Filestore Instance Created Successfully ===${NC}"
echo ""
printf "%b\n" "${BLUE}Instance Details:${NC}"
echo "  Name:       $FILESTORE_NAME"
echo "  IP Address: $IP_ADDRESS"
echo "  Share Name: $SHARE_NAME"
echo "  Mount Path: $IP_ADDRESS:/$SHARE_NAME"
echo "  Zone:       $FILESTORE_ZONE"
echo "  Tier:       $TIER"
echo "  Capacity:   $CAPACITY"
echo ""
printf "%b\n" "${BLUE}Next Steps:${NC}"
echo "  1. Update your harmony-storage/my-values.yaml:"
echo "     global.platform: \"gcp\""
echo "     storageClass.filestore.ip: \"$IP_ADDRESS\""
echo "     storageClass.filestore.share: \"$SHARE_NAME\""
echo ""
echo "  2. Install the harmony-storage chart:"
echo "     helm install harmony-storage . -f my-values.yaml -n harmony --create-namespace"
echo ""
printf "%b\n" "${BLUE}Verification Commands:${NC}"
echo "  gcloud filestore instances describe $FILESTORE_NAME --location=$FILESTORE_ZONE"
