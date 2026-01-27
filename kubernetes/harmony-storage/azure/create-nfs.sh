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

STORAGE_ACCOUNT_PREFIX="harmonyconfignfs"
FILE_SHARE_NAME="harmony-config-share"



# Check prerequisites
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI not found. Please install it first and ensure it's configured."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found. Please install it first."
    exit 1
fi

# Configure Azure CLI to install extensions without prompts (required for aks commands)
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null || echo "Could not configure extension auto-install"
az config set extension.dynamic_install_allow_preview=true 2>/dev/null || echo "Could not configure preview extensions"

echo "Creating Azure Files NFS storage for cluster: $CLUSTER_NAME in resource group: $RESOURCE_GROUP"

# Function to generate random suffix (cross-platform compatible)
generate_random_suffix() {
    if command -v openssl &> /dev/null; then
        # Use openssl if available (Linux, macOS, Git Bash)
        openssl rand -hex 3
    elif command -v od &> /dev/null && [ -r /dev/urandom ]; then
        # Use od + /dev/urandom as fallback (Unix-like systems)
        od -N 3 -t x1 /dev/urandom | head -1 | awk '{print $2$3$4}' | tr -d ' '
    else
        # Last resort: use date + process ID (less secure but works everywhere)
        echo "$(date +%s)$$" | tail -c 7
    fi
}

# Generate unique storage account name (Azure storage account names must be globally unique)
RANDOM_SUFFIX=$(generate_random_suffix)
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX}"

# Check if storage account with the prefix already exists (check both user RG and managed RG)
echo "Checking if storage account with prefix '$STORAGE_ACCOUNT_PREFIX' already exists..."
echo "Checking in user resource group: $RESOURCE_GROUP"
USER_RG_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, '$STORAGE_ACCOUNT_PREFIX')].{name:name, location:location, resourceGroup: resourceGroup}" --output json)
echo "Checking in managed resource group: $NODE_RESOURCE_GROUP"
MANAGED_RG_ACCOUNTS=$(az storage account list --resource-group "$NODE_RESOURCE_GROUP" --query "[?starts_with(name, '$STORAGE_ACCOUNT_PREFIX')].{name:name, location:location, resourceGroup: resourceGroup}" --output json)

# Combine results
EXISTING_ACCOUNTS=$(echo "$USER_RG_ACCOUNTS $MANAGED_RG_ACCOUNTS" | jq -s 'add')

