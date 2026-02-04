#!/bin/bash

# setup-env.sh - Helper script to set up environment variables for EFS scripts
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

printf "%b\n" "${GREEN}🔧 EFS Scripts Environment Setup${NC}"
echo "================================"

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
    
    if ! command -v aws &> /dev/null; then
        missing_commands+=("aws")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_commands+=("kubectl")
    fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        printf "%b\n" "${RED}❌ Missing required commands: ${missing_commands[*]}${NC}"
        echo ""
        echo "Installation instructions:"
        if [[ "$platform_detected" == "Linux"* ]]; then
            echo "  AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        elif [[ "$platform_detected" == "macOS"* ]]; then
            echo "  AWS CLI: brew install awscli"
            echo "  kubectl: brew install kubectl"
        elif [[ "$platform_detected" == *"Windows"* ]]; then
            echo "  AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
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
if ! aws sts get-caller-identity &> /dev/null; then
    printf "%b\n" "${RED}❌ You are not logged into AWS CLI. Please run 'aws configure' first.${NC}"
    exit 1
fi

echo ""
echo "Let's configure your environment variables for the EFS scripts."
echo ""

# Get available clusters
echo "📋 Finding your EKS clusters..."
AVAILABLE_CLUSTERS=$(aws eks list-clusters --query 'clusters' --output text 2>/dev/null)

if [ -z "$AVAILABLE_CLUSTERS" ]; then
    printf "%b\n" "${RED}❌ No EKS clusters found or unable to list clusters.${NC}"
    echo "Please check your AWS CLI configuration and permissions."
    exit 1
fi

echo "Available EKS clusters:"
for cluster in $AVAILABLE_CLUSTERS; do
    echo "  - $cluster"
done

echo ""
read -p "Enter your EKS cluster name: " CLUSTER_NAME

if [ -z "$CLUSTER_NAME" ]; then
    printf "%b\n" "${RED}❌ Cluster name cannot be empty.${NC}"
    exit 1
fi

# Validate cluster exists
echo "📋 Validating cluster '$CLUSTER_NAME'..."
# Only check common regions to speed up validation
REGIONS="us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-central-1 ca-central-1"

CLUSTER_FOUND=false
CLUSTER_REGION=""

for region in $REGIONS; do
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$region" &>/dev/null; then
        CLUSTER_FOUND=true
        CLUSTER_REGION="$region"
        break
    fi
done

if [ "$CLUSTER_FOUND" = false ]; then
    printf "%b\n" "${RED}❌ Cluster '$CLUSTER_NAME' not found in any region.${NC}"
    echo "Please check the cluster name and try again."
    exit 1
fi

printf "%b\n" "${GREEN}✅ Found cluster '$CLUSTER_NAME' in region '$CLUSTER_REGION'${NC}"

# Set environment variables
export CLUSTER_NAME="$CLUSTER_NAME"
export CLUSTER_REGION="$CLUSTER_REGION"

echo ""
printf "%b\n" "${GREEN}🎉 Environment variables configured successfully!${NC}"
echo ""
echo "Current configuration:"
echo "  CLUSTER_NAME: $CLUSTER_NAME"
echo "  CLUSTER_REGION: $CLUSTER_REGION"
echo ""

# If script was executed (not sourced), create an export file
if [ "$CREATE_EXPORT_FILE" = true ]; then
    EXPORT_FILE="./eks-env-vars.sh"
    cat > "$EXPORT_FILE" << EOF
#!/bin/bash
# Auto-generated environment variables for EFS scripts
export CLUSTER_NAME="$CLUSTER_NAME"
export CLUSTER_REGION="$CLUSTER_REGION"
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
        echo "  export CLUSTER_REGION=\"$CLUSTER_REGION\""
        exit 0
    fi

    # Check if variables already exist in profile
    if grep -q "export CLUSTER_NAME=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing CLUSTER_NAME in $SHELL_PROFILE"
        sed -i.bak "s/export CLUSTER_NAME=.*/export CLUSTER_NAME=\"$CLUSTER_NAME\"/" "$SHELL_PROFILE"
    else
        echo "export CLUSTER_NAME=\"$CLUSTER_NAME\"" >> "$SHELL_PROFILE"
    fi

    if grep -q "export CLUSTER_REGION=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing CLUSTER_REGION in $SHELL_PROFILE"
        sed -i.bak "s/export CLUSTER_REGION=.*/export CLUSTER_REGION=\"$CLUSTER_REGION\"/" "$SHELL_PROFILE"
    else
        echo "export CLUSTER_REGION=\"$CLUSTER_REGION\"" >> "$SHELL_PROFILE"
    fi

    echo "✅ Environment variables added to $SHELL_PROFILE"
    echo "They will be available in new terminal sessions."
fi

echo ""
printf "%b\n" "${GREEN}🚀 You're ready to run the EFS scripts!${NC}"
echo ""
echo "Next steps:"
echo "1. Install EFS CSI driver:  ./install-efs-csi-driver.sh"
echo "2. Create EFS file system:  ./create-efs.sh"
echo "3. When done, cleanup:      ./cleanup-efs.sh"
echo ""

if [ "$CREATE_EXPORT_FILE" = true ]; then
    echo "Remember: Since this script was executed (not sourced), run this first:"
    echo "  source ./eks-env-vars.sh"
    echo ""
else
    printf "%b\n" "${GREEN}✅ Environment variables are available in this terminal session.${NC}"
fi

if [[ ! $REPLY =~ ^[Yy]$ ]] && [ "$CREATE_EXPORT_FILE" = true ]; then
    echo "If you open a new terminal, you'll need to run:"
    echo "  source ./setup-env.sh"
    echo "or"
    echo "  source ./eks-env-vars.sh"
    echo "or manually set the variables with:"
    echo "  export CLUSTER_NAME=\"$CLUSTER_NAME\""
    echo "  export CLUSTER_REGION=\"$CLUSTER_REGION\""
fi
