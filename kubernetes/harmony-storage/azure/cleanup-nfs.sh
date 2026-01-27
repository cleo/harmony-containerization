#!/bin/bash

# cleanup-nfs.sh - Cleanup Azure Files NFS resources before tearing down AKS cluster
# This script removes network access restrictions and optionally deletes storage accounts
# that prevent clean AKS cluster deletion.
#
# Usage:
#   ./cleanup-nfs.sh                    # Interactive mode - prompts for each deletion
#   ./cleanup-nfs.sh --delete-storage   # Automatically delete all storage accounts and shares
#   ./cleanup-nfs.sh --help             # Show help message

# Configuration - these must be set as environment variables before running the script
# Required environment variables:
# - CLUSTER_NAME: Your AKS cluster name
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
    echo "Azure Files NFS Cleanup Script"
    echo ""
    echo "Usage:"
    echo "  ./cleanup-nfs.sh                    # Interactive mode - prompts whether to delete storage"
    echo "  ./cleanup-nfs.sh --delete-storage   # Automatically delete all storage accounts and shares (no prompts)"
    echo "  ./cleanup-nfs.sh --help             # Show this help message"
    echo ""
    echo "Environment variables required:"
    echo "  CLUSTER_NAME      - Your AKS cluster name"
    echo "  RESOURCE_GROUP    - Your Azure resource group"
    echo "  LOCATION          - Your Azure region"
    echo ""
    echo "Examples:"
    echo "  source ./setup-env.sh && ./cleanup-nfs.sh"
    echo "  source ./setup-env.sh && ./cleanup-nfs.sh --delete-storage"
    exit 0
fi

# Configure Azure CLI to install extensions without prompts (required for aks commands)
az config set extension.use_dynamic_install=yes_without_prompt 2>/dev/null || echo "Could not configure extension auto-install"
az config set extension.dynamic_install_allow_preview=true 2>/dev/null || echo "Could not configure preview extensions"

echo "🧹 Azure Files NFS Cleanup Script for AKS Cluster: $CLUSTER_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "=================================================="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
if ! command_exists az; then
    echo "❌ Azure CLI not found. Please install it first."
    exit 1
fi

if ! command_exists kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install it first and ensure it's configured for your cluster."
    exit 1
fi



# Check if user is logged in
if ! az account show &> /dev/null; then
    echo "❌ You are not logged into Azure CLI. Please run 'az login' first."
    exit 1
fi

# Get AKS managed resource group
echo "📋 Getting AKS cluster information..."
NODE_RESOURCE_GROUP=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query 'nodeResourceGroup' --output tsv 2>/dev/null || echo "")

if [ -n "$NODE_RESOURCE_GROUP" ] && [ "$NODE_RESOURCE_GROUP" != "null" ]; then
    echo "AKS managed resource group: $NODE_RESOURCE_GROUP"
else
    echo "⚠️  Could not determine AKS managed resource group. Will check user resource group only."
    NODE_RESOURCE_GROUP=""
fi

# Find storage accounts with the harmony config prefix (check both resource groups)
echo "📋 Finding Azure Files storage accounts..."
echo "Checking in user resource group: $RESOURCE_GROUP"
USER_RG_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, '$STORAGE_ACCOUNT_PREFIX')].{name:name, location:location, tags:tags, resourceGroup: resourceGroup}" --output json)

if [ -n "$NODE_RESOURCE_GROUP" ]; then
    echo "Checking in managed resource group: $NODE_RESOURCE_GROUP"
    MANAGED_RG_ACCOUNTS=$(az storage account list --resource-group "$NODE_RESOURCE_GROUP" --query "[?starts_with(name, '$STORAGE_ACCOUNT_PREFIX')].{name:name, location:location, tags:tags, resourceGroup: resourceGroup}" --output json)
    # Combine results
    STORAGE_ACCOUNTS=$(echo "$USER_RG_ACCOUNTS $MANAGED_RG_ACCOUNTS" | jq -s 'add')