if [ "$(echo "$EXISTING_ACCOUNTS" | jq length)" -gt 0 ]; then
    echo "✅ Found existing storage account(s) with prefix '$STORAGE_ACCOUNT_PREFIX':"
    echo "$EXISTING_ACCOUNTS" | jq -r '.[] | "  - \(.name) in \(.location) (Resource Group: \(.resourceGroup))"'

    EXISTING_ACCOUNT_NAME=$(echo "$EXISTING_ACCOUNTS" | jq -r '.[0].name')
    EXISTING_ACCOUNT_RG=$(echo "$EXISTING_ACCOUNTS" | jq -r '.[0].resourceGroup')

    echo "📋 Using existing storage account: $EXISTING_ACCOUNT_NAME in resource group: $EXISTING_ACCOUNT_RG"

    # Get storage account key for authentication
    echo "Getting storage account key..."
    EXISTING_STORAGE_KEY=$(az storage account keys list --resource-group "$EXISTING_ACCOUNT_RG" --account-name "$EXISTING_ACCOUNT_NAME" --query '[0].value' --output tsv)

    # Check if file share exists
    EXISTING_SHARES=$(az storage share list --account-name "$EXISTING_ACCOUNT_NAME" --account-key "$EXISTING_STORAGE_KEY" --query "[?name=='$FILE_SHARE_NAME'].name" --output tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_SHARES" ]; then
        echo "✅ File share '$FILE_SHARE_NAME' already exists in storage account '$EXISTING_ACCOUNT_NAME'"
    else
        echo "Creating file share '$FILE_SHARE_NAME' in existing storage account..."

        # Temporarily allow all network access to enable file share creation
        echo "Temporarily allowing all network access for file share creation..."
        az storage account update \
            --name "$EXISTING_ACCOUNT_NAME" \
            --resource-group "$EXISTING_ACCOUNT_RG" \
            --default-action Allow \
            --output none

        # Wait for network access changes to propagate
        echo "Waiting for network access changes to propagate (60 seconds)..."
        sleep 60

        # Create the NFS file share using share-rm (supports NFS protocol)
        az storage share-rm create \
            --storage-account "$EXISTING_ACCOUNT_NAME" \
            --resource-group "$EXISTING_ACCOUNT_RG" \
            --name "$FILE_SHARE_NAME" \
            --enabled-protocols NFS \
            --quota 100

        SHARE_CREATE_RESULT=$?

        # Restore network restrictions
        echo "Restoring network access restrictions..."
        az storage account update \
            --name "$EXISTING_ACCOUNT_NAME" \
            --resource-group "$EXISTING_ACCOUNT_RG" \
            --default-action Deny \
            --output none

        if [ $SHARE_CREATE_RESULT -eq 0 ]; then
            echo "✅ Created file share: $FILE_SHARE_NAME"
            echo "   Note: NFS 4.1 protocol is automatically supported on Premium FileStorage accounts"
        else
            echo "❌ Failed to create file share"
            exit 1
        fi
    fi

    echo ""
    echo "To use this existing storage, update your my-values.yaml with:"
    echo "   persistence:"
    echo "     nfs:"
    echo "       storageAccountName: \"$EXISTING_ACCOUNT_NAME\""
    echo "       shareName: \"$FILE_SHARE_NAME\""
    exit 0
fi

echo "No existing storage account found with prefix '$STORAGE_ACCOUNT_PREFIX'. Creating new storage account..."

# Get cluster information including the managed resource group
echo "Getting cluster information..."
CLUSTER_INFO=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query '{vnetSubnetId: agentPoolProfiles[0].vnetSubnetId, nodeResourceGroup: nodeResourceGroup}' --output json)

VNET_SUBNET_ID=$(echo "$CLUSTER_INFO" | jq -r '.vnetSubnetId // empty')
NODE_RESOURCE_GROUP=$(echo "$CLUSTER_INFO" | jq -r '.nodeResourceGroup // empty')

if [ -z "$NODE_RESOURCE_GROUP" ] || [ "$NODE_RESOURCE_GROUP" = "null" ]; then
    echo "❌ Failed to get AKS managed resource group. Please check cluster name and resource group."
    exit 1
fi

echo "AKS managed resource group: $NODE_RESOURCE_GROUP"
echo "Note: Storage account will be created in the managed resource group for CSI driver compatibility"

if [ -n "$VNET_SUBNET_ID" ] && [ "$VNET_SUBNET_ID" != "null" ]; then
    echo "Cluster subnet ID: $VNET_SUBNET_ID"

    # Parse VNet information from the subnet resource ID
    # Format: /subscriptions/.../resourceGroups/RG/providers/Microsoft.Network/virtualNetworks/VNET/subnets/SUBNET
    VNET_NAME=$(echo "$VNET_SUBNET_ID" | cut -d'/' -f9)
    SUBNET_NAME=$(echo "$VNET_SUBNET_ID" | cut -d'/' -f11)
    VNET_RESOURCE_GROUP=$(echo "$VNET_SUBNET_ID" | cut -d'/' -f5)

    # Trim any whitespace
    VNET_NAME=$(echo "$VNET_NAME" | tr -d '[:space:]')
    SUBNET_NAME=$(echo "$SUBNET_NAME" | tr -d '[:space:]')
    VNET_RESOURCE_GROUP=$(echo "$VNET_RESOURCE_GROUP" | tr -d '[:space:]')
    VNET_SUBNET_ID=$(echo "$VNET_SUBNET_ID" | tr -d '[:space:]')

    echo "VNet: $VNET_NAME"
    echo "Subnet: $SUBNET_NAME"
    echo "VNet Resource Group: $VNET_RESOURCE_GROUP"
