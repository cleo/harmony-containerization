# Harmony Deployment Scripts

This directory contains utility scripts for validating, deploying, and monitoring Harmony applications on Kubernetes.

## Available Scripts

### validate-prerequisites.sh
**Purpose**: Validates that all prerequisites are met before deployment

**Usage:**
```bash
./validate-prerequisites.sh [--platform aws|azure|gcp]
```

**Checks:**
- Required CLI tools (kubectl, helm, cloud provider CLIs)
- Kubernetes cluster connectivity
- Namespace existence
- Required secrets
- Storage configuration (if using harmony-storage)
- Sufficient cluster resources

**Example:**
```bash
# Validate for AWS deployment
./validate-prerequisites.sh --platform aws

# Validate without platform-specific checks
./validate-prerequisites.sh
```

---

### verify-deployment.sh
**Purpose**: Verifies that Harmony components deployed successfully

**Usage:**
```bash
./verify-deployment.sh [--namespace harmony] [--timeout 300]
```

**Checks:**
- Chart installation status
- Pod readiness and health
- Service availability
- PVC binding (if persistence enabled)
- Load balancer provisioning
- Certificate validity

**Example:**
```bash
# Verify deployment in default namespace
./verify-deployment.sh

# Verify with custom namespace and timeout
./verify-deployment.sh --namespace harmony-prod --timeout 600
```

---

### health-check.sh
**Purpose**: Continuous monitoring and health checking of Harmony instances

**Usage:**
```bash
./health-check.sh [--namespace harmony] [--interval 60] [--continuous]
```

**Monitors:**
- Pod status and restarts
- Resource utilization (CPU, memory)
- Service endpoints
- Storage availability
- Application responsiveness
- Recent errors in logs

**Example:**
```bash
# Single health check
./health-check.sh

# Continuous monitoring every 60 seconds
./health-check.sh --continuous --interval 60

# Check specific namespace
./health-check.sh --namespace harmony-prod
```

---

## Integration with Deployment Workflow

### Pre-Deployment
```bash
# 1. Validate prerequisites
./scripts/validate-prerequisites.sh --platform aws

# 2. Deploy charts (if validation passes)
cd harmony-storage && helm install harmony-storage . -n harmony
cd ../harmony-init && helm install harmony-init . -n harmony
cd ../harmony-run && helm install harmony-run . -n harmony
```

### Post-Deployment
```bash
# 3. Verify deployment
./scripts/verify-deployment.sh --namespace harmony --timeout 300

# 4. Run health check
./scripts/health-check.sh --namespace harmony
```

### Ongoing Monitoring
```bash
# Continuous health monitoring
./scripts/health-check.sh --namespace harmony --continuous --interval 300
```
