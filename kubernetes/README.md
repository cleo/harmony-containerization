# Harmony Kubernetes Deployment Overview

A comprehensive guide to deploying Harmony runtime instances on Kubernetes using Helm charts.

## Table of Contents

- [Introduction](#introduction)
- [Helm Charts Description](#helm-charts-description)
  - [1. harmony-storage (Optional)](#1-harmony-storage-optional)
  - [2. harmony-init (Required)](#2-harmony-init-required)
  - [3. harmony-run (Required)](#3-harmony-run-required)
- [Deployment Flow](#deployment-flow)
- [How Everything Ties Together](#how-everything-ties-together)
  - [Storage Integration](#storage-integration)
  - [Secret Management](#secret-management)
  - [System Identity](#system-identity)
  - [Service Discovery](#service-discovery)
- [Required Tooling](#required-tooling)
  - [AWS CLI](#aws-cli)
  - [Azure CLI](#azure-cli)
  - [Google Cloud SDK](#google-cloud-sdk)
  - [Helm](#helm)
  - [Kubectl](#kubectl)
- [Prerequisites](#prerequisites)
  - [General Requirements](#general-requirements)
  - [Storage Requirements (if using harmony-storage)](#storage-requirements-if-using-harmony-storage)
  - [Network Requirements](#network-requirements)
  - [Resource Requirements](#resource-requirements)
- [Quick Start Guide](#quick-start-guide)
- [Complete End-to-End Example](#complete-end-to-end-example)
- [Quick Reference Cheat Sheet](#quick-reference-cheat-sheet)
- [Chart Testing and Validation](#chart-testing-and-validation)
- [Deployment Validation Scripts](#deployment-validation-scripts)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Frequently Asked Questions (FAQ)](#frequently-asked-questions-faq)
- [Important Considerations](#important-considerations)
  - [Security](#security)
  - [High Availability](#high-availability)
  - [Backup and Recovery](#backup-and-recovery)
  - [Monitoring](#monitoring)
  - [Production Deployment](#production-deployment)

## Introduction

This repository contains three Helm charts that work together to deploy Harmony runtime instances on Kubernetes. Harmony is a CLEO integration platform that handles various communication protocols including FTP, SFTP, HTTP/HTTPS, AS2, SMTP, and OFTP for enterprise data exchange.

The charts are designed to be used in a specific order and provide a complete, production-ready deployment solution for Kubernetes environments.

## Helm Charts Description

### 1. harmony-storage (Optional)

📖 **[Detailed Documentation](harmony-storage/README.md)**

**Purpose**: Provides Kubernetes shared persistent storage infrastructure for Harmony applications using cloud provider storage solutions.

This chart is optional and only needs to be installed if you choose not to use any of the repository connectors as described below and documented in [harmony-init](harmony-init/README.md#example-cleo-config-repo-and-cleo-runtime-repo-files). The default for the `persistence.enabled` value in the other charts is `false` - set to `true` if using this chart.

**What it creates**:
- **StorageClass**: Defines the storage provisioner and configuration for cloud-specific storage
- **PersistentVolumeClaim (PVC)**: Requests shared storage that can be accessed by multiple pods

**Supported Storage Types**:
- **AWS**: Amazon EFS (Elastic File System) with the EFS CSI driver
- **Azure**: Azure Files NFS with the Azure Files CSI driver
- **GCP**: Google Cloud Filestore with the Filestore CSI driver

**Key Features**:
- ReadWriteMany access mode for shared storage across multiple pods
- Encryption at rest and in transit
- Automatic provisioning through cloud provider APIs
- Resource persistence (not deleted when chart is uninstalled)
- Uses the file repository connector

**When to use**:
- When you need shared configuration storage across multiple Harmony instances
- For environments requiring centralized file storage

### 2. harmony-init (Required)

📖 **[Detailed Documentation](harmony-init/README.md)**

**Purpose**: Performs a one-time initialization of the Harmony application with configuration and licensing setup.

**What it creates**:
- **Kubernetes Job**: Runs the Harmony container with initialization parameters
- **Configuration setup**: Initializes system settings and repository configurations

**Required Secrets** (must be created before installation):
1. `cleo-license` - Harmony license file
2. `cleo-license-verification-code` - License verification code
3. `cleo-default-admin-password` - Initial admin password
4. `cleo-system-settings` - System settings configuration
5. `cleo-config-repo` - Static configuration repository settings
6. `cleo-runtime-repo` - Runtime configuration repository settings

**Optional Secrets**:

7. `cleo-log-system` - Log system settings configuration (optional - uses default logging if not provided)

**Key Features**:
- One-time execution job that sets up the Harmony environment
- Supports multiple repository connector types (File, S3, SMB, AzureBlob, GCS)
- Secure secret management for sensitive configuration data
- Integration with persistent storage for configuration persistence

**Repository Connector Types**:
- **File**: Local filesystem storage (recommended with persistent storage)
- **S3**: Amazon S3 bucket storage
- **SMB**: SMB/CIFS network shares
- **AzureBlob**: Azure Blob Storage
- **GCS**: Google Cloud Storage

### 3. harmony-run (Required)

📖 **[Detailed Documentation](harmony-run/README.md)**

**Purpose**: Provides a production-ready deployment of Harmony runtime instances with enterprise protocol support.

**What it creates**:
- **StatefulSet**: Manages Harmony runtime instances with persistent identities and ordered deployment
- **Headless Service**: Enables internal service discovery and communication between instances
- **Load Balancer Service**: Provides external access with session affinity and protocol-specific port configuration

**Supported Protocols**:
- **Admin Interface** (Port 5080): Web-based administration
- **HTTP/HTTPS** (Ports 80/443): Web-based file transfer and APIs
- **FTP** (Ports 20/21): File Transfer Protocol with passive mode support
- **SFTP** (Port 22): Secure File Transfer Protocol over SSH
- **OFTP** (Ports 3305/6619): Odette File Transfer Protocol
- **SMTP** (Ports 25/587/465): Simple Mail Transfer Protocol variants

**Key Features**:
- High availability with multiple runtime instances
- Session affinity for connection persistence
- Configurable protocol port mappings
- Resource management with memory limits and requests
- Integration with cloud load balancers (AWS ELB/NLB, Azure Load Balancer, GCP Network Load Balancer)

## Deployment Flow

The charts must be deployed in the following order:

```
1. Prerequisites Setup
   ├── Create Kubernetes namespace
   ├── Install required tooling
   └── Configure cloud provider access

2. harmony-storage (Optional)
   ├── Configure cloud storage (EFS, Azure Files, or Filestore)
   ├── Install storage chart
   └── Verify PVC is bound

3. Secret Creation
   ├── Create 6 required secrets
   └── Verify secret creation

4. harmony-init (Required)
   ├── Install initialization chart
   ├── Wait for job completion
   └── Verify initialization success

5. harmony-run (Required)
   ├── Install runtime chart
   ├── Verify StatefulSet deployment
   └── Test protocol connectivity
```

## How Everything Ties Together

### Storage Integration
- **harmony-storage** creates the `harmony-pvc` PersistentVolumeClaim
- **harmony-init** mounts this PVC to `/shared-config` and initializes configuration
- **harmony-run** mounts the same PVC to access the initialized configuration
- This ensures configuration consistency across all instances

### Secret Management
- **harmony-init** requires 6 secrets for initial setup (plus 1 optional secret)
- **harmony-run** requires 4 of the same secrets (license, verification code, config/runtime repos) (plus 1 optional secret)
- Secrets are mounted to `/var/secrets` in both charts
- This provides secure access to licensing and configuration data

### System Identity
- Both **harmony-init** and **harmony-run** use the same `systemName` environment variable
- This ensures they operate as part of the same Harmony system
- Multiple deployments can coexist with different system names

### Service Discovery
- **harmony-run** creates both headless and load balancer services
- Headless service enables internal pod-to-pod communication
- Load balancer service provides external protocol access
- Session affinity ensures client connections remain on the same instance

## Required Tooling

### AWS CLI

**Purpose**: Required for AWS-specific operations including EFS setup and EKS cluster management.

**Installation**:
```bash
# Linux/macOS using curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# macOS using Homebrew
brew install awscli

# Windows
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# Verify installation
aws --version
```

**Configuration**:
```bash
# Configure with your AWS credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

**Official Documentation**: [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

### Azure CLI

**Purpose**: Required for Azure-specific operations including Azure Files setup and AKS cluster management.

**Installation**:
```bash
# Linux using curl
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# macOS using Homebrew
brew install azure-cli

# Windows using winget
winget install Microsoft.AzureCLI

# Verify installation
az --version
```

**Configuration**:
```bash
# Login to Azure
az login

# Set default subscription (if multiple)
az account set --subscription "your-subscription-id"
```

**Official Documentation**: [Azure CLI Installation Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

### Google Cloud SDK

**Purpose**: Required for GCP-specific operations including Filestore setup and GKE cluster management.

**Installation**:
```bash
# Linux using curl
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# macOS using Homebrew
brew install --cask google-cloud-sdk

# Windows using installer
# Download from: https://cloud.google.com/sdk/docs/install

# Verify installation
gcloud --version
```

**Configuration**:
```bash
# Initialize and login
gcloud init

# Or login separately
gcloud auth login

# Set default project
gcloud config set project your-project-id

# Set default region/zone
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

**Official Documentation**: [Google Cloud SDK Installation Guide](https://cloud.google.com/sdk/docs/install)

### Helm

**Purpose**: Package manager for Kubernetes applications. Required to install all three Harmony charts.

**Installation**:
```bash
# Linux/macOS using script
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# macOS using Homebrew
brew install helm

# Windows using winget
winget install Helm.Helm

# Verify installation
helm version
```

**Configuration**:
```bash
# Add common Helm repositories (optional)
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

**Official Documentation**: [Helm Installation Guide](https://helm.sh/docs/intro/install/)

### Kubectl

**Purpose**: Command-line tool for interacting with Kubernetes clusters. Required for all Kubernetes operations.

**Installation**:
```bash
# Linux using curl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# macOS using Homebrew
brew install kubectl

# Windows using winget
winget install Kubernetes.kubectl

# Verify installation
kubectl version --client
```

**Configuration**:
```bash
# Configure for EKS cluster
aws eks update-kubeconfig --region us-west-2 --name your-cluster-name

# Configure for AKS cluster
az aks get-credentials --resource-group your-rg --name your-cluster-name

# Configure for GKE cluster
gcloud container clusters get-credentials your-cluster-name --region us-central1

# Verify connection
kubectl cluster-info
kubectl get nodes
```

**Official Documentation**: [Kubectl Installation Guide](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)

## Prerequisites

### General Requirements
- Kubernetes cluster (version >= 1.19.0)
- Target namespace created (default: `harmony`)
- Sufficient cluster resources for Harmony instances
- Cloud provider CLI configured with appropriate permissions

### Storage Requirements (if using harmony-storage)
- **AWS**: EKS cluster with EFS CSI driver addon
- **Azure**: AKS cluster with Azure Files CSI driver (when available)

### Network Requirements
- Load balancer support in your Kubernetes cluster
- Security group/firewall rules for enabled protocol ports
- DNS resolution for external access (optional)

### Resource Requirements
- **Minimum per Harmony instance**: 4GB RAM, 2 CPU cores
- **Recommended**: 8GB RAM, 4 CPU cores per instance
- **Storage**: Variable based on data volume and retention

## Quick Start Guide

This quick overview shows the deployment sequence. For a complete step-by-step example, see [Complete End-to-End Example](#complete-end-to-end-example).

**Deployment Order:**

1. Validate Prerequisites
2. Create Namespace
3. Setup Storage (optional)
4. Create Secrets
5. Deploy charts
   - Deploy storage (optional)
   - Run initialization
   - Deploy Runtime
6. Verify Deployment
7. Access Application

**Essential Commands:**
```bash
# 1. Validate prerequisites
./scripts/validate-prerequisites.sh --platform aws

# 2. Create namespace
kubectl create namespace harmony

# 3. Setup Storage (optional)

# 4. Create secrets (all 6 required)
kubectl create secret generic cleo-license --from-file=cleo-license=license.txt -n harmony
kubectl create secret generic cleo-license-verification-code --from-literal=cleo-license-verification-code='CODE' -n harmony
kubectl create secret generic cleo-default-admin-password --from-literal=cleo-default-admin-password='PASSWORD' -n harmony
kubectl create secret generic cleo-system-settings --from-file=cleo-system-settings=system-settings.yaml -n harmony
kubectl create secret generic cleo-config-repo --from-file=cleo-config-repo=config-repo.yaml -n harmony
kubectl create secret generic cleo-runtime-repo --from-file=cleo-runtime-repo=runtime-repo.yaml -n harmony

# 5. Deploy charts in order
helm install harmony-storage ./harmony-storage -n harmony --set global.platform=aws (optional)
helm install harmony-init ./harmony-init -n harmony
helm install harmony-runtime ./harmony-run -n harmony --set global.platform=aws

# 6. Verify deployment
./scripts/verify-deployment.sh --namespace harmony

# 7. Access admin console
kubectl port-forward svc/harmony 5080:5080 -n harmony
# Open browser: http://localhost:5080
```

## Complete End-to-End Example

A complete, production-ready deployment example for AWS EKS. Adapt cloud-specific commands for Azure AKS or Google GKE.

### Prerequisites Setup

```bash
# Set your cluster information
export CLUSTER_NAME="my-eks-cluster"
export CLUSTER_REGION="us-west-2"
export NAMESPACE="harmony"

# Verify tools are installed
kubectl version --client
helm version
aws --version

# Configure kubectl for your cluster
aws eks update-kubeconfig --region $CLUSTER_REGION --name $CLUSTER_NAME

# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes
```

### Step 1: Setup Cloud Storage (AWS EFS)

```bash
# Navigate to AWS storage scripts
cd harmony-storage/aws

# Source environment setup
source ./setup-env.sh
# Select your EKS cluster when prompted

# Install EFS CSI driver
./install-efs-csi-driver.sh

# Create EFS file system
./create-efs.sh
# Save the EFS ID output: fs-1234567890abcdef0

export EFS_ID="fs-1234567890abcdef0"  # Use your actual EFS ID
cd ../..
```

### Step 2: Create Kubernetes Namespace

```bash
# Create namespace
kubectl create namespace $NAMESPACE

# Verify namespace
kubectl get namespace $NAMESPACE
```

### Step 3: Prepare Configuration Files

```bash
# Create directory for secrets
mkdir -p ~/harmony-secrets
cd ~/harmony-secrets

# Create system-settings.yaml
cat > system-settings.yaml << 'EOF'
---
nodes:
- alias: harmony-1
  url: https://harmony-1.harmony-service.harmony.svc.cluster.local:6443
- alias: harmony-2
  url: https://harmony-2.harmony-service.harmony.svc.cluster.local:6443
- alias: harmony-3
  url: https://harmony-3.harmony-service.harmony.svc.cluster.local:6443
EOF

# Create config-repo.yaml (using shared storage)
cat > config-repo.yaml << 'EOF'
---
type: file
connectorProperties:
  rootPath: /shared-config
advancedProperties:
  outboxSort: Date/Time Modified
EOF

# Create runtime-repo.yaml (using shared storage)
cat > runtime-repo.yaml << 'EOF'
---
type: file
connectorProperties:
  rootPath: /shared-config
advancedProperties:
  outboxSort: Date/Time Modified
EOF

# Copy your license file to this directory
# cp /path/to/your/license_key.txt ./license.txt
```

### Step 4: Create Kubernetes Secrets

```bash
# Create all required secrets
kubectl create secret generic cleo-license \
  --from-file=cleo-license=license.txt \
  -n $NAMESPACE

kubectl create secret generic cleo-license-verification-code \
  --from-literal=cleo-license-verification-code='YOUR-VERIFICATION-CODE' \
  -n $NAMESPACE

kubectl create secret generic cleo-default-admin-password \
  --from-literal=cleo-default-admin-password='YourSecurePassword123!' \
  -n $NAMESPACE

kubectl create secret generic cleo-system-settings \
  --from-file=cleo-system-settings=system-settings.yaml \
  -n $NAMESPACE

kubectl create secret generic cleo-config-repo \
  --from-file=cleo-config-repo=config-repo.yaml \
  -n $NAMESPACE

kubectl create secret generic cleo-runtime-repo \
  --from-file=cleo-runtime-repo=runtime-repo.yaml \
  -n $NAMESPACE

# Verify secrets were created
kubectl get secrets -n $NAMESPACE
```

### Step 5: Deploy Harmony Storage Chart

```bash
cd /path/to/kubernetes/charts

# Update harmony-storage values with your EFS ID
cat > harmony-storage-values.yaml << EOF
global:
  namespace: $NAMESPACE
  platform: aws

storageClass:
  enabled: true
  name: harmony-sc
  reclaimPolicy: Retain
  efs:
    fileSystemId: "$EFS_ID"
    accessPoint:
      path: /harmony-data
      uid: "1000"
      gid: "1000"
      permissions: "0755"

pvc:
  enabled: true
  name: harmony-pvc
  accessMode: ReadWriteMany
  size: 10Gi
EOF

# Install harmony-storage chart
helm install harmony-storage ./harmony-storage \
  -f harmony-storage-values.yaml \
  -n $NAMESPACE

# Wait for PVC to be bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  pvc/harmony-pvc -n $NAMESPACE --timeout=120s

# Verify storage
kubectl get pvc -n $NAMESPACE
kubectl get sc harmony-sc
```

### Step 6: Deploy Harmony Init Chart

```bash
# Create harmony-init values
cat > harmony-init-values.yaml << EOF
global:
  namespace: $NAMESPACE

harmonyInit:
  image:
    repository: cleodev/harmony
    tag: "1.0.0"
    pullPolicy: IfNotPresent

  env:
    systemName: "ProductionSystem"

persistence:
  enabled: true
  claimName: harmony-pvc
  mountPath: /shared-config
EOF

# Install harmony-init chart
helm install harmony-init ./harmony-init \
  -f harmony-init-values.yaml \
  -n $NAMESPACE

# Wait for initialization job to complete
kubectl wait --for=condition=complete \
  job/harmony-init -n $NAMESPACE --timeout=600s

# Check job status
kubectl get job harmony-init -n $NAMESPACE

# View initialization logs
kubectl logs job/harmony-init -n $NAMESPACE
```

### Step 7: Deploy Harmony Runtime Chart

```bash
# Create harmony-run values
cat > harmony-run-values.yaml << EOF
global:
  namespace: $NAMESPACE
  platform: aws

harmony:
  image:
    repository: cleodev/harmony
    tag: "1.0.0"
    pullPolicy: IfNotPresent

  statefulset:
    replicas: 2

  env:
    systemName: "ProductionSystem"

  resources:
    requests:
      memory: "4096Mi"
    limits:
      memory: "8192Mi"

service:
  loadBalancer:
    enabled: true
    ports:
      - name: admin
        port: 5080
        targetPort: 5080
        enabled: true
      - name: https
        port: 443
        targetPort: 443
        enabled: true
      - name: sftp
        port: 22
        targetPort: 22
        enabled: true

persistence:
  enabled: true
  claimName: harmony-pvc
  mountPath: /shared-config
EOF

# Install harmony-run chart
helm install harmony-runtime ./harmony-run \
  -f harmony-run-values.yaml \
  -n $NAMESPACE

# Wait for pods to be ready
kubectl wait --for=condition=ready \
  pod -l app=harmony -n $NAMESPACE --timeout=600s

# Check deployment status
kubectl get statefulset harmony -n $NAMESPACE
kubectl get pods -n $NAMESPACE -l app=harmony
```

### Step 8: Verify Deployment

```bash
# Run verification script
./scripts/verify-deployment.sh --namespace $NAMESPACE

# Get load balancer external endpoint
kubectl get svc harmony -n $NAMESPACE

# Check pod logs
kubectl logs harmony-1 -n $NAMESPACE --tail=50

# Check service endpoints
kubectl get endpoints harmony -n $NAMESPACE
```

### Step 9: Access Harmony Admin Console

```bash
# Option 1: Port forwarding (for testing)
kubectl port-forward svc/harmony 5080:5080 -n $NAMESPACE
# Open browser: http://localhost:5080

# Option 2: Load balancer (for production)
LB_HOSTNAME=$(kubectl get svc harmony -n $NAMESPACE \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Admin Console: http://$LB_HOSTNAME:5080"

# Default credentials:
# Username: administrator
# Password: (the password you set in cleo-default-admin-password secret)
```

### Step 10: Configure and Test Protocols

```bash
# Test SFTP connectivity
sftp -P 22 user@$LB_HOSTNAME

# Test HTTPS
curl -k https://$LB_HOSTNAME:443

# Monitor ongoing health
./scripts/health-check.sh --namespace $NAMESPACE
```

### Cleanup (if needed)

```bash
# Uninstall Helm releases
helm uninstall harmony-runtime -n $NAMESPACE
helm uninstall harmony-init -n $NAMESPACE
helm uninstall harmony-storage -n $NAMESPACE

# Delete namespace
kubectl delete namespace $NAMESPACE

# Cleanup AWS resources
cd harmony-storage/aws
./cleanup-efs.sh --delete-storage
```

## Quick Reference Cheat Sheet

### Essential Commands

#### Cluster & Namespace Operations
```bash
# Connect to cluster
aws eks update-kubeconfig --region REGION --name CLUSTER_NAME        # AWS
az aks get-credentials --resource-group RG --name CLUSTER_NAME       # Azure
gcloud container clusters get-credentials CLUSTER_NAME --zone ZONE   # GCP

# Create namespace
kubectl create namespace harmony

# Set default namespace (optional)
kubectl config set-context --current --namespace=harmony
```

#### Secret Management
```bash
# Create all required secrets (one-liner)
kubectl create secret generic cleo-license --from-file=cleo-license=license.txt -n harmony && \
kubectl create secret generic cleo-license-verification-code --from-literal=cleo-license-verification-code='CODE' -n harmony && \
kubectl create secret generic cleo-default-admin-password --from-literal=cleo-default-admin-password='PASS' -n harmony && \
kubectl create secret generic cleo-system-settings --from-file=cleo-system-settings=system-settings.yaml -n harmony && \
kubectl create secret generic cleo-config-repo --from-file=cleo-config-repo=config-repo.yaml -n harmony && \
kubectl create secret generic cleo-runtime-repo --from-file=cleo-runtime-repo=runtime-repo.yaml -n harmony

# List secrets
kubectl get secrets -n harmony

# View secret content (base64 decoded)
kubectl get secret SECRET_NAME -n harmony -o jsonpath='{.data.KEY}' | base64 -d

# Update a secret
kubectl create secret generic SECRET_NAME --from-literal=KEY='NEW_VALUE' -n harmony --dry-run=client -o yaml | kubectl apply -f -

# Delete a secret
kubectl delete secret SECRET_NAME -n harmony
```

#### Helm Chart Operations
```bash
# Install charts (in order)
helm install harmony-storage ./harmony-storage -n harmony --set global.platform=aws
helm install harmony-init ./harmony-init -n harmony
helm install harmony-runtime ./harmony-run -n harmony --set global.platform=aws

# List installed releases
helm list -n harmony

# Get chart values
helm get values RELEASE_NAME -n harmony

# Upgrade release
helm upgrade RELEASE_NAME ./CHART_DIR -n harmony --reuse-values

# Upgrade with new values
helm upgrade harmony-runtime ./harmony-run -n harmony --set harmony.statefulset.replicas=3

# Rollback release
helm rollback RELEASE_NAME -n harmony

# Uninstall release
helm uninstall RELEASE_NAME -n harmony

# Dry-run (test without installing)
helm install RELEASE_NAME ./CHART_DIR --dry-run --debug -n harmony
```

#### Pod Operations
```bash
# Get pods
kubectl get pods -n harmony
kubectl get pods -n harmony -l app=harmony -o wide

# Describe pod
kubectl describe pod POD_NAME -n harmony

# View logs
kubectl logs POD_NAME -n harmony
kubectl logs POD_NAME -n harmony --tail=100
kubectl logs POD_NAME -n harmony --follow
kubectl logs POD_NAME -n harmony --previous  # Previous container (after restart)

# Execute command in pod
kubectl exec POD_NAME -n harmony -- COMMAND
kubectl exec -it POD_NAME -n harmony -- /bin/bash

# Copy files to/from pod
kubectl cp LOCAL_FILE POD_NAME:/PATH -n harmony
kubectl cp POD_NAME:/PATH LOCAL_FILE -n harmony

# Port forward
kubectl port-forward svc/harmony 5080:5080 -n harmony
kubectl port-forward pod/harmony-1 5080:5080 -n harmony

# Restart pods
kubectl rollout restart statefulset harmony -n harmony
kubectl delete pod POD_NAME -n harmony  # For StatefulSet, pod will be recreated
```

#### Service & Networking
```bash
# Get services
kubectl get svc -n harmony

# Get service details
kubectl describe svc harmony -n harmony

# Get load balancer IP/hostname
kubectl get svc harmony -n harmony -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get svc harmony -n harmony -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get service endpoints
kubectl get endpoints harmony -n harmony

# Test service connectivity
kubectl run test-pod --image=busybox --rm -it -n harmony -- telnet harmony 5080
```

#### Storage Operations
```bash
# Get PVCs
kubectl get pvc -n harmony

# Get PVs
kubectl get pv

# Get StorageClasses
kubectl get sc

# Describe PVC
kubectl describe pvc harmony-pvc -n harmony

# Check PVC binding status
kubectl get pvc harmony-pvc -n harmony -o jsonpath='{.status.phase}'
```

#### StatefulSet Operations
```bash
# Get StatefulSet
kubectl get statefulset harmony -n harmony

# Describe StatefulSet
kubectl describe statefulset harmony -n harmony

# Scale StatefulSet
kubectl scale statefulset harmony --replicas=3 -n harmony

# Update StatefulSet
kubectl patch statefulset harmony -n harmony -p '{"spec":{"replicas":3}}'

# Check rollout status
kubectl rollout status statefulset harmony -n harmony

# View rollout history
kubectl rollout history statefulset harmony -n harmony
```

#### Job Operations (Init)
```bash
# Get jobs
kubectl get jobs -n harmony

# Wait for job completion
kubectl wait --for=condition=complete job/harmony-init -n harmony --timeout=600s

# View job logs
kubectl logs job/harmony-init -n harmony

# Delete completed job
kubectl delete job harmony-init -n harmony

# Delete job and recreate
helm uninstall harmony-init -n harmony
helm install harmony-init ./harmony-init -n harmony
```

#### Monitoring & Troubleshooting
```bash
# Get all resources
kubectl get all -n harmony

# Get events
kubectl get events -n harmony --sort-by='.lastTimestamp'
kubectl get events -n harmony --field-selector type=Warning

# Check resource usage
kubectl top nodes
kubectl top pods -n harmony

# Describe resources for troubleshooting
kubectl describe pod POD_NAME -n harmony
kubectl describe svc harmony -n harmony
kubectl describe pvc harmony-pvc -n harmony

# Check pod status
kubectl get pods -n harmony -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].ready}{"\n"}{end}'

# Get pod restart count
kubectl get pods -n harmony -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# View pod conditions
kubectl get pod POD_NAME -n harmony -o jsonpath='{.status.conditions[*].type}'
```

#### Validation Scripts
```bash
# Validate prerequisites
./scripts/validate-prerequisites.sh --platform aws

# Verify deployment
./scripts/verify-deployment.sh --namespace harmony

# Monitor health
./scripts/health-check.sh --namespace harmony

# Run chart tests
./charts-test/test-all-charts.sh
```

### Common Workflows

#### Update Harmony Version
```bash
# 1. Check current version
helm get values harmony-runtime -n harmony | grep tag

# 2. Backup configuration (optional)
kubectl get configmap -n harmony -o yaml > configmap-backup.yaml

# 3. Upgrade
helm upgrade harmony-runtime ./harmony-run -n harmony \
  --set harmony.image.tag="NEW_VERSION" \
  --reuse-values

# 4. Monitor rollout
kubectl rollout status statefulset harmony -n harmony

# 5. Verify
./scripts/health-check.sh --namespace harmony
```

#### Scale Deployment
```bash
# Scale up
kubectl scale statefulset harmony --replicas=5 -n harmony

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=harmony -n harmony --timeout=600s

# Verify all pods running
kubectl get pods -n harmony -l app=harmony

# Check endpoints
kubectl get endpoints harmony -n harmony
```

#### Complete Teardown
```bash
# 1. Uninstall Helm releases
helm uninstall harmony-runtime -n harmony
helm uninstall harmony-init -n harmony
helm uninstall harmony-storage -n harmony

# 2. Delete namespace (includes all resources)
kubectl delete namespace harmony

# 3. Cleanup cloud storage
cd harmony-storage/aws && ./cleanup-efs.sh --delete-storage  # AWS
cd harmony-storage/azure && ./cleanup-nfs.sh                 # Azure
cd harmony-storage/gcp && ./cleanup-filestore.sh             # GCP
```

#### Backup & Restore
```bash
# Backup secrets
kubectl get secrets -n harmony -o yaml > secrets-backup.yaml

# Backup configuration from PVC (if using file storage)
kubectl exec harmony-1 -n harmony -- tar czf /tmp/config-backup.tar.gz /shared-config
kubectl cp harmony-1:/tmp/config-backup.tar.gz ./config-backup.tar.gz -n harmony

# Restore secrets
kubectl apply -f secrets-backup.yaml

# Restore configuration to PVC
kubectl cp ./config-backup.tar.gz harmony-1:/tmp/config-backup.tar.gz -n harmony
kubectl exec harmony-1 -n harmony -- tar xzf /tmp/config-backup.tar.gz -C /
```

#### Troubleshoot Failing Pods
```bash
# 1. Check pod status
kubectl get pods -n harmony

# 2. Describe pod for events
kubectl describe pod POD_NAME -n harmony

# 3. Check logs
kubectl logs POD_NAME -n harmony --tail=100

# 4. Check previous logs (if pod restarted)
kubectl logs POD_NAME -n harmony --previous

# 5. Check events
kubectl get events -n harmony --field-selector involvedObject.name=POD_NAME

# 6. Interactive debugging
kubectl exec -it POD_NAME -n harmony -- /bin/bash
```

### Platform-Specific Commands

#### AWS EKS
```bash
# Create EKS cluster (example)
eksctl create cluster --name harmony-cluster --region us-west-2 --nodegroup-name standard-workers --node-type m5.large --nodes 3

# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name harmony-cluster

# View EFS file systems
aws efs describe-file-systems --region us-west-2

# View ELB/NLB
aws elbv2 describe-load-balancers --region us-west-2
```

#### Azure AKS
```bash
# Create AKS cluster (example)
az aks create --resource-group harmony-rg --name harmony-cluster --node-count 3 --enable-managed-identity

# Get credentials
az aks get-credentials --resource-group harmony-rg --name harmony-cluster

# View Azure Files shares
az storage share list --account-name STORAGE_ACCOUNT

# View load balancers
az network lb list --resource-group harmony-rg
```

#### Google GKE
```bash
# Create GKE cluster (example)
gcloud container clusters create harmony-cluster --zone us-central1-a --num-nodes 3 --machine-type n1-standard-4

# Get credentials
gcloud container clusters get-credentials harmony-cluster --zone us-central1-a

# View Filestore instances
gcloud filestore instances list --zone us-central1-a

# View load balancers
gcloud compute forwarding-rules list
```

### Quick Tips

**Aliases to save time:**
```bash
# Add to ~/.bashrc or ~/.zshrc
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kex='kubectl exec -it'
alias h='helm'
alias hl='helm list'
alias hg='helm get values'

# Usage examples:
k get pods -n harmony
kl harmony-1 -n harmony
h list -n harmony
```

**Watch resources in real-time:**
```bash
watch kubectl get pods -n harmony
watch kubectl get svc harmony -n harmony
watch 'kubectl top pods -n harmony'
```

**JSON/YAML output for scripting:**
```bash
# JSON output
kubectl get pod POD_NAME -n harmony -o json

# YAML output
kubectl get pod POD_NAME -n harmony -o yaml

# JSONPath for specific fields
kubectl get pods -n harmony -o jsonpath='{.items[*].metadata.name}'
kubectl get svc harmony -n harmony -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**Multi-pod commands:**
```bash
# Get logs from all pods
for pod in $(kubectl get pods -n harmony -l app=harmony -o name); do
  echo "=== $pod ==="
  kubectl logs $pod -n harmony --tail=20
done

# Execute command on all pods
for pod in $(kubectl get pods -n harmony -l app=harmony -o jsonpath='{.items[*].metadata.name}'); do
  kubectl exec $pod -n harmony -- COMMAND
done
```

**Quick health check one-liner:**
```bash
kubectl get pods,svc,pvc,statefulset -n harmony && \
kubectl get events -n harmony --field-selector type=Warning --sort-by='.lastTimestamp' | tail -10
```

## Chart Testing and Validation

📖 **[Complete Testing Documentation](charts-test/README.md)**

A comprehensive test suite is available to validate all Helm charts before deployment.

**Run all tests:**
```bash
cd charts-test
./test-all-charts.sh
```

**Test specific chart:**
```bash
./test-all-charts.sh harmony-init
./test-all-charts.sh harmony-run
./test-all-charts.sh harmony-storage
```

**What's tested:**
- Chart structure validation
- Helm lint compliance
- Template rendering with multiple scenarios
- Platform-specific configurations (AWS, Azure, GCP)
- Production and HA configurations

**Test scenarios include:**
- Minimal configurations
- With persistent storage
- Production deployments
- High availability setups
- Multi-platform scenarios

## Deployment Validation Scripts

🛠️ **[Complete Scripts Documentation](scripts/README.md)**

Utility scripts are provided to validate prerequisites, verify deployments, and monitor health.

### validate-prerequisites.sh
Validates all prerequisites before deployment:
```bash
./scripts/validate-prerequisites.sh --platform aws --check-storage
```

**Checks:**
- Required CLI tools (kubectl, helm, cloud CLIs)
- Kubernetes cluster connectivity
- Required secrets existence
- Storage prerequisites
- Chart availability

### verify-deployment.sh
Verifies successful deployment of all components:
```bash
./scripts/verify-deployment.sh --namespace harmony --timeout 300
```

**Validates:**
- Helm release status
- Pod readiness and health
- Service availability and endpoints
- Load balancer provisioning
- Storage binding (if enabled)
- Recent warning events

### health-check.sh
Monitors runtime health of Harmony instances:
```bash
# Single check
./scripts/health-check.sh --namespace harmony

# Continuous monitoring
./scripts/health-check.sh --namespace harmony --continuous --interval 60
```

**Monitors:**
- Pod status and restart counts
- Resource utilization (CPU/memory)
- Service endpoints
- Storage availability
- Recent errors in logs

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Pods Not Starting

**Symptom:** Pods stuck in `Pending`, `CrashLoopBackOff`, or `ImagePullBackOff` state

**Solutions:**

```bash
# Check pod status
kubectl get pods -n harmony

# Describe pod for details
kubectl describe pod harmony-1 -n harmony

# Check events
kubectl get events -n harmony --sort-by='.lastTimestamp'
```

**Common Causes:**
- **ImagePullBackOff**: Invalid image tag or registry authentication issues
  ```bash
  # Verify image exists
  docker pull cleodev/harmony:TAG
  ```

- **Pending**: Insufficient cluster resources or PVC not bound
  ```bash
  # Check node resources
  kubectl top nodes

  # Check PVC status
  kubectl get pvc -n harmony
  ```

- **CrashLoopBackOff**: Missing secrets or configuration errors
  ```bash
  # Check pod logs
  kubectl logs harmony-1 -n harmony --previous

  # Verify all secrets exist
  kubectl get secrets -n harmony
  ```

#### 2. Initialization Job Fails

**Symptom:** `harmony-init` job status shows `Failed` or never completes

**Solutions:**

```bash
# Check job status
kubectl get job harmony-init -n harmony

# View job logs
kubectl logs job/harmony-init -n harmony

# Check job pod events
kubectl describe job harmony-init -n harmony
```

**Common Causes:**
- Invalid license file or verification code
- Incorrect secret format or missing required fields
- PVC not mounted correctly
- Timeout due to slow initialization

**Fix:**
```bash
# Delete and recreate job
helm uninstall harmony-init -n harmony

# Verify secrets content
kubectl get secret cleo-license -n harmony -o jsonpath='{.data.cleo-license}' | base64 -d

# Reinstall with increased timeout
helm install harmony-init ./harmony-init -n harmony
```

#### 3. Load Balancer External IP Pending

**Symptom:** Service shows `<pending>` for EXTERNAL-IP

**Solutions:**

```bash
# Check service status
kubectl get svc harmony -n harmony

# Describe service for events
kubectl describe svc harmony -n harmony
```

**Common Causes:**
- **AWS**: No available Elastic IPs or service limits reached
  ```bash
  # Check AWS ELB/NLB limits
  aws elbv2 describe-load-balancers --region YOUR_REGION
  ```

- **Azure**: Insufficient IP addresses in subnet
  ```bash
  # Check Azure LB
  az network lb list --resource-group YOUR_RG
  ```

- **GCP**: Project quotas exceeded
  ```bash
  # Check GCP load balancers
  gcloud compute forwarding-rules list
  ```

- **Platform annotation missing**: Verify `global.platform` is set correctly
  ```bash
  helm get values harmony-runtime -n harmony
  ```

#### 4. PVC Not Binding

**Symptom:** PVC status remains `Pending`

**Solutions:**

```bash
# Check PVC status
kubectl get pvc harmony-pvc -n harmony

# Describe PVC for events
kubectl describe pvc harmony-pvc -n harmony

# Check StorageClass
kubectl get sc harmony-sc
kubectl describe sc harmony-sc
```

**Common Causes:**
- **AWS**: EFS CSI driver not installed or EFS file system doesn't exist
  ```bash
  # Check CSI driver
  kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver

  # Verify EFS exists
  aws efs describe-file-systems --region YOUR_REGION
  ```

- **Azure**: Storage account not found or incorrect credentials
  ```bash
  # Verify storage account
  az storage account show --name STORAGE_ACCOUNT_NAME --resource-group YOUR_RG
  ```

- **GCP**: Filestore instance not accessible from cluster
  ```bash
  # Verify Filestore
  gcloud filestore instances describe harmony-config-filestore --zone=YOUR_ZONE
  ```

#### 5. Certificate or SSL Issues

**Symptom:** HTTPS/SSL connection errors

**Solutions:**

```bash
# Test SSL connectivity
curl -vk https://LOAD_BALANCER_IP:443

# Check pod logs for certificate errors
kubectl logs harmony-1 -n harmony | grep -i certificate
```

**Fix:**
- Ensure certificates in `cleo-system-settings` are valid and not expired
- Verify certificate format (PEM, base64 encoded)
- Check that certificate private keys are included

#### 6. High Memory Usage / OOM Kills

**Symptom:** Pods restarting with OOMKilled status

**Solutions:**

```bash
# Check pod resource usage
kubectl top pods -n harmony

# Check for OOMKilled
kubectl get pods -n harmony -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'

# View pod events
kubectl describe pod harmony-1 -n harmony
```

**Fix:**
```bash
# Increase memory limits in values
helm upgrade harmony-runtime ./harmony-run -n harmony \
  --set harmony.resources.limits.memory=16384Mi \
  --reuse-values
```

#### 7. Helm Installation Failures

**Symptom:** Helm install or upgrade commands fail

**Solutions:**

```bash
# Check Helm release status
helm list -n harmony

# View release history
helm history harmony-runtime -n harmony

# Dry-run to see what would be deployed
helm install harmony-runtime ./harmony-run --dry-run --debug -n harmony
```

**Common Causes:**
- Missing required values (e.g., `global.platform`)
- Invalid YAML syntax in values files
- Conflicting resource names

**Fix:**
```bash
# Uninstall failed release
helm uninstall harmony-runtime -n harmony

# Clean up resources
kubectl delete all -l app=harmony -n harmony

# Reinstall with corrected values
helm install harmony-runtime ./harmony-run -n harmony --set global.platform=aws
```

#### 8. Pod-to-Pod Communication Issues

**Symptom:** Pods cannot discover or communicate with each other

**Solutions:**

```bash
# Check headless service
kubectl get svc harmony-service -n harmony

# Check service endpoints
kubectl get endpoints harmony-service -n harmony

# Test DNS resolution from within a pod
kubectl exec harmony-1 -n harmony -- nslookup harmony-service.harmony.svc.cluster.local

# Test connectivity between pods
kubectl exec harmony-1 -n harmony -- ping harmony-2.harmony-service.harmony.svc.cluster.local
```

**Fix:**
- Verify headless service exists and has endpoints
- Check network policies aren't blocking traffic
- Ensure `cleo-system-settings` has correct node URLs

#### 9. Protocol Connection Refused

**Symptom:** Cannot connect to FTP, SFTP, HTTPS, or other protocols

**Solutions:**

```bash
# Check which ports are enabled
kubectl get svc harmony -n harmony -o yaml | grep -A 5 ports

# Verify load balancer is provisioned
kubectl get svc harmony -n harmony

# Test specific protocol
telnet LOAD_BALANCER_IP 5080  # Admin console
telnet LOAD_BALANCER_IP 22    # SFTP
```

**Fix:**
- Enable required ports in `harmony-run` values:
  ```yaml
  service:
    loadBalancer:
      ports:
        - name: sftp
          port: 22
          enabled: true  # Must be true
  ```
- Verify security groups/firewall rules allow traffic
- Check that protocols are enabled in Harmony admin console

### Debugging Commands

**Quick diagnostics:**
```bash
# Get all resources in namespace
kubectl get all -n harmony

# Check recent events
kubectl get events -n harmony --sort-by='.lastTimestamp' | tail -20

# View all pod logs
for pod in $(kubectl get pods -n harmony -l app=harmony -o name); do
  echo "=== $pod ==="
  kubectl logs $pod -n harmony --tail=20
done

# Check resource quotas
kubectl describe resourcequota -n harmony

# Verify RBAC permissions
kubectl auth can-i create pods --namespace harmony
```

**Advanced diagnostics:**
```bash
# Export all resources for analysis
kubectl get all -n harmony -o yaml > harmony-resources.yaml

# Get full pod spec
kubectl get pod harmony-1 -n harmony -o yaml

# Check apiserver logs (if accessible)
kubectl logs -n kube-system kube-apiserver-XXX

# Network debugging from inside pod
kubectl exec -it harmony-1 -n harmony -- /bin/bash
# Inside pod:
curl -v http://harmony-service:5080
ping harmony-2
nslookup harmony-service
```

### Getting Help

If issues persist:

1. **Collect diagnostics:**
   ```bash
   ./scripts/health-check.sh --namespace harmony > health-report.txt
   kubectl get events -n harmony > events.txt
   kubectl logs harmony-1 -n harmony > pod-logs.txt
   ```

2. **Check Harmony logs:** Look in `/shared-config/logs` (if using persistent storage)

3. **Review configuration:** Verify all secrets and values files

4. **Contact Cleo support (support@cleo.com):** Provide collected diagnostics and describe the issue

## Frequently Asked Questions (FAQ)

### General Questions

**Q: Do I need to use harmony-storage chart?**

No, it's optional. You can use alternative repository connectors like S3, Azure Blob, or SMB that don't require shared filesystem storage. Use harmony-storage if you want:
- Shared file-based configuration across instances
- Simplified setup with automatic PVC provisioning
- Native Kubernetes persistent storage

**Q: What's the difference between harmony-init and harmony-run?**

`harmony-init` is a one-time initialization job that:
- Installs the license
- Sets up initial configuration
- Creates default admin user
- Prepares the shared storage (if used)

`harmony-run` is the runtime deployment that:
- Runs continuously as a StatefulSet
- Handles all protocol connections
- Serves the admin console
- Processes business logic

**Q: Can I run multiple Harmony systems in the same cluster?**

Yes! Deploy each system to a different namespace:
```bash
kubectl create namespace harmony-prod
kubectl create namespace harmony-dev
helm install harmony-runtime ./harmony-run -n harmony-prod --set harmony.env.systemName="ProdSystem"
helm install harmony-runtime ./harmony-run -n harmony-dev --set harmony.env.systemName="DevSystem"
```

**Q: How do I upgrade to a new Harmony version?**

Update the image tag and upgrade the Helm release:
```bash
helm upgrade harmony-runtime ./harmony-run -n harmony \
  --set harmony.image.tag="2.0.0" \
  --reuse-values
```

### Scaling and Performance

**Q: How many replicas should I run?**

Depends on your load:
- **Development**: 1 replica
- **Production (low volume)**: 2-3 replicas
- **Production (high volume)**: 3-5 replicas
- **High Availability**: Minimum 3 replicas across multiple AZs

Note: Session affinity means clients stick to the same pod, so scale based on concurrent unique clients.

**Q: Can I scale pods dynamically with HPA?**

StatefulSets don't support HPA well due to persistent identities. Instead:
- Pre-configure more replicas than needed
- Scale manually based on monitoring:
  ```bash
  kubectl scale statefulset harmony --replicas=5 -n harmony
  ```

**Q: What are the resource requirements per pod?**

- **Minimum**: 2GB RAM, 1 CPU
- **Recommended**: 4-8GB RAM, 2-4 CPUs
- **High Volume**: 8-16GB RAM, 4-8 CPUs

Adjust based on workload and monitor with `kubectl top pods`.

### Storage and Data

**Q: What happens if I don't use persistent storage?**

Without persistent storage:
- Configuration is stored in the repository connector (S3, Azure Blob, etc.)
- No shared filesystem between pods
- Pod restarts lose local data
- Must use cloud-native storage for config/runtime repositories

**Q: Can I switch from one storage backend to another?**

Yes, but requires migration:
1. Export configuration from current storage
2. Deploy new storage solution
3. Update `cleo-config-repo` and `cleo-runtime-repo` secrets
4. Restart pods
5. Import configuration to new storage

**Q: How do I backup Harmony data?**

Backup strategy depends on storage type:

**File Storage (EFS/Azure Files/Filestore):**
```bash
# AWS EFS
aws efs create-backup --file-system-id $EFS_ID

# Azure Files
az backup protection enable-for-azurefileshare ...

# GCP Filestore
gcloud filestore backups create ...
```

**S3/Blob Storage:**
- Use versioning
- Enable point-in-time restore
- Regular snapshots

### Networking

**Q: Which protocols does Harmony support?**

Harmony supports:
- **FTP/FTPS** (ports 20/21 + passive ports)
- **SFTP** (port 22)
- **HTTP/HTTPS** (ports 80/443)
- **AS2** (via HTTP/HTTPS)
- **SMTP** (ports 25/587/465)
- **OFTP** (ports 3305/6619)
- **Admin Console** (port 5080)

**Q: How do I enable FTP passive mode?**

Configure in values:
```yaml
service:
  loadBalancer:
    passiveFtp:
      enabled: true
      passivePorts:
        - name: ftp-passive-1
          port: 25900
          targetPort: 25900
        # Add more as needed (max 50 ports on AWS)
```

Then configure the same range in Harmony admin console.

**Q: Can I use a custom domain name?**

Yes:
1. Get load balancer IP/hostname:
   ```bash
   kubectl get svc harmony -n harmony
   ```
2. Create DNS A/CNAME record pointing to it
3. Optionally add Ingress for HTTPS with certificates:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: harmony-ingress
   spec:
     rules:
     - host: harmony.example.com
       http:
         paths:
         - path: /
           backend:
             service:
               name: harmony
               port:
                 number: 443
   ```

### Security

**Q: How are secrets managed?**

Secrets are stored as Kubernetes Secrets and mounted to pods at runtime:
- Secrets are base64 encoded in Kubernetes
- Consider using external secret management (AWS Secrets Manager, Azure Key Vault, Google Secret Manager)
- Enable encryption at rest in your cluster
- Use RBAC to restrict secret access

**Q: How do I rotate credentials?**

```bash
# Update secret
kubectl create secret generic cleo-default-admin-password \
  --from-literal=cleo-default-admin-password='NewPassword123!' \
  -n harmony --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secret
kubectl rollout restart statefulset harmony -n harmony
```

**Q: Is data encrypted?**

- **In transit**: Use HTTPS, FTPS, SFTP for encrypted connections
- **At rest**:
  - AWS EFS: Encrypted by default
  - Azure Files: Encryption enabled
  - GCP Filestore: Google-managed encryption
  - S3/Blob: Server-side encryption

### Troubleshooting

**Q: How do I view Harmony logs?**

```bash
# View pod logs
kubectl logs harmony-1 -n harmony

# Follow logs in real-time
kubectl logs -f harmony-1 -n harmony

# View previous pod logs (after restart)
kubectl logs harmony-1 -n harmony --previous

# View logs in shared storage (if available)
kubectl exec harmony-1 -n harmony -- ls /shared-config/logs
```

**Q: Why are pods restarting?**

Check:
```bash
# Check restart count
kubectl get pods -n harmony

# Check pod events
kubectl describe pod harmony-1 -n harmony

# Common causes:
# - OOMKilled: Increase memory limits
# - Liveness probe failures: Adjust probe settings
# - Application crashes: Check logs
```

**Q: How do I test connectivity to protocols?**

```bash
# Get load balancer address
LB=$(kubectl get svc harmony -n harmony -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test admin console
curl http://$LB:5080

# Test SFTP
sftp -P 22 user@$LB

# Test HTTPS
curl -k https://$LB:443

# Test from within cluster
kubectl run test-pod --image=busybox --rm -it -- /bin/sh
telnet harmony-service 5080
```

### Operations

**Q: How do I perform rolling updates?**

```bash
# Update image tag
helm upgrade harmony-runtime ./harmony-run -n harmony \
  --set harmony.image.tag="new-version" \
  --reuse-values

# Monitor rollout
kubectl rollout status statefulset harmony -n harmony

# Rollback if needed
helm rollback harmony-runtime -n harmony
```

**Q: Can I pause/resume the deployment?**

```bash
# Scale down to zero
kubectl scale statefulset harmony --replicas=0 -n harmony

# Scale back up
kubectl scale statefulset harmony --replicas=2 -n harmony
```

**Q: How do I migrate to a different cloud provider?**

Migration steps:
1. Backup all configuration and data
2. Create new cluster on target cloud
3. Install appropriate CSI drivers
4. Update `global.platform` in values
5. Recreate secrets
6. Deploy charts
7. Restore configuration
8. Test thoroughly before switching traffic

**Q: What's the recommended backup frequency?**

- **Configuration**: Daily backups, retained for 30 days
- **Runtime data**: Hourly backups during business hours
- **Logs**: Aggregate to centralized logging (7-90 day retention)
- **Secrets**: Store securely in external secret manager with version control

## Important Considerations

### Security
- All secrets contain sensitive data and should be encrypted at rest
- Use RBAC to restrict access to the harmony namespace
- Consider external secret management systems for production
- Enable network policies to restrict pod-to-pod communication

### High Availability
- Deploy multiple Harmony runtime instances for resilience
- Use session affinity to maintain client connections
- Deploy across multiple availability zones when possible
- Implement health checks and monitoring

### Backup and Recovery
- Backup persistent volumes regularly if using harmony-storage
- Document your EFS file system ID (AWS) for disaster recovery
- Test restore procedures in non-production environments
- Maintain copies of your Helm values files and secret creation scripts

### Monitoring
- Implement monitoring for all Harmony instances
- Set up alerts for job failures and service unavailability
- Monitor resource usage and scale accordingly
- Log aggregation for troubleshooting and audit trails

### Production Deployment
- Use specific image tags instead of development versions
- Set appropriate resource limits and requests
- Test all protocols and load scenarios before production
- Document your specific configuration and operational procedures