else
    echo "⚠️  Using default AKS networking (kubenet). Discovering VNet in managed resource group..."

    # For kubenet clusters, discover the VNet in the managed resource group
    VNET_INFO=$(az network vnet list --resource-group "$NODE_RESOURCE_GROUP" --query "[0].{name:name, subnets:subnets[?contains(name, 'aks-subnet') || contains(name, 'subnet')].{name:name, id:id}}" --output json 2>/dev/null)

    if [ -n "$VNET_INFO" ] && [ "$VNET_INFO" != "null" ] && [ "$VNET_INFO" != "{}" ]; then
        VNET_NAME=$(echo "$VNET_INFO" | jq -r '.name // empty')
        # Get the first suitable subnet (prefer aks-subnet)
        SUBNET_NAME=$(echo "$VNET_INFO" | jq -r '.subnets[0].name // empty')
        VNET_SUBNET_ID=$(echo "$VNET_INFO" | jq -r '.subnets[0].id // empty')
        VNET_RESOURCE_GROUP="$NODE_RESOURCE_GROUP"

        if [ -n "$VNET_NAME" ] && [ "$VNET_NAME" != "null" ] && [ -n "$SUBNET_NAME" ] && [ "$SUBNET_NAME" != "null" ] && [ -n "$VNET_SUBNET_ID" ] && [ "$VNET_SUBNET_ID" != "null" ]; then
            echo "✅ Discovered VNet in managed resource group:"
            echo "   VNet: $VNET_NAME"
            echo "   Subnet: $SUBNET_NAME"
            echo "   Subnet ID: $VNET_SUBNET_ID"
            echo "   Resource Group: $VNET_RESOURCE_GROUP"
        else
            echo "⚠️  Could not find suitable subnet in VNet. Network restrictions will be limited."
            VNET_SUBNET_ID=""
        fi
    else
        echo "⚠️  No VNet found in managed resource group. Network restrictions will be limited."
        VNET_SUBNET_ID=""
    fi
fi

# Create storage account with Premium tier for NFS support in the managed resource group
echo "Creating Premium storage account with NFS support in managed resource group..."
echo "Resource Group: $NODE_RESOURCE_GROUP (AKS managed resource group)"
az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$NODE_RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Premium_LRS \
    --kind FileStorage \
    --enable-large-file-share \
    --default-action Deny \
    --https-only false \
    --tags "cluster=$CLUSTER_NAME" "purpose=harmony-config" "origin-rg=$RESOURCE_GROUP"

if [ $? -ne 0 ]; then
    echo "❌ Failed to create storage account"
    exit 1
fi

echo "✅ Created storage account: $STORAGE_ACCOUNT_NAME"

# Wait for storage account to be fully provisioned
echo "Waiting for storage account to be ready..."
RETRIES=0
MAX_RETRIES=20
while true; do
    PROVISION_STATE=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$NODE_RESOURCE_GROUP" --query "provisioningState" --output tsv)
    if [ "$PROVISION_STATE" = "Succeeded" ]; then
        echo "Storage account is ready"
        break
    elif [ "$PROVISION_STATE" = "Failed" ]; then
        echo "❌ Storage account creation failed"
        exit 1
    else
        RETRIES=$((RETRIES + 1))
        if [ $RETRIES -ge $MAX_RETRIES ]; then
            echo "⚠️  Timeout waiting for storage account to be ready"
            break
        fi
        echo "Storage account state: $PROVISION_STATE - waiting 15 seconds..."
        sleep 15
    fi
done

