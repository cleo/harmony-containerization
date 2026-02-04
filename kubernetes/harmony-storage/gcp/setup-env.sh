#!/bin/bash

# setup-env.sh - Helper script to set up environment variables for Filestore scripts
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

printf "%b\n" "${GREEN}🔧 GCP Filestore Scripts Environment Setup${NC}"
echo "==========================================="

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
    
    if ! command -v gcloud &> /dev/null; then
        missing_commands+=("gcloud")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_commands+=("kubectl")
    fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        printf "%b\n" "${RED}❌ Missing required commands: ${missing_commands[*]}${NC}"
        echo ""
        echo "Installation instructions:"
        if [[ "$platform_detected" == "Linux"* ]]; then
            echo "  Google Cloud SDK: https://cloud.google.com/sdk/docs/install#linux"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        elif [[ "$platform_detected" == "macOS"* ]]; then
            echo "  Google Cloud SDK: brew install google-cloud-sdk"
            echo "  kubectl: brew install kubectl"
        elif [[ "$platform_detected" == *"Windows"* ]]; then
            echo "  Google Cloud SDK: https://cloud.google.com/sdk/docs/install#windows"
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
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
    printf "%b\n" "${RED}❌ You are not logged into Google Cloud CLI. Please run 'gcloud auth login' first.${NC}"
    exit 1
fi

# Check current project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ -z "$CURRENT_PROJECT" ]; then
    printf "%b\n" "${YELLOW}⚠️  No default Google Cloud project is currently set.${NC}"
    echo ""
    echo "Available projects:"
    gcloud projects list --format="value(projectId)" 2>/dev/null | while read -r project; do
        echo "  - $project"
    done
    echo ""
    read -p "Enter your project ID: " CURRENT_PROJECT
    if [ -z "$CURRENT_PROJECT" ]; then
        printf "%b\n" "${RED}❌ Project ID cannot be empty.${NC}"
        exit 1
    fi
    gcloud config set project "$CURRENT_PROJECT" &>/dev/null
fi

echo ""
echo "Let's configure your environment variables for the Filestore scripts."
echo ""

# Get available clusters
echo "📋 Finding your GKE clusters..."
AVAILABLE_CLUSTERS=$(gcloud container clusters list --format="value(name)" 2>/dev/null)

if [ -z "$AVAILABLE_CLUSTERS" ]; then
    printf "%b\n" "${RED}❌ No GKE clusters found or unable to list clusters.${NC}"
    echo "Please check your Google Cloud CLI configuration and permissions."
    exit 1
fi

echo "Available GKE clusters:"
for cluster in $AVAILABLE_CLUSTERS; do
    echo "  - $cluster"
done

echo ""
read -p "Enter your GKE cluster name: " CLUSTER_NAME

if [ -z "$CLUSTER_NAME" ]; then
    printf "%b\n" "${RED}❌ Cluster name cannot be empty.${NC}"
    exit 1
fi

# Validate cluster exists
echo "📋 Validating cluster '$CLUSTER_NAME'..."
CLUSTER_INFO=$(gcloud container clusters list --filter="name=$CLUSTER_NAME" --format="value(name,location)" 2>/dev/null)

if [ -z "$CLUSTER_INFO" ]; then
    printf "%b\n" "${RED}❌ Cluster '$CLUSTER_NAME' not found in project '$CURRENT_PROJECT'.${NC}"
    echo "Please check the cluster name and try again."
    exit 1
fi

CLUSTER_LOCATION=$(echo "$CLUSTER_INFO" | awk '{print $2}')

# Derive CLUSTER_ZONE for Filestore operations
if [[ "$CLUSTER_LOCATION" =~ -[a-z]$ ]]; then
    CLUSTER_ZONE="$CLUSTER_LOCATION"
else
    REGION="$CLUSTER_LOCATION"
    ZONES=$(gcloud compute zones list --filter="region:$REGION" --format="value(name)" 2>/dev/null)
    if [ -n "$ZONES" ]; then
        CLUSTER_ZONE=$(echo "$ZONES" | head -1)
    else
        CLUSTER_ZONE="${CLUSTER_LOCATION}-a"
    fi
fi

PROJECT_ID="$CURRENT_PROJECT"

printf "%b\n" "${GREEN}✅ Found cluster '$CLUSTER_NAME' in location '$CLUSTER_LOCATION'${NC}"

# Set environment variables
export CLUSTER_NAME="$CLUSTER_NAME"
export CLUSTER_LOCATION="$CLUSTER_LOCATION"
export CLUSTER_ZONE="$CLUSTER_ZONE"
export PROJECT_ID="$PROJECT_ID"

