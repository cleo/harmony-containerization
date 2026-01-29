#!/bin/bash

# setup-env.sh - Helper script to set up environment variables for Azure NFS scripts
# Configuration - these must be set as environment variables before running the script
#
# IMPORTANT: To make environment variables available in your current terminal,
# you must SOURCE this script instead of executing it:
#
#   source ./setup-env.sh
#   OR
#   . ./setup-env.sh
#
# Do NOT run: ./setup-env.sh (variables will be lost when script exits)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

printf "%b\n" "${GREEN}🔧 Azure NFS Scripts Environment Setup${NC}"
echo "======================================"

# Cross-platform compatibility check
check_platform_compatibility() {
    local platform_detected="unknown"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        platform_detected="Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        platform_detected="macOS"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        platform_detected="Windows (Git Bash/Cygwin)"
    else
        platform_detected="Unknown ($OSTYPE)"
    fi
    
    echo "Platform detected: $platform_detected"
    
    # Check for required commands
    local missing_commands=()
    
    if ! command -v az &> /dev/null; then
        missing_commands+=("az")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_commands+=("kubectl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_commands+=("jq")
    fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        printf "%b\n" "${RED}❌ Missing required commands: ${missing_commands[*]}${NC}"
        echo ""
        echo "Installation instructions:"
        if [[ "$platform_detected" == "Linux"* ]]; then
            echo "  Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
            echo "  jq: sudo apt-get install jq (Ubuntu/Debian) or sudo yum install jq (RHEL/CentOS)"
        elif [[ "$platform_detected" == "macOS"* ]]; then
            echo "  Azure CLI: brew install azure-cli"
            echo "  kubectl: brew install kubectl"
            echo "  jq: brew install jq"
        elif [[ "$platform_detected" == *"Windows"* ]]; then
            echo "  Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
            echo "  jq: Download from https://stedolan.github.io/jq/"
        fi
        return 1
    fi
    
    printf "%b\n" "${GREEN}✅ All required commands available${NC}"
    return 0
}

# Run platform compatibility check
if ! check_platform_compatibility; then
    exit 1
fi
echo ""

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf "%b\n" "${YELLOW}⚠️  WARNING: This script is being executed, not sourced!${NC}"
    echo "Environment variables will NOT be available in your terminal after this script finishes."
    echo ""
    echo "To make variables available in your current terminal, please run:"
    echo "  source ./setup-env.sh"
    echo "  OR"
    echo "  . ./setup-env.sh"
    echo ""
    read -p "Continue anyway? The script will create an export file you can source. (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please run: source ./setup-env.sh"
        exit 1
    fi
    CREATE_EXPORT_FILE=true
else
    printf "%b\n" "${GREEN}✅ Script is being sourced - variables will be available in this terminal!${NC}"
    CREATE_EXPORT_FILE=false
fi
echo ""

# Check if user is logged in
if ! az account show &> /dev/null; then
    printf "%b\n" "${RED}❌ You are not logged into Azure CLI. Please run 'az login' first.${NC}"
    exit 1
fi

echo ""
echo "Let's configure your environment variables for the Azure NFS scripts."
echo ""

# Get available clusters
echo "📋 Finding your AKS clusters..."
AVAILABLE_CLUSTERS=$(az aks list --query '[].name' --output tsv 2>/dev/null)

if [ -z "$AVAILABLE_CLUSTERS" ]; then
    printf "%b\n" "${RED}❌ No AKS clusters found or unable to list clusters.${NC}"
    echo "Please check your Azure CLI configuration and permissions."
    exit 1
fi

echo "Available AKS clusters:"
for cluster in $AVAILABLE_CLUSTERS; do
    echo "  - $cluster"
done

echo ""
read -p "Enter your AKS cluster name: " CLUSTER_NAME

if [ -z "$CLUSTER_NAME" ]; then
    printf "%b\n" "${RED}❌ Cluster name cannot be empty.${NC}"
    exit 1
fi

# Validate cluster exists and find resource group and location
echo "📋 Validating cluster '$CLUSTER_NAME'..."
CLUSTER_INFO=$(az aks list --query "[?name=='$CLUSTER_NAME'] | [0].{resourceGroup: resourceGroup, location: location, nodeResourceGroup: nodeResourceGroup}" --output json 2>/dev/null)

if [ -z "$CLUSTER_INFO" ] || [ "$CLUSTER_INFO" = "null" ]; then
    printf "%b\n" "${RED}❌ Cluster '$CLUSTER_NAME' not found.${NC}"
    echo "Please check the cluster name and try again."
    exit 1
fi

RESOURCE_GROUP=$(echo "$CLUSTER_INFO" | jq -r '.resourceGroup')
LOCATION=$(echo "$CLUSTER_INFO" | jq -r '.location')
NODE_RESOURCE_GROUP=$(echo "$CLUSTER_INFO" | jq -r '.nodeResourceGroup')

printf "%b\n" "${GREEN}✅ Found cluster '$CLUSTER_NAME' in resource group '$RESOURCE_GROUP', location '$LOCATION'${NC}"

# Set environment variables
export CLUSTER_NAME="$CLUSTER_NAME"
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export NODE_RESOURCE_GROUP="$NODE_RESOURCE_GROUP"

echo ""
printf "%b\n" "${GREEN}🎉 Environment variables configured successfully!${NC}"
echo ""
echo "Current configuration:"
echo "  CLUSTER_NAME: $CLUSTER_NAME"
echo "  RESOURCE_GROUP: $RESOURCE_GROUP"
echo "  LOCATION: $LOCATION"
echo "  NODE_RESOURCE_GROUP: $NODE_RESOURCE_GROUP"
echo ""

# If script was executed (not sourced), create an export file
if [ "$CREATE_EXPORT_FILE" = true ]; then
    EXPORT_FILE="./aks-env-vars.sh"
    cat > "$EXPORT_FILE" << EOF
#!/bin/bash
# Auto-generated environment variables for Azure NFS scripts
export CLUSTER_NAME="$CLUSTER_NAME"
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export NODE_RESOURCE_GROUP="$NODE_RESOURCE_GROUP"
EOF
    chmod +x "$EXPORT_FILE"
    echo "📁 Created export file: $EXPORT_FILE"
    echo "To load these variables in your current terminal, run:"
    echo "  source $EXPORT_FILE"
    echo ""
fi

# Offer to make it persistent
echo "Would you like to make these environment variables persistent?"
echo "This will add them to your shell profile so they're available in new terminals."
read -p "Make persistent? (y/N): " -r

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Detect shell
    if [ -n "$BASH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.bashrc"
        SHELL_NAME="bash"
    elif [ -n "$ZSH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.zshrc"
        SHELL_NAME="zsh"
    else
        echo "Unable to detect shell type. Please manually add these lines to your shell profile:"
        echo "  export CLUSTER_NAME=\"$CLUSTER_NAME\""
        echo "  export RESOURCE_GROUP=\"$RESOURCE_GROUP\""
        echo "  export LOCATION=\"$LOCATION\""
        echo "  export NODE_RESOURCE_GROUP=\"$NODE_RESOURCE_GROUP\""
        exit 0
    fi

    # Check if variables already exist in profile
    if grep -q "export CLUSTER_NAME=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing CLUSTER_NAME in $SHELL_PROFILE"
        sed -i.bak "s/export CLUSTER_NAME=.*/export CLUSTER_NAME=\"$CLUSTER_NAME\"/" "$SHELL_PROFILE"
    else
        echo "export CLUSTER_NAME=\"$CLUSTER_NAME\"" >> "$SHELL_PROFILE"
    fi

    if grep -q "export RESOURCE_GROUP=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing RESOURCE_GROUP in $SHELL_PROFILE"
        sed -i.bak "s/export RESOURCE_GROUP=.*/export RESOURCE_GROUP=\"$RESOURCE_GROUP\"/" "$SHELL_PROFILE"
    else
        echo "export RESOURCE_GROUP=\"$RESOURCE_GROUP\"" >> "$SHELL_PROFILE"
    fi

    if grep -q "export LOCATION=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing LOCATION in $SHELL_PROFILE"
        sed -i.bak "s/export LOCATION=.*/export LOCATION=\"$LOCATION\"/" "$SHELL_PROFILE"
    else
        echo "export LOCATION=\"$LOCATION\"" >> "$SHELL_PROFILE"
    fi

    if grep -q "export NODE_RESOURCE_GROUP=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing NODE_RESOURCE_GROUP in $SHELL_PROFILE"
        sed -i.bak "s/export NODE_RESOURCE_GROUP=.*/export NODE_RESOURCE_GROUP=\"$NODE_RESOURCE_GROUP\"/" "$SHELL_PROFILE"
    else
        echo "export NODE_RESOURCE_GROUP=\"$NODE_RESOURCE_GROUP\"" >> "$SHELL_PROFILE"
    fi

    echo "✅ Environment variables added to $SHELL_PROFILE"
    echo "They will be available in new terminal sessions."
fi

echo ""
printf "%b\n" "${GREEN}🚀 You're ready to run the Azure NFS scripts!${NC}"
echo ""
echo "Next steps:"
echo "1. Install Azure Files CSI driver:  ./install-nfs-csi-driver.sh"
echo "2. Create NFS storage account:      ./create-nfs.sh"
echo "3. When done, cleanup:              ./cleanup-nfs.sh"
echo ""

if [ "$CREATE_EXPORT_FILE" = true ]; then
    echo "Remember: Since this script was executed (not sourced), run this first:"
    echo "  source ./aks-env-vars.sh"
    echo ""
else
    printf "%b\n" "${GREEN}✅ Environment variables are available in this terminal session.${NC}"
fi

if [[ ! $REPLY =~ ^[Yy]$ ]] && [ "$CREATE_EXPORT_FILE" = true ]; then
    echo "If you open a new terminal, you'll need to run:"
    echo "  source ./setup-env.sh"
    echo "or"
    echo "  source ./aks-env-vars.sh"
    echo "or manually set the variables with:"
    echo "  export CLUSTER_NAME=\"$CLUSTER_NAME\""
    echo "  export RESOURCE_GROUP=\"$RESOURCE_GROUP\""
    echo "  export LOCATION=\"$LOCATION\""
    echo "  export NODE_RESOURCE_GROUP=\"$NODE_RESOURCE_GROUP\""
fi
