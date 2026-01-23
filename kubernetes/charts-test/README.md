# Helm Charts Testing

This directory contains test scenarios and validation scripts for all Harmony Helm charts.

## Overview

The test suite includes:
- **Helm Lint**: Validates chart syntax and best practices
- **Template Rendering**: Tests chart templates with various value combinations
- **Dry-Run Validation**: Verifies charts can be installed without errors
- **Multi-Scenario Testing**: Tests different deployment configurations

## Directory Structure

```text
charts-test/
├── README.md                         # This file
├── test-all-charts.sh                # Main test runner script
├── harmony-init/                     # harmony-init chart tests
│   ├── values-minimal.yaml           # Minimal required values
│   ├── values-with-persistence.yaml  # With persistent storage
│   └── values-production.yaml        # Production configuration
├── harmony-run/                      # harmony-run chart tests
│   ├── values-aws-minimal.yaml       # AWS minimal setup
│   ├── values-azure-minimal.yaml     # Azure minimal setup
│   ├── values-gcp-minimal.yaml       # GCP minimal setup
│   ├── values-production-aws.yaml    # Production AWS setup
│   └── values-ha-cluster.yaml        # High availability setup
└── harmony-storage/                  # harmony-storage chart tests
    ├── values-aws-efs.yaml           # AWS EFS configuration
    ├── values-azure-nfs.yaml         # Azure Files NFS configuration
    └── values-gcp-filestore.yaml     # GCP Filestore configuration
```

## Running Tests

### Run All Tests
```bash
./test-all-charts.sh
```

### Test Specific Chart
```bash
# Test harmony-init
./test-all-charts.sh harmony-init

# Test harmony-run
./test-all-charts.sh harmony-run

# Test harmony-storage
./test-all-charts.sh harmony-storage
```

### Run Individual Test Scenarios
```bash
# Lint only
helm lint ../harmony-init

# Template rendering with test values
helm template test-release ../harmony-init -f harmony-init/values-minimal.yaml

# Dry-run installation
helm install test-release ../harmony-init -f harmony-init/values-minimal.yaml --dry-run --debug
```

## Test Scenarios

### harmony-init Tests
- **Minimal**: Basic required configuration
- **With Persistence**: Includes persistent storage mount
- **Production**: Full production-ready configuration

### harmony-run Tests
- **AWS Minimal**: Minimal AWS deployment with default settings
- **Azure Minimal**: Minimal Azure deployment with default settings
- **GCP Minimal**: Minimal GCP deployment with default settings
- **Production AWS**: Production AWS with multiple replicas and optimized resources
- **High Availability**: Multi-replica setup with session affinity

### harmony-storage Tests
- **AWS EFS**: Amazon EFS configuration
- **Azure NFS**: Azure Files NFS configuration
- **GCP Filestore**: Google Cloud Filestore configuration

## Validation Checks

Each test performs the following validations:

1. **Syntax Validation**: Ensures YAML is valid
2. **Helm Lint**: Checks for common chart issues
3. **Template Rendering**: Verifies templates render without errors
4. **Required Values**: Confirms all required values are provided
5. **Platform-Specific**: Tests platform-specific annotations and configurations

## Adding New Tests

To add a new test scenario:

1. Create a new values file in the appropriate chart directory
2. Name it descriptively (e.g., `values-scenario-name.yaml`)
3. Document the scenario in this README
4. Run tests to verify

## Troubleshooting

### Common Issues

**Helm lint warnings**: Some warnings are acceptable (e.g., templates without default values)

**Template rendering fails**: Check that all required values are provided in test values files

**Dry-run fails**: Ensure kubectl context is set to a valid cluster (not required for lint/template tests)

## Best Practices

- Keep test values files minimal and focused
- Document the purpose of each test scenario
- Use realistic values that match actual deployment scenarios
- Test edge cases and error conditions
- Keep tests fast and independent