# Configure network access if VNet integration is available
if [ -n "$VNET_SUBNET_ID" ] && [ "$VNET_SUBNET_ID" != "null" ]; then
    echo "Configuring network access for VNet integration..."
    echo "   Using subnet: $VNET_SUBNET_ID"

    # Add service endpoint for Azure Storage to the subnet
    echo "Adding Microsoft.Storage service endpoint to subnet..."
    if az network vnet subnet update \
        --resource-group "$VNET_RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --service-endpoints Microsoft.Storage \
        --output none 2>&1; then
        echo "✅ Service endpoint added"
    else
        echo "⚠️  Service endpoint may already exist or failed to add"
    fi

    # Add network rule for the cluster subnet
    echo "Adding network rule for cluster subnet..."

    # Use the full subnet resource ID directly (Azure CLI accepts either ID or name+vnet-name)
    NETWORK_RULE_OUTPUT=$(az storage account network-rule add \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --subnet "$VNET_SUBNET_ID" \
        --output none 2>&1)
    NETWORK_RULE_RESULT=$?

    if [ $NETWORK_RULE_RESULT -eq 0 ]; then
        echo "✅ Network rule added"
    else
        # If full ID failed, try with vnet-name and subnet name separately
        # Note: When the VNet is in a different resource group, we need to specify it
        echo "   Retrying with vnet-name and subnet name..."
        NETWORK_RULE_OUTPUT2=$(az network vnet subnet show \
            --resource-group "$VNET_RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$SUBNET_NAME" \
            --query id --output tsv 2>&1)

        if [ -n "$NETWORK_RULE_OUTPUT2" ] && [[ ! "$NETWORK_RULE_OUTPUT2" =~ "ERROR" ]]; then
            # Use the verified subnet ID
            if az storage account network-rule add \
                --resource-group "$NODE_RESOURCE_GROUP" \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --subnet "$NETWORK_RULE_OUTPUT2" \
                --output none 2>&1; then
                echo "✅ Network rule added (using verified subnet ID)"
            else
                echo "⚠️  Network rule may already exist or failed to add"
            fi
        else
            echo "⚠️  Network rule may already exist or failed to add"
        fi
    fi

    # Verify network rules were added
    echo "Verifying network configuration..."
    VNET_RULES=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$NODE_RESOURCE_GROUP" --query "networkRuleSet.virtualNetworkRules" --output json)
    if [ "$(echo "$VNET_RULES" | jq length)" -gt 0 ]; then
        echo "✅ Network rules verified: $(echo "$VNET_RULES" | jq length) rule(s) configured"
    else
        echo "❌ WARNING: No network rules found! Pods may not be able to mount the storage."
        echo "   You may need to manually add the network rule:"
        echo "   az storage account network-rule add --resource-group $NODE_RESOURCE_GROUP --account-name $STORAGE_ACCOUNT_NAME --subnet $VNET_SUBNET_ID"
    fi
else
    echo "⚠️  No VNet integration detected. Allowing access from all networks."
    az storage account update \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --default-action Allow \
        --output none
fi

# Get storage account key for file share operations
echo "Getting storage account key..."
STORAGE_KEY=$(az storage account keys list --resource-group "$NODE_RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT_NAME" --query '[0].value' --output tsv)

# Create NFS file share (Azure Files Premium supports NFS by default)
echo "Creating file share with NFS support..."

# Check current network access configuration
CURRENT_DEFAULT_ACTION=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$NODE_RESOURCE_GROUP" --query "networkRuleSet.defaultAction" --output tsv)

RESTORE_NETWORK_RULES=false
if [ "$CURRENT_DEFAULT_ACTION" = "Deny" ] && [ -n "$VNET_SUBNET_ID" ]; then
    echo "Temporarily allowing all network access for file share creation..."
    az storage account update \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --default-action Allow \
        --output none
    RESTORE_NETWORK_RULES=true
    echo "Waiting for network access changes to propagate (60 seconds)..."
    sleep 60
fi

# Create the NFS file share using share-rm (supports NFS protocol in newer Azure CLI)
az storage share-rm create \
    --storage-account "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$NODE_RESOURCE_GROUP" \
    --name "$FILE_SHARE_NAME" \
    --enabled-protocols NFS \
    --quota 100