else
    STORAGE_ACCOUNTS="$USER_RG_ACCOUNTS"
fi

if [ "$(echo "$STORAGE_ACCOUNTS" | jq length)" -eq 0 ]; then
    echo "ℹ️  No storage accounts found with prefix '$STORAGE_ACCOUNT_PREFIX'. Nothing to clean up."
    exit 0
fi

echo "Found storage accounts:"
echo "$STORAGE_ACCOUNTS" | jq -r '.[] | "  - \(.name) in \(.location) (Resource Group: \(.resourceGroup))"'

# Process each storage account
# Use process substitution to avoid subshell issues with variables
while read -r STORAGE_ACCOUNT_NAME STORAGE_RG; do
    echo ""
    echo "🗑️  Processing storage account: $STORAGE_ACCOUNT_NAME (in $STORAGE_RG)"

    # Get current network access configuration
    echo "📋 Checking network access configuration..."
    NETWORK_CONFIG=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$STORAGE_RG" --query '{defaultAction: networkRuleSet.defaultAction, virtualNetworkRules: networkRuleSet.virtualNetworkRules}' --output json)
    DEFAULT_ACTION=$(echo "$NETWORK_CONFIG" | jq -r '.defaultAction // "Allow"')
    VNET_RULES=$(echo "$NETWORK_CONFIG" | jq -r '.virtualNetworkRules // []')

    echo "Current default action: $DEFAULT_ACTION"

    # Remove VNet rules if they exist
    if [ "$(echo "$VNET_RULES" | jq length)" -gt 0 ]; then
        echo "🗑️  Removing VNet network rules..."
        echo "$VNET_RULES" | jq -r '.[].virtualNetworkResourceId' | while read -r SUBNET_ID; do
            if [ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "null" ]; then
                echo "Removing network rule for subnet: $SUBNET_ID"
                az storage account network-rule remove \
                    --resource-group "$STORAGE_RG" \
                    --account-name "$STORAGE_ACCOUNT_NAME" \
                    --subnet "$SUBNET_ID" 2>/dev/null || echo "Network rule may already be removed"
            fi
        done
    else
        echo "ℹ️  No VNet network rules found"
    fi

    # Set default action to Allow to remove network restrictions
    if [ "$DEFAULT_ACTION" = "Deny" ]; then
        echo "🔓 Removing network access restrictions..."
        az storage account update \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$STORAGE_RG" \
            --default-action Allow
        echo "✅ Network access restrictions removed"
    else
        echo "ℹ️  No network restrictions to remove"
    fi
done < <(echo "$STORAGE_ACCOUNTS" | jq -r '.[] | "\(.name) \(.resourceGroup)"')

# Process storage account cleanup based on mode
echo ""
if [ "$DELETE_STORAGE" = true ]; then
    echo "🗑️  Automatic storage deletion mode enabled"
    echo "⚠️  WARNING: This will PERMANENTLY delete all storage accounts and data!"
    sleep 2
else
    # Prompt user upfront about whether to delete storage
    echo ""
    echo "⚠️  Storage accounts were found. Would you like to delete them?"
    echo "   This will PERMANENTLY delete all storage accounts and their data!"
    read -p "Delete storage accounts? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        DELETE_STORAGE=true
        echo "🗑️  Storage deletion enabled"
    else
        echo "ℹ️  Storage accounts will be preserved (network restrictions removed only)"
    fi
fi

