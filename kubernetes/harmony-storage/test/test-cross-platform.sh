#!/bin/bash

# Cross-platform compatibility test script
# Tests all scripts for common cross-platform issues

echo "🧪 Cross-Platform Compatibility Test"
echo "====================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERRORS_FOUND=0

# Test 1: Syntax check all scripts
echo "1️⃣  Testing script syntax..."
for script in ../aws/*.sh ../azure/*.sh ../gcp/*.sh; do
    if [ -f "$script" ]; then
        if ! bash -n "$script" 2>/dev/null; then
            echo "❌ Syntax error in: $script"
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        else
            echo "✅ Syntax OK: $script"
        fi
    fi
done

# Test 2: Check for cross-platform command usage
echo ""
echo "2️⃣  Checking for cross-platform command usage..."

# Check for potentially problematic commands
PROBLEMATIC_PATTERNS=(
    "sed -i[^.]"  # sed -i without backup extension
    "echo -e"     # echo -e not consistent across platforms
    "echo.*\\\\\\\\n" # literal \\n in echo commands (but tr '\n' is OK)
    "readlink -f" # not available on macOS
    "timeout"     # not available on macOS by default
)

for pattern in "${PROBLEMATIC_PATTERNS[@]}"; do
    matches=$(grep -r "$pattern" ../aws/*.sh ../azure/*.sh ../gcp/*.sh 2>/dev/null || true)
    if [ -n "$matches" ]; then
        echo "⚠️  Potentially problematic pattern found: $pattern"
        echo "$matches"
        ERRORS_FOUND=$((ERRORS_FOUND + 1))
    fi
done

# Test 3: Check shebang consistency
echo ""
echo "3️⃣  Checking shebang consistency..."
for script in ../aws/*.sh ../azure/*.sh ../gcp/*.sh; do
    if [ -f "$script" ]; then
        shebang=$(head -1 "$script")
        if [[ "$shebang" != "#!/bin/bash" ]] && [[ "$shebang" != "#!/usr/bin/env bash" ]]; then
            echo "❌ Inconsistent shebang in $script: $shebang"
            ERRORS_FOUND=$((ERRORS_FOUND + 1))
        else
            echo "✅ Shebang OK: $script"
        fi
    fi
done

# Test 4: Check for required command availability checks
echo ""
echo "4️⃣  Checking for proper command availability checks..."
REQUIRED_CHECKS=("command -v")

for script in ../aws/*.sh ../azure/*.sh ../gcp/*.sh; do
    if [ -f "$script" ]; then
        # Skip setup-env.sh as they have comprehensive checks
        if [[ "$script" == *"setup-env.sh" ]]; then
            continue
        fi

        # Check if script uses external commands without checking availability
        if grep -q "aws\|az\|gcloud\|kubectl\|jq" "$script" && ! grep -q "command -v\|which" "$script"; then
            echo "⚠️  $script uses external commands but doesn't check availability"
        fi
    fi
done

# Test 5: Check file permissions and executable bits
echo ""
echo "5️⃣  Checking file permissions..."
for script in ../aws/*.sh ../azure/*.sh ../gcp/*.sh; do
    if [ -f "$script" ]; then
        if [ ! -x "$script" ]; then
            echo "⚠️  Script not executable: $script (this may be intentional for sourced scripts)"
        else
            echo "✅ Executable: $script"
        fi
    fi
done

# Test 6: Platform detection simulation
echo ""
echo "6️⃣  Testing platform detection simulation..."
for ostype in "linux-gnu" "darwin" "msys" "unknown"; do
    echo "Testing OSTYPE=$ostype..."

    # Test AWS setup platform detection
    result=$(cd ../aws && OSTYPE="$ostype" bash -c '
        source setup-env.sh <<<""
    ' 2>&1 | grep "Platform detected" || echo "No platform detection")

    echo "  AWS: $result"

    # Test Azure platform detection
    result=$(cd ../azure && OSTYPE="$ostype" bash -c '
        source setup-env.sh <<<""
    ' 2>&1 | grep "Platform detected" || echo "No platform detection")

    echo "  Azure: $result"

    # Test GCP setup platform detection
    result=$(cd ../gcp && timeout 5 bash -c '
        OSTYPE="'"$ostype"'" source setup-env.sh <<<""
    ' 2>&1 | grep "Platform detected" || echo "No platform detection")

    echo "  GCP: $result"
done

# Test 7: Check for Windows path compatibility
echo ""
echo "7️⃣  Checking for Windows path compatibility..."
for script in ../aws/*.sh ../azure/*.sh ../gcp/*.sh; do
    if [ -f "$script" ]; then
        # Look for hardcoded Unix paths that might not work on Windows (excluding shebangs)
        if grep -v "^#!" "$script" | grep -q "/usr/\|/opt/\|/etc/"; then
            echo "⚠️  $script contains hardcoded Unix paths"
            grep -v "^#!" "$script" | grep -n "/usr/\|/opt/\|/etc/"
        fi
    fi
done

echo ""
echo "🏁 Test Summary"
echo "==============="
if [ $ERRORS_FOUND -eq 0 ]; then
    echo "✅ All cross-platform compatibility tests passed!"
    echo "Scripts should work on:"
    echo "  • Linux (Ubuntu, RHEL, CentOS, etc.)"
    echo "  • macOS (Intel and Apple Silicon)"
    echo "  • Windows (Git Bash, WSL, Cygwin)"
else
    echo "❌ Found $ERRORS_FOUND potential cross-platform issues"
    echo "Please review the warnings above."
fi

exit $ERRORS_FOUND