SHARE_CREATE_RESULT=$?

# Restore network restrictions if we changed them
if [ "$RESTORE_NETWORK_RULES" = true ]; then
    echo "Restoring network access restrictions..."
    az storage account update \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$NODE_RESOURCE_GROUP" \
        --default-action Deny \
        --output none
fi

if [ $SHARE_CREATE_RESULT -eq 0 ]; then
    echo "✅ Created NFS file share: $FILE_SHARE_NAME"
    echo "   Protocol: NFS 4.1 (Premium FileStorage)"
else
    echo "❌ Failed to create NFS file share"
    exit 1
fi

# Get additional storage account information
echo "Getting storage account information..."
STORAGE_ENDPOINT=$(az storage account show --resource-group "$NODE_RESOURCE_GROUP" --name "$STORAGE_ACCOUNT_NAME" --query "primaryEndpoints.file" --output tsv)

echo ""
echo "✅ Azure Files NFS setup complete!"
echo "📋 Storage Account Name: $STORAGE_ACCOUNT_NAME"
echo "📋 File Share Name: $FILE_SHARE_NAME"
echo "📋 Storage Endpoint: $STORAGE_ENDPOINT"
echo ""
echo "Next steps:"
echo "1. Update your my-values.yaml with these details:"
echo "   persistence:"
echo "     nfs:"
echo "       storageAccountName: \"$STORAGE_ACCOUNT_NAME\""
echo "       shareName: \"$FILE_SHARE_NAME\""
echo ""
echo "2. Redeploy your Helm chart"
echo ""
echo "⚠️  IMPORTANT: Before deleting your AKS cluster, run:"
echo "   ./cleanup-nfs.sh"
echo "   This removes network dependencies and optionally deletes the storage account"
echo ""

# Create a summary file
cat > "./nfs-storage-info.txt" << EOF
Azure Files NFS Storage Configuration
====================================
Created: $(date)
Cluster: $CLUSTER_NAME
User Resource Group: $RESOURCE_GROUP
Managed Resource Group: $NODE_RESOURCE_GROUP
Location: $LOCATION

Storage Details:
- Storage Account: $STORAGE_ACCOUNT_NAME (in managed resource group)
- File Share: $FILE_SHARE_NAME
- Storage Endpoint: $STORAGE_ENDPOINT

Helm Configuration:
storageClass:
  nfs:
    storageAccountName: "$STORAGE_ACCOUNT_NAME"
    shareName: "$FILE_SHARE_NAME"

Cleanup Command:
./cleanup-nfs.sh
EOF

echo ""
echo "=== Azure Files NFS Created Successfully ==="
echo ""
echo "Storage Details:"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  File Share:      $FILE_SHARE_NAME"
echo "  Resource Group:  $NODE_RESOURCE_GROUP (AKS managed)"
echo "  Location:        $LOCATION"
echo ""
echo "Next Steps:"
echo "  1. Update your harmony-storage/my-values.yaml:"
echo "     global.platform: \"azure\""
echo "     storageClass.nfs.storageAccountName: \"$STORAGE_ACCOUNT_NAME\""
echo "     storageClass.nfs.shareName: \"$FILE_SHARE_NAME\""
echo ""
echo "  2. Install the harmony-storage chart:"
echo "     helm install harmony-storage . -f my-values.yaml -n harmony"
echo ""
echo "Verification Commands:"
echo "  az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $NODE_RESOURCE_GROUP"
echo "  kubectl get storageclass -n harmony"
echo ""
echo "Configuration details saved to: ./nfs-storage-info.txt"
echo "⚠️  IMPORTANT: Before deleting your AKS cluster, run:"
echo "   ./cleanup-nfs.sh"
echo "   This removes network dependencies and optionally deletes the storage account"
echo ""
echo "📄 Configuration details saved to: ./nfs-storage-info.txt"
