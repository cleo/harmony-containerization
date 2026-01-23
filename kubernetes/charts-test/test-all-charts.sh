#!/bin/bash

# test-all-charts.sh - Comprehensive Helm chart testing script
# Tests all Harmony charts with multiple scenarios

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        Harmony Helm Charts Test Suite${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# Function to print test result
print_result() {
    local status=$1
    local message=$2
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC} - $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Function to test helm lint
test_helm_lint() {
    local chart_name=$1
    local chart_path=$2
    
    echo -e "\n${YELLOW}Testing: helm lint ${chart_name}${NC}"
    
    if helm lint "$chart_path" > /dev/null 2>&1; then
        print_result "PASS" "Helm lint: $chart_name"
        return 0
    else
        print_result "FAIL" "Helm lint: $chart_name"
        helm lint "$chart_path" || true
        return 1
    fi
}

# Function to test template rendering
test_template_render() {
    local chart_name=$1
    local chart_path=$2
    local values_file=$3
    local scenario_name=$4
    
    echo -e "\n${YELLOW}Testing: template render ${chart_name} - ${scenario_name}${NC}"
    
    if [ -f "$values_file" ]; then
        if helm template test-release "$chart_path" -f "$values_file" > /dev/null 2>&1; then
            print_result "PASS" "Template render: $chart_name - $scenario_name"
            return 0
        else
            print_result "FAIL" "Template render: $chart_name - $scenario_name"
            helm template test-release "$chart_path" -f "$values_file" 2>&1 | head -20 || true
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ SKIP${NC} - Values file not found: $values_file"
        return 0
    fi
}

# Function to test chart structure
test_chart_structure() {
    local chart_name=$1
    local chart_path=$2
    
    echo -e "\n${YELLOW}Testing: chart structure ${chart_name}${NC}"
    
    local has_errors=0
    
    # Check Chart.yaml exists
    if [ ! -f "$chart_path/Chart.yaml" ]; then
        print_result "FAIL" "Chart.yaml missing: $chart_name"
        has_errors=1
    fi
    
    # Check values.yaml exists
    if [ ! -f "$chart_path/values.yaml" ]; then
        print_result "FAIL" "values.yaml missing: $chart_name"
        has_errors=1
    fi
    
    # Check templates directory exists
    if [ ! -d "$chart_path/templates" ]; then
        print_result "FAIL" "templates/ directory missing: $chart_name"
        has_errors=1
    fi
    
    # Check README.md exists
    if [ ! -f "$chart_path/README.md" ]; then
        print_result "FAIL" "README.md missing: $chart_name"
        has_errors=1
    fi
    
    if [ $has_errors -eq 0 ]; then
        print_result "PASS" "Chart structure: $chart_name"
    fi
    
    return $has_errors
}

# Test harmony-init chart
test_harmony_init() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing: harmony-init${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local chart_path="$CHARTS_DIR/harmony-init"
    
    test_chart_structure "harmony-init" "$chart_path"
    test_helm_lint "harmony-init" "$chart_path"
    test_template_render "harmony-init" "$chart_path" "$SCRIPT_DIR/harmony-init/values-minimal.yaml" "minimal"
    test_template_render "harmony-init" "$chart_path" "$SCRIPT_DIR/harmony-init/values-with-persistence.yaml" "with-persistence"
    test_template_render "harmony-init" "$chart_path" "$SCRIPT_DIR/harmony-init/values-production.yaml" "production"
}

# Test harmony-run chart
test_harmony_run() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing: harmony-run${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local chart_path="$CHARTS_DIR/harmony-run"
    
    test_chart_structure "harmony-run" "$chart_path"
    test_helm_lint "harmony-run" "$chart_path"
    test_template_render "harmony-run" "$chart_path" "$SCRIPT_DIR/harmony-run/values-aws-minimal.yaml" "aws-minimal"
    test_template_render "harmony-run" "$chart_path" "$SCRIPT_DIR/harmony-run/values-azure-minimal.yaml" "azure-minimal"
    test_template_render "harmony-run" "$chart_path" "$SCRIPT_DIR/harmony-run/values-gcp-minimal.yaml" "gcp-minimal"
    test_template_render "harmony-run" "$chart_path" "$SCRIPT_DIR/harmony-run/values-production-aws.yaml" "production-aws"
    test_template_render "harmony-run" "$chart_path" "$SCRIPT_DIR/harmony-run/values-ha-cluster.yaml" "ha-cluster"
}

# Test harmony-storage chart
test_harmony_storage() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing: harmony-storage${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local chart_path="$CHARTS_DIR/harmony-storage"
    
    test_chart_structure "harmony-storage" "$chart_path"
    test_helm_lint "harmony-storage" "$chart_path"
    test_template_render "harmony-storage" "$chart_path" "$SCRIPT_DIR/harmony-storage/values-aws-efs.yaml" "aws-efs"
    test_template_render "harmony-storage" "$chart_path" "$SCRIPT_DIR/harmony-storage/values-azure-nfs.yaml" "azure-nfs"
    test_template_render "harmony-storage" "$chart_path" "$SCRIPT_DIR/harmony-storage/values-gcp-filestore.yaml" "gcp-filestore"
}

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm command not found${NC}"
    echo "Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo "Helm version: $(helm version --short)"
echo ""

# Parse command line arguments
if [ $# -eq 0 ]; then
    # Run all tests
    test_harmony_init
    test_harmony_run
    test_harmony_storage
elif [ "$1" = "harmony-init" ]; then
    test_harmony_init
elif [ "$1" = "harmony-run" ]; then
    test_harmony_run
elif [ "$1" = "harmony-storage" ]; then
    test_harmony_storage
else
    echo -e "${RED}Error: Unknown chart '$1'${NC}"
    echo "Usage: $0 [harmony-init|harmony-run|harmony-storage]"
    exit 1
fi

# Print summary
echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        Test Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "Total tests run:    ${TESTS_RUN}"
echo -e "${GREEN}Tests passed:       ${TESTS_PASSED}${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Tests failed:       ${TESTS_FAILED}${NC}"
else
    echo -e "Tests failed:       ${TESTS_FAILED}"
fi
echo ""

# Exit with appropriate code
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
fi