echo ""
printf "%b\n" "${GREEN}🎉 Environment variables configured successfully!${NC}"
echo ""
echo "Current configuration:"
echo "  CLUSTER_NAME: $CLUSTER_NAME"
echo "  CLUSTER_LOCATION: $CLUSTER_LOCATION"
echo "  CLUSTER_ZONE: $CLUSTER_ZONE"
echo "  PROJECT_ID: $PROJECT_ID"
echo ""

# Configure kubectl context
echo "Configuring kubectl context..."
if gcloud container clusters get-credentials "$CLUSTER_NAME" --location="$CLUSTER_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
    printf "%b\n" "${GREEN}✅ kubectl configured for cluster${NC}"
else
    printf "%b\n" "${YELLOW}⚠️  Warning: Could not configure kubectl context${NC}"
fi
echo ""

# If script was executed (not sourced), create an export file
if [ "$CREATE_EXPORT_FILE" = true ]; then
    EXPORT_FILE="./gke-env-vars.sh"
    cat > "$EXPORT_FILE" << ENVEOF
#!/bin/bash
# Auto-generated environment variables for Filestore scripts
export CLUSTER_NAME="$CLUSTER_NAME"
export CLUSTER_LOCATION="$CLUSTER_LOCATION"
export CLUSTER_ZONE="$CLUSTER_ZONE"
export PROJECT_ID="$PROJECT_ID"
ENVEOF
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
        echo "  export CLUSTER_LOCATION=\"$CLUSTER_LOCATION\""
        echo "  export CLUSTER_ZONE=\"$CLUSTER_ZONE\""
        echo "  export PROJECT_ID=\"$PROJECT_ID\""
        exit 0
    fi

    # Check if variables already exist in profile
    if grep -q "export CLUSTER_NAME=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing CLUSTER_NAME in $SHELL_PROFILE"
        sed -i.bak "s/export CLUSTER_NAME=.*/export CLUSTER_NAME=\"$CLUSTER_NAME\"/" "$SHELL_PROFILE"
    else
        echo "export CLUSTER_NAME=\"$CLUSTER_NAME\"" >> "$SHELL_PROFILE"
    fi

    if grep -q "export CLUSTER_LOCATION=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing CLUSTER_LOCATION in $SHELL_PROFILE"
        sed -i.bak "s/export CLUSTER_LOCATION=.*/export CLUSTER_LOCATION=\"$CLUSTER_LOCATION\"/" "$SHELL_PROFILE"
    else
        echo "export CLUSTER_LOCATION=\"$CLUSTER_LOCATION\"" >> "$SHELL_PROFILE"
    fi

    if grep -q "export CLUSTER_ZONE=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing CLUSTER_ZONE in $SHELL_PROFILE"
        sed -i.bak "s/export CLUSTER_ZONE=.*/export CLUSTER_ZONE=\"$CLUSTER_ZONE\"/" "$SHELL_PROFILE"
    else
        echo "export CLUSTER_ZONE=\"$CLUSTER_ZONE\"" >> "$SHELL_PROFILE"
    fi

    if grep -q "export PROJECT_ID=" "$SHELL_PROFILE" 2>/dev/null; then
        echo "Updating existing PROJECT_ID in $SHELL_PROFILE"
        sed -i.bak "s/export PROJECT_ID=.*/export PROJECT_ID=\"$PROJECT_ID\"/" "$SHELL_PROFILE"
    else
        echo "export PROJECT_ID=\"$PROJECT_ID\"" >> "$SHELL_PROFILE"
    fi

    echo "✅ Environment variables added to $SHELL_PROFILE"
    echo "They will be available in new terminal sessions."
fi

echo ""
printf "%b\n" "${GREEN}🚀 You're ready to run the Filestore scripts!${NC}"
echo ""
echo "Next steps:"
echo "1. Install NFS CSI driver:       ./install-nfs-csi-driver.sh"
echo "2. Create Filestore instance:    ./create-filestore.sh"
echo "3. When done, cleanup:           ./cleanup-filestore.sh"
echo ""

if [ "$CREATE_EXPORT_FILE" = true ]; then
    echo "Remember: Since this script was executed (not sourced), run this first:"
    echo "  source ./gke-env-vars.sh"
    echo ""
else
    printf "%b\n" "${GREEN}✅ Environment variables are available in this terminal session.${NC}"
fi

if [[ ! $REPLY =~ ^[Yy]$ ]] && [ "$CREATE_EXPORT_FILE" = true ]; then
    echo "If you open a new terminal, you'll need to run:"
    echo "  source ./setup-env.sh"
    echo "or"
    echo "  source ./gke-env-vars.sh"
    echo "or manually set the variables with:"
    echo "  export CLUSTER_NAME=\"$CLUSTER_NAME\""
    echo "  export CLUSTER_LOCATION=\"$CLUSTER_LOCATION\""
    echo "  export CLUSTER_ZONE=\"$CLUSTER_ZONE\""
    echo "  export PROJECT_ID=\"$PROJECT_ID\""
fi
