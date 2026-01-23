#!/bin/bash

# validate-prerequisites.sh - Validate prerequisites before Harmony deployment
# Checks required tools, cluster access, secrets, and configurations

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Default values
NAMESPACE="harmony"
PLATFORM=""
CHECK_STORAGE=false

# Print functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Harmony Deployment Prerequisites Validation${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_check() {
    local status=$1
    local message=$2
    
    case $status in
        "PASS")
            echo -e "${GREEN}✓ PASS${NC} - $message"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            ;;
        "FAIL")
            echo -e "${RED}✗ FAIL${NC} - $message"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠ WARN${NC} - $message"
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
            ;;
    esac
}

print_section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "────────────────────────────────────────────────────────"
}

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate prerequisites for Harmony deployment on Kubernetes.

OPTIONS:
    --platform PLATFORM     Cloud platform: aws, azure, or gcp
    --namespace NAMESPACE   Kubernetes namespace (default: harmony)
    --check-storage        Also validate storage prerequisites
    --help                 Show this help message

EXAMPLES:
    # Basic validation
    $0

    # Validate for AWS with storage
    $0 --platform aws --check-storage

    # Validate custom namespace
    $0 --namespace harmony-prod --platform azure

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --check-storage)
            CHECK_STORAGE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Validate platform if provided
if [[ -n "$PLATFORM" ]] && [[ ! "$PLATFORM" =~ ^(aws|azure|gcp)$ ]]; then
    echo -e "${RED}Error: Invalid platform '$PLATFORM'. Must be aws, azure, or gcp${NC}"
    exit 2
fi

print_header
echo "Namespace: $NAMESPACE"
[[ -n "$PLATFORM" ]] && echo "Platform: $PLATFORM"
echo "Check Storage: $CHECK_STORAGE"
echo ""

# ============================================================================
# Check Required CLI Tools
# ============================================================================
print_section "Required CLI Tools"

