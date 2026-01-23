#!/usr/bin/env bash

# install-nfs-csi-driver.sh - Install NFS CSI driver for GKE
#
# Prerequisites:
#   - Environment variables set (run: source ./setup-env.sh)
#   - gcloud CLI configured
#   - kubectl configured for target GKE cluster
#   - Cluster-admin permissions required

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
if [ -z "$CLUSTER_NAME" ] || [ -z "$CLUSTER_LOCATION" ] || [ -z "$PROJECT_ID" ]; then
    printf "%b\n" "${RED}ERROR: Required environment variables not set${NC}"
    echo "Please run: source ./setup-env.sh"
    exit 1
fi

printf "%b\n" "${GREEN}=== Installing NFS CSI Driver for GKE ===${NC}\n"
echo "Using configuration:"
printf "%b\n" "${BLUE}  Cluster:${NC}  $CLUSTER_NAME"
printf "%b\n" "${BLUE}  Location:${NC} $CLUSTER_LOCATION"
printf "%b\n" "${BLUE}  Project:${NC}  $PROJECT_ID"
echo ""

# Step 1: Install NFS CSI driver
printf "%b\n" "${GREEN}Step 1: Installing NFS CSI driver...${NC}"

# Download and execute the NFS CSI driver installation script
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/install-driver.sh | bash -s master --

if [ $? -eq 0 ]; then
    printf "%b\n" "${GREEN}✓ NFS CSI driver installed${NC}\n"
else
    printf "%b\n" "${YELLOW}⚠ NFS CSI driver installation may have failed, continuing...${NC}\n"
fi

# Step 2: Wait for driver pods to be ready
printf "%b\n" "${GREEN}Step 2: Verifying CSI driver installation...${NC}"

# Check if cluster has nodes
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')

if [ "$NODE_COUNT" -eq 0 ]; then
    printf "%b\n" "${YELLOW}⚠ Warning: Cluster has no nodes${NC}"
    printf "%b\n" "${BLUE}Skipping pod readiness check...${NC}"
else
    # Wait for CSI driver pods to be ready
    echo "Waiting for NFS CSI driver pods to be ready..."
    MAX_WAIT=120
    ELAPSED=0
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        READY_PODS=$(kubectl get pods -n kube-system -l app=csi-nfs-node --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        if [ "$READY_PODS" -gt 0 ]; then
            printf "%b\n" "${GREEN}✓ CSI driver pods are running${NC}"
            break
        fi
        
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    done
    
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        printf "%b\n" "${YELLOW}⚠ Warning: CSI driver pods not ready after ${MAX_WAIT}s${NC}"
        echo "Check pod status with: kubectl get pods -n kube-system -l app=csi-nfs-node"
    fi
fi

echo ""

# Step 3: Check for CSI driver registration
printf "%b\n" "${GREEN}Step 3: Checking for CSI driver resources...${NC}"

CSIDRIVER=$(kubectl get csidriver nfs.csi.k8s.io --no-headers 2>/dev/null || echo "")

if [ -n "$CSIDRIVER" ]; then
    printf "%b\n" "${GREEN}✓ CSIDriver resource found${NC}"
else
    printf "%b\n" "${YELLOW}⚠ CSIDriver resource not found${NC}"
    echo "The driver may still be initializing"
fi

echo ""
printf "%b\n" "${GREEN}=== Installation Complete ===${NC}"
echo ""
printf "%b\n" "${BLUE}Next Steps:${NC}"
echo "  1. Run ./create-filestore.sh to create a Filestore instance"
echo "  2. Update harmony-storage chart values with Filestore details"
echo "  3. Deploy the harmony-storage Helm chart"
echo ""
printf "%b\n" "${BLUE}Verification Commands:${NC}"
echo "  kubectl get pods -n kube-system -l app=csi-nfs-node"
echo "  kubectl get csidriver nfs.csi.k8s.io"

