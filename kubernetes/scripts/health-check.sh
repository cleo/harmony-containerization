#!/bin/bash

# health-check.sh - Monitor health of Harmony deployment
# Performs health checks and reports on system status

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="harmony"
INTERVAL=60
CONTINUOUS=false

# Print functions
print_header() {
    clear
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Harmony Health Check${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "Namespace: ${CYAN}$NAMESPACE${NC}"
    echo -e "Time: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "────────────────────────────────────────────────────────"
}

print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "HEALTHY")
            echo -e "${GREEN}✓ HEALTHY${NC} - $message"
            ;;
        "DEGRADED")
            echo -e "${YELLOW}⚠ DEGRADED${NC} - $message"
            ;;
        "UNHEALTHY")
            echo -e "${RED}✗ UNHEALTHY${NC} - $message"
            ;;
        "INFO")
            echo -e "${CYAN}ℹ INFO${NC} - $message"
            ;;
    esac
}

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Monitor health of Harmony deployment on Kubernetes.

OPTIONS:
    --namespace NAMESPACE   Kubernetes namespace (default: harmony)
    --interval SECONDS     Check interval for continuous mode (default: 60)
    --continuous           Run continuously (default: single check)
    --help                 Show this help message

EXAMPLES:
    # Single health check
    $0

    # Continuous monitoring every 60 seconds
    $0 --continuous

    # Monitor custom namespace every 30 seconds
    $0 --namespace harmony-prod --continuous --interval 30

Press Ctrl+C to stop continuous monitoring.

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
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --continuous)
            CONTINUOUS=true
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