# kubectl
if command -v kubectl &> /dev/null; then
    VERSION=$(kubectl version --client --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    print_check "PASS" "kubectl is installed ($VERSION)"
else
    print_check "FAIL" "kubectl is not installed"
fi

# helm
if command -v helm &> /dev/null; then
    VERSION=$(helm version --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    print_check "PASS" "helm is installed ($VERSION)"
else
    print_check "FAIL" "helm is not installed"
fi

# Platform-specific CLI tools
if [[ "$PLATFORM" == "aws" ]]; then
    if command -v aws &> /dev/null; then
        VERSION=$(aws --version 2>&1 | grep -oP 'aws-cli/\d+\.\d+\.\d+' || echo "unknown")
        print_check "PASS" "aws CLI is installed ($VERSION)"
    else
        print_check "FAIL" "aws CLI is not installed"
    fi
elif [[ "$PLATFORM" == "azure" ]]; then
    if command -v az &> /dev/null; then
        VERSION=$(az version 2>&1 | grep -oP '"azure-cli": "\d+\.\d+\.\d+"' | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        print_check "PASS" "az CLI is installed ($VERSION)"
    else
        print_check "FAIL" "az CLI is not installed"
    fi
    
    if command -v jq &> /dev/null; then
        print_check "PASS" "jq is installed (required for Azure)"
    else
        print_check "WARN" "jq is not installed (recommended for Azure)"
    fi
elif [[ "$PLATFORM" == "gcp" ]]; then
    if command -v gcloud &> /dev/null; then
        VERSION=$(gcloud version 2>&1 | grep "Google Cloud SDK" | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        print_check "PASS" "gcloud CLI is installed ($VERSION)"
    else
        print_check "FAIL" "gcloud CLI is not installed"
    fi
fi

# ============================================================================
# Check Kubernetes Cluster Access
# ============================================================================
print_section "Kubernetes Cluster Access"

if kubectl cluster-info &> /dev/null; then
    CLUSTER=$(kubectl config current-context 2>/dev/null || echo "unknown")
    print_check "PASS" "Connected to Kubernetes cluster ($CLUSTER)"
    
    # Check cluster version
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | grep -oP 'v\d+\.\d+' || echo "unknown")
    if [[ "$K8S_VERSION" != "unknown" ]]; then
        print_check "PASS" "Kubernetes server version: $K8S_VERSION"
    fi
else
    print_check "FAIL" "Cannot connect to Kubernetes cluster"
fi

# Check namespace
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_check "PASS" "Namespace '$NAMESPACE' exists"
else
    print_check "WARN" "Namespace '$NAMESPACE' does not exist (will need to be created)"
fi

# Check cluster resources
if kubectl top nodes &> /dev/null 2>&1; then
    print_check "PASS" "Metrics server is available"
else
    print_check "WARN" "Metrics server not available (resource monitoring will be limited)"
fi

# ============================================================================
# Check Required Secrets
# ============================================================================
print_section "Required Secrets"

REQUIRED_SECRETS=(
    "cleo-license"
    "cleo-license-verification-code"
    "cleo-default-admin-password"
    "cleo-system-settings"
    "cleo-config-repo"
    "cleo-runtime-repo"
)

OPTIONAL_SECRETS=(
    "cleo-log-system"
)

for secret in "${REQUIRED_SECRETS[@]}"; do
    if kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
        print_check "PASS" "Required secret '$secret' exists"
    else
        print_check "FAIL" "Required secret '$secret' is missing"
    fi
done

for secret in "${OPTIONAL_SECRETS[@]}"; do
    if kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
        print_check "PASS" "Optional secret '$secret' exists"
    else
        print_check "WARN" "Optional secret '$secret' is missing (will use defaults)"
    fi
done

# ============================================================================
# Check Storage Prerequisites (if requested)
# ============================================================================
if [[ "$CHECK_STORAGE" == true ]]; then
    print_section "Storage Prerequisites"
    
    # Check for existing PVC
    if kubectl get pvc harmony-pvc -n "$NAMESPACE" &> /dev/null; then
        STATUS=$(kubectl get pvc harmony-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        if [[ "$STATUS" == "Bound" ]]; then
            print_check "PASS" "PVC 'harmony-pvc' exists and is bound"
        else
            print_check "WARN" "PVC 'harmony-pvc' exists but status is: $STATUS"
        fi
    else
        print_check "WARN" "PVC 'harmony-pvc' does not exist (will be created by harmony-storage chart)"
    fi
    
    # Platform-specific storage checks
    if [[ "$PLATFORM" == "aws" ]]; then
        if kubectl get csidriver efs.csi.aws.com &> /dev/null; then
            print_check "PASS" "AWS EFS CSI driver is installed"
        else
            print_check "FAIL" "AWS EFS CSI driver is not installed"
        fi
    elif [[ "$PLATFORM" == "azure" ]]; then
        if kubectl get csidriver file.csi.azure.com &> /dev/null; then
            print_check "PASS" "Azure Files CSI driver is installed"
        else
            print_check "FAIL" "Azure Files CSI driver is not installed"
        fi
    elif [[ "$PLATFORM" == "gcp" ]]; then
        if kubectl get csidriver nfs.csi.k8s.io &> /dev/null; then
            print_check "PASS" "NFS CSI driver is installed"
        else
            print_check "FAIL" "NFS CSI driver is not installed"
        fi
    fi
fi

# ============================================================================
# Check Helm Repository
# ============================================================================
print_section "Helm Charts"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="$(dirname "$SCRIPT_DIR")"

for chart in "harmony-init" "harmony-run" "harmony-storage"; do
    if [[ -f "$CHARTS_DIR/$chart/Chart.yaml" ]]; then
        print_check "PASS" "Chart '$chart' found"
    else
        print_check "FAIL" "Chart '$chart' not found"
    fi
done

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Validation Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "Checks passed:   ${GREEN}${CHECKS_PASSED}${NC}"
echo -e "Checks failed:   ${RED}${CHECKS_FAILED}${NC}"
echo -e "Warnings:        ${YELLOW}${CHECKS_WARNING}${NC}"
echo ""

if [[ $CHECKS_FAILED -gt 0 ]]; then
    echo -e "${RED}✗ Validation failed. Please fix the issues above before deployment.${NC}"
    exit 1
elif [[ $CHECKS_WARNING -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Validation passed with warnings. Review warnings before deployment.${NC}"
    exit 0
else
    echo -e "${GREEN}✓ All validation checks passed! Ready for deployment.${NC}"
    exit 0
fi
