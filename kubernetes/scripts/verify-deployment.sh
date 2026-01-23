#!/bin/bash

# verify-deployment.sh - Verify successful Harmony deployment
# Checks that all components are deployed and running correctly

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
TIMEOUT=300

# Print functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Harmony Deployment Verification${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
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

Verify successful Harmony deployment on Kubernetes.

OPTIONS:
    --namespace NAMESPACE   Kubernetes namespace (default: harmony)
    --timeout SECONDS      Timeout for waiting on resources (default: 300)
    --help                 Show this help message

EXAMPLES:
    # Basic verification
    $0

    # Verify custom namespace
    $0 --namespace harmony-prod

    # Verify with extended timeout
    $0 --timeout 600

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
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

print_header
echo "Namespace: $NAMESPACE"
echo "Timeout: ${TIMEOUT}s"
echo ""

# ============================================================================
# Check Helm Releases
# ============================================================================
print_section "Helm Releases"

for release in "harmony-storage" "harmony-init" "harmony-runtime"; do
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^$release"; then
        STATUS=$(helm list -n "$NAMESPACE" -o json 2>/dev/null | jq -r ".[] | select(.name==\"$release\") | .status" || echo "unknown")
        if [[ "$STATUS" == "deployed" ]]; then
            print_check "PASS" "Helm release '$release' is deployed"
        else
            print_check "WARN" "Helm release '$release' status: $STATUS"
        fi
    else
        if [[ "$release" == "harmony-storage" ]]; then
            echo -e "  ${BLUE} INFO${NC} - Helm release '$release' not installed (optional)"
        else
            print_check "FAIL" "Helm release '$release' not found"
        fi
    fi
done

# ============================================================================
# Check Harmony Init Job
# ============================================================================
print_section "Initialization Job"