# Use process substitution to avoid subshell issues with variables like DELETE_STORAGE
while read -r STORAGE_ACCOUNT_NAME STORAGE_RG; do
    echo "🗑️  Storage account: $STORAGE_ACCOUNT_NAME (in $STORAGE_RG)"

    # Get storage account key for authentication
    STORAGE_KEY=$(az storage account keys list --resource-group "$STORAGE_RG" --account-name "$STORAGE_ACCOUNT_NAME" --query '[0].value' --output tsv 2>/dev/null)

    # Ensure network access is allowed for storage operations
    CURRENT_DEFAULT_ACTION=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$STORAGE_RG" --query "networkRuleSet.defaultAction" --output tsv 2>/dev/null || echo "Allow")
    NEED_TO_RESTORE_ACCESS=false

    if [ "$CURRENT_DEFAULT_ACTION" = "Deny" ]; then
        echo "Temporarily allowing network access for storage operations..."
        az storage account update --name "$STORAGE_ACCOUNT_NAME" --resource-group "$STORAGE_RG" --default-action Allow --output none
        NEED_TO_RESTORE_ACCESS=true
        sleep 5
    fi

    # List file shares
    if [ -n "$STORAGE_KEY" ]; then
        FILE_SHARES=$(az storage share list --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$STORAGE_KEY" --query '[].name' --output tsv 2>/dev/null || echo "")
    else
        echo "⚠️  Could not get storage account key, unable to list file shares"
        FILE_SHARES=""
    fi

    # Handle file share deletion based on mode
    if [ -n "$FILE_SHARES" ]; then
        echo "File shares in this storage account:"
        for share in $FILE_SHARES; do
            echo "  - $share"
        done
        echo ""

        if [ "$DELETE_STORAGE" = true ]; then
            echo "🗑️  Deleting file shares..."
            for share in $FILE_SHARES; do
                echo "Deleting file share: $share"
                az storage share delete \
                    --account-name "$STORAGE_ACCOUNT_NAME" \
                    --account-key "$STORAGE_KEY" \
                    --name "$share" \
                    --delete-snapshots include 2>/dev/null || echo "Failed to delete $share"
            done
            echo "✅ File shares deletion completed"
        else
            echo "ℹ️  File shares preserved in storage account: $STORAGE_ACCOUNT_NAME"
        fi
    else
        echo "ℹ️  No file shares found in storage account"
    fi

    # Handle storage account deletion based on mode
    echo ""
    if [ "$DELETE_STORAGE" = true ]; then
        echo "🗑️  Deleting storage account: $STORAGE_ACCOUNT_NAME"
        az storage account delete \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$STORAGE_RG" \
            --yes
        echo "✅ Storage account deletion initiated: $STORAGE_ACCOUNT_NAME"
    else
        echo "ℹ️  Storage account preserved: $STORAGE_ACCOUNT_NAME"
        echo "📋 To delete it later, run:"
        echo "   az storage account delete --name $STORAGE_ACCOUNT_NAME --resource-group $STORAGE_RG --yes"

        # Only restore network access restrictions if we're keeping the storage account
        if [ "$NEED_TO_RESTORE_ACCESS" = true ]; then
            echo "Restoring network access restrictions..."
            az storage account update --name "$STORAGE_ACCOUNT_NAME" --resource-group "$STORAGE_RG" --default-action Deny --output none
        fi
    fi

    echo ""
done < <(echo "$STORAGE_ACCOUNTS" | jq -r '.[] | "\(.name) \(.resourceGroup)"')

# Clean up service endpoints from cluster subnets
echo "🗑️  Checking for service endpoints to clean up..."

# Get cluster subnet information if cluster still exists
CLUSTER_INFO=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query '{vnetSubnetId: agentPoolProfiles[0].vnetSubnetId}' --output json 2>/dev/null || echo '{}')
VNET_SUBNET_ID=$(echo "$CLUSTER_INFO" | jq -r '.vnetSubnetId // empty')

