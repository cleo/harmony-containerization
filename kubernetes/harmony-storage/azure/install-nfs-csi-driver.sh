#!/bin/bash

# Configuration - these must be set as environment variables before running the script
# Required environment variables:
# - CLUSTER_NAME: Your AKS cluster name
# - RESOURCE_GROUP: Your Azure resource group
# - LOCATION: Your Azure region
if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: CLUSTER_NAME environment variable is not set."
    echo "Please set it before running this script:"
    echo "  export CLUSTER_NAME=your-cluster-name"
    exit 1
fi

if [ -z "$RESOURCE_GROUP" ]; then
    echo "Error: RESOURCE_GROUP environment variable is not set."
    echo "Please set it before running this script:"
    echo "  export RESOURCE_GROUP=your-resource-group"
    exit 1
fi

if [ -z "$LOCATION" ]; then
    echo "Error: LOCATION environment variable is not set."
    echo "Please set it before running this script:"
    echo "  export LOCATION=your-azure-region"
    exit 1
fi

echo "Using configuration:"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo ""

# --- Prerequisites Check ---

# Check prerequisites
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install it first and ensure it's configured."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install it first and ensure it's configured for your cluster."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    echo "Error: You are not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Configure Azure CLI to install extensions without prompts (required for aks commands)
echo "Configuring Azure CLI for automatic extension installation..."
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null || echo "Could not configure extension auto-install"
az config set extension.dynamic_install_allow_preview=true 2>/dev/null || echo "Could not configure preview extensions"

echo "--- Starting Azure Files NFS CSI Driver Installation for cluster: ${CLUSTER_NAME} in resource group: ${RESOURCE_GROUP} ---"

# --- Step 1: Check Current Addon Status ---

echo "1. Checking Azure Files CSI driver status..."

# Check if CSI driver node pods are running (Azure Files CSI driver is enabled by default in modern AKS)
# Note: Modern AKS clusters (1.21+) only deploy csi-azurefile-node pods. The controller functionality
# is managed by Azure and does not require separate controller pods in the cluster.
CSI_NODE_PODS=$(kubectl get pods -n kube-system -l app=csi-azurefile-node --no-headers 2>/dev/null | wc -l)

if [ "$CSI_NODE_PODS" -gt 0 ]; then
    echo "   ✅ Azure Files CSI driver is running."
    echo "   Node pods: $CSI_NODE_PODS (one per node is expected)"
else
    echo "   ⚠️  Azure Files CSI driver node pods not found."
    echo "   This may indicate an older AKS cluster or configuration issue."
    echo "   Azure Files CSI driver is enabled by default in AKS 1.21+ clusters."
    echo ""
    echo "   If you're using an older cluster, you may need to:"
    echo "   1. Upgrade your AKS cluster to a supported version"
    echo "   2. Manually install the Azure Files CSI driver"
    echo ""
    echo "   Continuing with storage class creation..."
fi

# --- Step 2: Verification ---

echo "2. Verifying CSI driver readiness (this may take a minute or two)..."

# Wait for pods to be ready
RETRIES=0
MAX_RETRIES=12  # Wait up to 6 minutes
while true; do
    # Use a more robust way to count running pods
    NODE_READY=0
    if kubectl get pods -n kube-system -l app=csi-azurefile-node --no-headers 2>/dev/null | grep -q "Running"; then
        NODE_READY=$(kubectl get pods -n kube-system -l app=csi-azurefile-node --no-headers 2>/dev/null | grep -c "Running")
    fi

    if [ "$NODE_READY" -gt 0 ]; then
        echo "   Success: Azure Files CSI driver pods are running."
        echo "   Node pods ready: $NODE_READY"
        break
    fi

    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "   Warning: Timeout waiting for CSI driver pods to be ready."
        echo "   Current status:"
        echo "     Node pods ready: $NODE_READY"
        echo "   You can check pod status with:"
        echo "     kubectl get pods -n kube-system -l app=csi-azurefile-node"
        break
    fi

    echo "   Waiting for CSI driver pods to be ready... (attempt $RETRIES/$MAX_RETRIES)"
    sleep 30
done

# --- Step 3: Check Storage Classes ---

echo "3. Checking for Azure Files storage classes..."

# List Azure Files storage classes
STORAGE_CLASSES=$(kubectl get storageclass --no-headers 2>/dev/null | grep "file.csi.azure.com" | awk '{print $1}' || echo "")

if [ -n "$STORAGE_CLASSES" ]; then
    echo "   Found Azure Files storage classes:"
    for sc in $STORAGE_CLASSES; do
        echo "     - $sc"
    done
else
    echo "   No Azure Files storage classes found. Creating default NFS storage class..."

    # Create NFS storage class
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azurefile-nfs
  labels:
    kubernetes.io/cluster-service: "true"
provisioner: file.csi.azure.com
parameters:
  protocol: nfs
  skuName: Premium_LRS
allowVolumeExpansion: true
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=4.1
EOF

    if [ $? -eq 0 ]; then
        echo "   Success: Created azurefile-nfs storage class."
    else
        echo "   Warning: Failed to create NFS storage class."
    fi
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next Steps:"
echo "  1. Run ./create-nfs.sh to create an Azure Files NFS storage account"
echo "  2. Update harmony-storage chart values with storage account details"
echo "  3. Deploy the harmony-storage Helm chart"
echo ""
echo "Verification Commands:"
echo "  kubectl get pods -n kube-system -l app=csi-azurefile-node"
echo "  kubectl get storageclass | grep file.csi.azure.com"