if kubectl get job harmony-init -n "$NAMESPACE" &> /dev/null; then
    print_check "PASS" "Job 'harmony-init' exists"
    
    # Check job status
    SUCCEEDED=$(kubectl get job harmony-init -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    FAILED=$(kubectl get job harmony-init -n "$NAMESPACE" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
    
    if [[ "$SUCCEEDED" -gt 0 ]]; then
        print_check "PASS" "Job 'harmony-init' completed successfully"
    elif [[ "$FAILED" -gt 0 ]]; then
        print_check "FAIL" "Job 'harmony-init' failed"
    else
        print_check "WARN" "Job 'harmony-init' is still running"
    fi
else
    print_check "FAIL" "Job 'harmony-init' not found"
fi

# ============================================================================
# Check StatefulSet
# ============================================================================
print_section "Harmony Runtime StatefulSet"

if kubectl get statefulset harmony -n "$NAMESPACE" &> /dev/null; then
    print_check "PASS" "StatefulSet 'harmony' exists"
    
    REPLICAS=$(kubectl get statefulset harmony -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get statefulset harmony -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$READY" -eq "$REPLICAS" ]]; then
        print_check "PASS" "StatefulSet 'harmony' has $READY/$REPLICAS replicas ready"
    else
        print_check "WARN" "StatefulSet 'harmony' has $READY/$REPLICAS replicas ready"
    fi
else
    print_check "FAIL" "StatefulSet 'harmony' not found"
fi

# ============================================================================
# Check Pods
# ============================================================================
print_section "Pod Status"

if kubectl get pods -n "$NAMESPACE" -l app=harmony &> /dev/null 2>&1; then
    PODS=$(kubectl get pods -n "$NAMESPACE" -l app=harmony -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -n "$PODS" ]]; then
        for pod in $PODS; do
            STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
            
            if [[ "$STATUS" == "Running" ]] && [[ "$READY" == "True" ]]; then
                print_check "PASS" "Pod '$pod' is running and ready"
            elif [[ "$STATUS" == "Running" ]]; then
                print_check "WARN" "Pod '$pod' is running but not ready"
            else
                print_check "FAIL" "Pod '$pod' status: $STATUS"
            fi
            
            # Check for restarts
            RESTARTS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
            if [[ "$RESTARTS" -gt 0 ]]; then
                print_check "WARN" "Pod '$pod' has restarted $RESTARTS times"
            fi
        done
    else
        print_check "FAIL" "No harmony pods found"
    fi
else
    print_check "FAIL" "Cannot list harmony pods"
fi

# ============================================================================
# Check Services
# ============================================================================
print_section "Services"

# Headless service
if kubectl get service harmony-service -n "$NAMESPACE" &> /dev/null; then
    print_check "PASS" "Headless service 'harmony-service' exists"
else
    print_check "WARN" "Headless service 'harmony-service' not found"
fi

# Load balancer service
if kubectl get service harmony -n "$NAMESPACE" &> /dev/null; then
    print_check "PASS" "Load balancer service 'harmony' exists"
    
    # Check if load balancer has external IP/hostname
    EXTERNAL=$(kubectl get service harmony -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0]}' 2>/dev/null || echo "")
    if [[ -n "$EXTERNAL" ]]; then
        HOSTNAME=$(echo "$EXTERNAL" | jq -r '.hostname // .ip // "pending"' 2>/dev/null || echo "pending")
        if [[ "$HOSTNAME" != "pending" ]] && [[ "$HOSTNAME" != "" ]]; then
            print_check "PASS" "Load balancer has external endpoint: $HOSTNAME"
        else
            print_check "WARN" "Load balancer external endpoint is pending"
        fi
    else
        print_check "WARN" "Load balancer external endpoint is pending"
    fi
else
    print_check "FAIL" "Load balancer service 'harmony' not found"
fi

# ============================================================================
# Check Storage (if harmony-storage is deployed)
# ============================================================================
if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^harmony-storage"; then
    print_section "Storage"
    
    # Check PVC
    if kubectl get pvc harmony-pvc -n "$NAMESPACE" &> /dev/null; then
        STATUS=$(kubectl get pvc harmony-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        if [[ "$STATUS" == "Bound" ]]; then
            CAPACITY=$(kubectl get pvc harmony-pvc -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')
            print_check "PASS" "PVC 'harmony-pvc' is bound ($CAPACITY)"
        else
            print_check "FAIL" "PVC 'harmony-pvc' status: $STATUS"
        fi
    else
        print_check "FAIL" "PVC 'harmony-pvc' not found"
    fi
    
    # Check StorageClass
    if kubectl get storageclass harmony-sc &> /dev/null; then
        print_check "PASS" "StorageClass 'harmony-sc' exists"
    else
        print_check "FAIL" "StorageClass 'harmony-sc' not found"
    fi
fi

# ============================================================================
# Check Events for Errors
# ============================================================================
print_section "Recent Events"

ERROR_EVENTS=$(kubectl get events -n "$NAMESPACE" --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -5 || echo "")

if [[ -n "$ERROR_EVENTS" ]]; then
    WARNING_COUNT=$(echo "$ERROR_EVENTS" | grep -c "Warning" || echo "0")
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
        print_check "WARN" "Found $WARNING_COUNT warning events in the last few minutes"
        echo "$ERROR_EVENTS" | head -3
    else
        print_check "PASS" "No recent warning events"
    fi
else
    print_check "PASS" "No recent warning events"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Verification Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "Checks passed:   ${GREEN}${CHECKS_PASSED}${NC}"
echo -e "Checks failed:   ${RED}${CHECKS_FAILED}${NC}"
echo -e "Warnings:        ${YELLOW}${CHECKS_WARNING}${NC}"
echo ""

if [[ $CHECKS_FAILED -gt 0 ]]; then
    echo -e "${RED}✗ Verification failed. Please investigate the issues above.${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check pod logs: kubectl logs -n $NAMESPACE <pod-name>"
    echo "2. Describe failing resources: kubectl describe pod -n $NAMESPACE <pod-name>"
    echo "3. Check events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    exit 1
elif [[ $CHECKS_WARNING -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Verification completed with warnings. Review warnings above.${NC}"
    exit 0
else
    echo -e "${GREEN}✓ Deployment verification successful!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Access admin console: kubectl port-forward svc/harmony 5080:5080 -n $NAMESPACE"
    echo "2. Monitor health: ./health-check.sh --namespace $NAMESPACE"
    exit 0
fi