if [ -n "$VNET_SUBNET_ID" ] && [ "$VNET_SUBNET_ID" != "null" ]; then
    # Parse VNet information
    VNET_NAME=$(echo "$VNET_SUBNET_ID" | cut -d'/' -f9)
    SUBNET_NAME=$(echo "$VNET_SUBNET_ID" | cut -d'/' -f11)
    VNET_RESOURCE_GROUP=$(echo "$VNET_SUBNET_ID" | cut -d'/' -f5)

    echo "Cluster subnet: $VNET_NAME/$SUBNET_NAME in resource group $VNET_RESOURCE_GROUP"

    # Check current service endpoints
    CURRENT_ENDPOINTS=$(az network vnet subnet show --resource-group "$VNET_RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --query 'serviceEndpoints[].service' --output tsv 2>/dev/null || echo "")

    if echo "$CURRENT_ENDPOINTS" | grep -q "Microsoft.Storage"; then
        echo "Found Microsoft.Storage service endpoint"
        read -p "Remove Microsoft.Storage service endpoint from subnet? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Get all current service endpoints except Microsoft.Storage
            OTHER_ENDPOINTS=$(echo "$CURRENT_ENDPOINTS" | grep -v "Microsoft.Storage" | tr '\n' ' ')

            if [ -n "$OTHER_ENDPOINTS" ] && [ "$OTHER_ENDPOINTS" != " " ]; then
                echo "Updating service endpoints (keeping: $OTHER_ENDPOINTS)..."
                az network vnet subnet update \
                    --resource-group "$VNET_RESOURCE_GROUP" \
                    --vnet-name "$VNET_NAME" \
                    --name "$SUBNET_NAME" \
                    --service-endpoints $OTHER_ENDPOINTS
            else
                echo "Removing all service endpoints..."
                # Remove service endpoints by updating without the --service-endpoints parameter
                # This effectively clears all service endpoints
                az network vnet subnet update \
                    --resource-group "$VNET_RESOURCE_GROUP" \
                    --vnet-name "$VNET_NAME" \
                    --name "$SUBNET_NAME" \
                    --remove serviceEndpoints
            fi
            echo "✅ Service endpoint cleanup completed"
        else
            echo "ℹ️  Service endpoint preserved"
        fi
    else
        echo "ℹ️  No Microsoft.Storage service endpoint found"
    fi
else
    echo "ℹ️  No cluster subnet information available (cluster may be deleted or using default networking)"
fi

# Clean up info file if it exists
if [ -f "./nfs-storage-info.txt" ]; then
    echo ""
    DELETE_CONFIG=false
    if [ "$DELETE_STORAGE" = true ]; then
        echo "🗑️  Automatically removing configuration file (--delete-storage mode)..."
        DELETE_CONFIG=true
    else
        read -p "Remove local configuration file './nfs-storage-info.txt'? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            DELETE_CONFIG=true
        fi
    fi

    if [ "$DELETE_CONFIG" = true ]; then
        rm "./nfs-storage-info.txt"
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
    echo "  ✓ Storage account and file shares"
fi
echo "  ✓ Network access rules"
echo "  ✓ Configuration files"
echo ""
echo "All Azure Files NFS resources have been cleaned up"
echo ""
echo "Next Steps:"
echo "  - You can now safely delete your AKS cluster if needed"
echo "  - To recreate the NFS storage, run: ./create-nfs.sh"
echo "Useful commands for verification:"
echo "# Check remaining storage accounts in user resource group:"
echo "az storage account list --resource-group $RESOURCE_GROUP --query \"[?starts_with(name, '$STORAGE_ACCOUNT_PREFIX')]\""
if [ -n "$NODE_RESOURCE_GROUP" ]; then
    echo "# Check remaining storage accounts in managed resource group:"
    echo "az storage account list --resource-group $NODE_RESOURCE_GROUP --query \"[?starts_with(name, '$STORAGE_ACCOUNT_PREFIX')]\""
fi
echo ""
if [ -n "$VNET_SUBNET_ID" ] && [ "$VNET_SUBNET_ID" != "null" ]; then
    echo "# Check subnet service endpoints:"
    echo "az network vnet subnet show --resource-group $VNET_RESOURCE_GROUP --vnet-name $VNET_NAME --name $SUBNET_NAME --query serviceEndpoints"
fi
