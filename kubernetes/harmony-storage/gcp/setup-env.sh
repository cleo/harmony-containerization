#!/usr/bin/env bash

# setup-env.sh - Configure environment variables for GKE cluster and Google Cloud Filestore operations
#
# This script must be SOURCED, not executed:
#   source ./setup-env.sh
#
# Purpose:
#   - Lists available GKE clusters in your Google Cloud project
#   - Prompts user to select a cluster
#   - Auto-detects cluster region/zone
#   - Sets environment variables for use by other scripts
#   - Optionally makes variables persistent in shell profile
#
# Environment Variables Set:
#   CLUSTER_NAME     - Name of the selected GKE cluster
#   CLUSTER_LOCATION - Region or zone of the cluster
#   CLUSTER_ZONE     - Specific zone for Filestore (derived from CLUSTER_LOCATION)
#   PROJECT_ID       - Google Cloud project ID
#
# Platform Support:
#   - Linux (Ubuntu, RHEL, CentOS, etc.)
#   - macOS (Intel and Apple Silicon)
#   - Windows (Git Bash, WSL, Cygwin)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect shell configuration file
detect_shell_profile() {
    if [ -n "$BASH_VERSION" ]; then
        if [ -f "$HOME/.bashrc" ]; then
            echo "$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            echo "$HOME/.bash_profile"
        fi
    elif [ -n "$ZSH_VERSION" ]; then
        echo "$HOME/.zshrc"
    else
        echo "$HOME/.profile"
    fi
}

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
        echo "❌ Missing required commands: ${missing_commands[*]}"
        echo ""
        echo "Installation instructions:"
        if [[ "$platform_detected" == "Linux"* ]]; then
            echo "  Google Cloud SDK: https://cloud.google.com/sdk/docs/install#linux"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        elif [[ "$platform_detected" == "macOS"* ]]; then
            echo "  Google Cloud SDK: brew install google-cloud-sdk"
            echo "  kubectl: brew install kubectl"
        elif [[ "$platform_detected" == "Windows"* ]]; then
            echo "  Google Cloud SDK: https://cloud.google.com/sdk/docs/install#windows"
            echo "  kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
        fi
        return 1
    fi

    return 0
}

printf "%b\n" "${GREEN}=== GKE Cluster Environment Setup ===${NC}\n"

# Run platform compatibility check
check_platform_compatibility
if [ $? -ne 0 ]; then
    return 1
fi
echo ""

# Check if gcloud is installed (redundant but kept for clarity)
if ! command -v gcloud &> /dev/null; then
    printf "%b\n" "${RED}ERROR: gcloud CLI is not installed or not in PATH${NC}"
    echo "Please install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
    return 1
fi

# Get current project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ -z "$CURRENT_PROJECT" ]; then
    printf "%b\n" "${YELLOW}No default Google Cloud project is currently set${NC}"
    echo ""

    # List available projects
    echo "Fetching available projects..."
    PROJECTS=$(gcloud projects list --format="table[no-heading](projectId,name)" 2>/dev/null)

    if [ -z "$PROJECTS" ]; then
        printf "%b\n" "${RED}ERROR: No Google Cloud projects found${NC}"
        echo "Please create a project first or check your authentication"
        echo "Run: gcloud auth login"
        return 1
    fi

    # Display projects
    printf "%b\n" "${GREEN}Available Projects:${NC}"
    echo "$PROJECTS" | nl -w2 -s'. '
    echo ""

    # Prompt for project selection
    while true; do
        read -p "Select project number: " PROJECT_SELECTION

        # Validate input is a number
        if ! [[ "$PROJECT_SELECTION" =~ ^[0-9]+$ ]]; then
            printf "%b\n" "${RED}Invalid input. Please enter a number.${NC}"
            continue
        fi

        # Get project info
        PROJECT_INFO=$(echo "$PROJECTS" | sed -n "${PROJECT_SELECTION}p")

        if [ -z "$PROJECT_INFO" ]; then
            printf "%b\n" "${RED}Invalid selection. Please try again.${NC}"
            continue
        fi

        # Extract project ID
        CURRENT_PROJECT=$(echo "$PROJECT_INFO" | awk '{print $1}')

        # Set the project
        echo "Setting default project to: $CURRENT_PROJECT"
        if gcloud config set project "$CURRENT_PROJECT" &>/dev/null; then
            printf "%b\n" "${GREEN}✓ Project set successfully${NC}"
        else
            printf "%b\n" "${RED}ERROR: Failed to set project${NC}"
            return 1
        fi

        break
    done
    echo ""
fi

printf "%b\n" "${GREEN}Current Project:${NC} $CURRENT_PROJECT"
echo ""

# Get list of GKE clusters
echo "Fetching GKE clusters..."
CLUSTERS=$(gcloud container clusters list --format="table[no-heading](name,location)" 2>/dev/null)

if [ -z "$CLUSTERS" ]; then
    printf "%b\n" "${RED}ERROR: No GKE clusters found in project $CURRENT_PROJECT${NC}"
    echo "Please create a GKE cluster first or switch to the correct project"
    return 1