# Health check function
perform_health_check() {
    print_header
    
    # Initialize variables
    PODS=""
    TOTAL_PODS=0
    READY_PODS=0
    RUNNING_PODS=0
    
    # ============================================================================
    # Pod Health
    # ============================================================================
    print_section "Pod Health"
    
    if kubectl get pods -n "$NAMESPACE" -l app=harmony &> /dev/null 2>&1; then
        PODS=$(kubectl get pods -n "$NAMESPACE" -l app=harmony -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$PODS" ]]; then
            TOTAL_PODS=$(echo "$PODS" | wc -w)
            RUNNING_PODS=0
            READY_PODS=0
            
            for pod in $PODS; do
                STATUS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                
                if [[ "$STATUS" == "Running" ]]; then
                    ((RUNNING_PODS++))
                fi
                
                if [[ "$READY" == "True" ]]; then
                    ((READY_PODS++))
                fi
            done
            
            if [[ "$READY_PODS" -eq "$TOTAL_PODS" ]]; then
                print_status "HEALTHY" "$READY_PODS/$TOTAL_PODS pods ready and running"
            elif [[ "$READY_PODS" -gt 0 ]]; then
                print_status "DEGRADED" "$READY_PODS/$TOTAL_PODS pods ready"
            else
                print_status "UNHEALTHY" "No pods ready ($RUNNING_PODS/$TOTAL_PODS running)"
            fi
        else
            print_status "UNHEALTHY" "No harmony pods found"
        fi
    else
        print_status "UNHEALTHY" "Cannot access harmony pods"
    fi
    
    # ============================================================================
    # Resource Utilization
    # ============================================================================
    print_section "Resource Utilization"
    
    if kubectl top pods -n "$NAMESPACE" -l app=harmony &> /dev/null 2>&1; then
        RESOURCE_DATA=$(kubectl top pods -n "$NAMESPACE" -l app=harmony 2>/dev/null || echo "")
        
        if [[ -n "$RESOURCE_DATA" ]]; then
            print_status "INFO" "Current resource usage:"
            echo "$RESOURCE_DATA" | tail -n +2 | while read -r line; do
                POD_NAME=$(echo "$line" | awk '{print $1}')
                CPU=$(echo "$line" | awk '{print $2}')
                MEMORY=$(echo "$line" | awk '{print $3}')
                echo "  $POD_NAME: CPU=$CPU, Memory=$MEMORY"
            done
        else
            print_status "INFO" "Resource metrics not available"
        fi
    else
        print_status "INFO" "Metrics server not available or no pods running"
    fi
    
    # ============================================================================
    # Pod Restarts
    # ============================================================================
    print_section "Pod Restart Count"
    
    if [[ -n "$PODS" ]]; then
        HAS_RESTARTS=false
        for pod in $PODS; do
            RESTARTS=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
            if [[ "$RESTARTS" -gt 0 ]]; then
                print_status "DEGRADED" "Pod '$pod' has restarted $RESTARTS times"
                HAS_RESTARTS=true
            fi
        done
        
        if [[ "$HAS_RESTARTS" == false ]]; then
            print_status "HEALTHY" "No pod restarts detected"
        fi
    fi
    
    # ============================================================================
    # Service Status
    # ============================================================================
    print_section "Services"
    
    # Load balancer
    if kubectl get service harmony -n "$NAMESPACE" &> /dev/null 2>&1; then
        EXTERNAL=$(kubectl get service harmony -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0]}' 2>/dev/null || echo "")
        if [[ -n "$EXTERNAL" ]]; then
            HOSTNAME=$(echo "$EXTERNAL" | jq -r '.hostname // .ip // "pending"' 2>/dev/null || echo "pending")
            if [[ "$HOSTNAME" != "pending" ]] && [[ "$HOSTNAME" != "" ]]; then
                print_status "HEALTHY" "Load balancer accessible at: $HOSTNAME"
            else
                print_status "DEGRADED" "Load balancer endpoint pending"
            fi
        else
            print_status "DEGRADED" "Load balancer not provisioned"
        fi
        
        # Check service endpoints
        ENDPOINTS=$(kubectl get endpoints harmony -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        if [[ -n "$ENDPOINTS" ]]; then
            ENDPOINT_COUNT=$(echo "$ENDPOINTS" | wc -w)
            print_status "HEALTHY" "$ENDPOINT_COUNT service endpoints available"
        else
            print_status "UNHEALTHY" "No service endpoints available"
        fi
    else
        print_status "UNHEALTHY" "Service 'harmony' not found"
    fi
    
    # ============================================================================
    # Storage Health
    # ============================================================================
    if kubectl get pvc harmony-pvc -n "$NAMESPACE" &> /dev/null 2>&1; then
        print_section "Storage"
        
        STATUS=$(kubectl get pvc harmony-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "$STATUS" == "Bound" ]]; then
            CAPACITY=$(kubectl get pvc harmony-pvc -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}' 2>/dev/null || echo "Unknown")
            print_status "HEALTHY" "PVC bound with capacity: $CAPACITY"
        else
            print_status "UNHEALTHY" "PVC status: $STATUS"
        fi
    fi
    
    # ============================================================================
    # Recent Errors
    # ============================================================================
    print_section "Recent Errors (Last 5 minutes)"
    
    ERROR_EVENTS=$(kubectl get events -n "$NAMESPACE" \
        --field-selector type=Warning \
        --sort-by='.lastTimestamp' 2>/dev/null | tail -5 || echo "")
    
    if [[ -n "$ERROR_EVENTS" ]] && echo "$ERROR_EVENTS" | grep -q "Warning"; then
        ERROR_COUNT=$(echo "$ERROR_EVENTS" | grep -c "Warning" || echo "0")
        print_status "DEGRADED" "$ERROR_COUNT warning events in last 5 minutes"
        echo "$ERROR_EVENTS" | grep "Warning" | head -3 | while read -r line; do
            echo "  $line"
        done
    else
        print_status "HEALTHY" "No warning events in last 5 minutes"
    fi
    
    # ============================================================================
    # Container Logs - Recent Errors
    # ============================================================================
    print_section "Recent Log Errors"
    
    if [[ -n "$PODS" ]]; then
        ERROR_FOUND=false
        for pod in $PODS; do
            ERRORS=$(kubectl logs "$pod" -n "$NAMESPACE" --tail=100 2>/dev/null | grep -iE "error|exception|fatal" | tail -3 || echo "")
            if [[ -n "$ERRORS" ]]; then
                print_status "DEGRADED" "Errors found in pod '$pod' logs"
                echo "$ERRORS" | while read -r line; do
                    echo "  $line"
                done
                ERROR_FOUND=true
            fi
        done
        
        if [[ "$ERROR_FOUND" == false ]]; then
            print_status "HEALTHY" "No errors in recent logs"
        fi
    fi
    
    # ============================================================================
    # Summary
    # ============================================================================
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    
    # Calculate overall health
    TOTAL_CHECKS=6
    UNHEALTHY_COUNT=$(print_status "UNHEALTHY" "test" 2>/dev/null | grep -c "UNHEALTHY" || echo "0")
    
    if [[ "$READY_PODS" -eq "$TOTAL_PODS" ]] && [[ "$READY_PODS" -gt 0 ]]; then
        echo -e "${GREEN}✓ System Status: HEALTHY${NC}"
    elif [[ "$READY_PODS" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ System Status: DEGRADED${NC}"
    else
        echo -e "${RED}✗ System Status: UNHEALTHY${NC}"
    fi
    
    echo ""
}

# Main execution
if [[ "$CONTINUOUS" == true ]]; then
    echo -e "${YELLOW}Starting continuous health monitoring (Interval: ${INTERVAL}s)${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    sleep 2
    
    while true; do
        perform_health_check
        echo ""
        echo -e "${CYAN}Next check in ${INTERVAL} seconds...${NC}"
        sleep "$INTERVAL"
    done
else
    perform_health_check
fi