fi

# Display clusters
printf "%b\n" "${GREEN}Available GKE Clusters:${NC}"
echo "$CLUSTERS" | nl -w2 -s'. '
echo ""

# Prompt for cluster selection
while true; do
    read -p "Select cluster number: " SELECTION

    # Validate input is a number
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
        printf "%b\n" "${RED}Invalid input. Please enter a number.${NC}"
        continue
    fi

    # Get cluster info
    CLUSTER_INFO=$(echo "$CLUSTERS" | sed -n "${SELECTION}p")

    if [ -z "$CLUSTER_INFO" ]; then
        printf "%b\n" "${RED}Invalid selection. Please try again.${NC}"
        continue
    fi

    # Extract cluster name and location
    export CLUSTER_NAME=$(echo "$CLUSTER_INFO" | awk '{print $1}')
    export CLUSTER_LOCATION=$(echo "$CLUSTER_INFO" | awk '{print $2}')
    export PROJECT_ID="$CURRENT_PROJECT"

    # Derive CLUSTER_ZONE for Filestore operations
    if [[ "$CLUSTER_LOCATION" =~ -[a-z]$ ]]; then
        # CLUSTER_LOCATION is already a zone (e.g., us-central1-a)
        export CLUSTER_ZONE="$CLUSTER_LOCATION"
    else
        # CLUSTER_LOCATION is a region (e.g., us-central1), select first available zone
        REGION="$CLUSTER_LOCATION"
        ZONES=$(gcloud compute zones list --filter="region:$REGION" --format="value(name)" 2>/dev/null)
        if [ -n "$ZONES" ]; then
            export CLUSTER_ZONE=$(echo "$ZONES" | head -1)
        else
            export CLUSTER_ZONE="${CLUSTER_LOCATION}-c"  # Fallback to -c zone
        fi
    fi

    break
done

echo ""
printf "%b\n" "${GREEN}Environment Variables Set:${NC}"
echo "  CLUSTER_NAME     = $CLUSTER_NAME"
echo "  CLUSTER_LOCATION = $CLUSTER_LOCATION"
echo "  CLUSTER_ZONE     = $CLUSTER_ZONE"
echo "  PROJECT_ID       = $PROJECT_ID"
echo ""

# Configure kubectl context
echo "Configuring kubectl context..."
if gcloud container clusters get-credentials "$CLUSTER_NAME" --location="$CLUSTER_LOCATION" --project="$PROJECT_ID" &>/dev/null; then
    printf "%b\n" "${GREEN}✓ kubectl configured for cluster${NC}"
else
    printf "%b\n" "${YELLOW}⚠ Warning: Could not configure kubectl context${NC}"
fi

# Ask if user wants to make variables persistent
echo ""
read -p "Make these variables persistent in your shell profile? (y/n): " MAKE_PERSISTENT

if [[ "$MAKE_PERSISTENT" =~ ^[Yy]$ ]]; then
    PROFILE_FILE=$(detect_shell_profile)

    if [ -z "$PROFILE_FILE" ]; then
        printf "%b\n" "${YELLOW}Could not detect shell profile file${NC}"
        echo "Manually add these lines to your shell profile:"
    else
        # Remove old entries if they exist
        sed -i.bak '/^export CLUSTER_NAME=/d' "$PROFILE_FILE" 2>/dev/null || true
        sed -i.bak '/^export CLUSTER_LOCATION=/d' "$PROFILE_FILE" 2>/dev/null || true
        sed -i.bak '/^export CLUSTER_ZONE=/d' "$PROFILE_FILE" 2>/dev/null || true
        sed -i.bak '/^export PROJECT_ID=/d' "$PROFILE_FILE" 2>/dev/null || true

        # Add new entries
        echo "export CLUSTER_NAME=\"$CLUSTER_NAME\"" >> "$PROFILE_FILE"
        echo "export CLUSTER_LOCATION=\"$CLUSTER_LOCATION\"" >> "$PROFILE_FILE"
        echo "export CLUSTER_ZONE=\"$CLUSTER_ZONE\"" >> "$PROFILE_FILE"
        echo "export PROJECT_ID=\"$PROJECT_ID\"" >> "$PROFILE_FILE"

        printf "%b\n" "${GREEN}✓ Variables added to $PROFILE_FILE${NC}"
        echo "Run 'source $PROFILE_FILE' to reload in current session"
    fi

    echo ""
    echo "export CLUSTER_NAME=\"$CLUSTER_NAME\""
    echo "export CLUSTER_LOCATION=\"$CLUSTER_LOCATION\""
    echo "export CLUSTER_ZONE=\"$CLUSTER_ZONE\""
    echo "export PROJECT_ID=\"$PROJECT_ID\""
else
    printf "%b\n" "${YELLOW}Note: Variables are only set for this session${NC}"
    echo "To set them again later, run: source ./setup-env.sh"
fi

echo ""
printf "%b\n" "${GREEN}=== Setup Complete ===${NC}"
