# EFS Storage Setup for EKS

This directory contains scripts to set up Amazon EFS persistent storage for your EKS cluster.

## Table of Contents

- [Scripts Overview](#scripts-overview)
  - [`setup-env.sh` - Environment Configuration](#setup-envsh---environment-configuration)
  - [`install-efs-csi-driver.sh` - CSI Driver Installation](#install-efs-csi-driversh---csi-driver-installation)
  - [`create-efs.sh` - EFS File System Creation](#create-efssh---efs-file-system-creation)
  - [`cleanup-efs.sh` - Resource Cleanup](#cleanup-efssh---resource-cleanup)
- [Prerequisites](#prerequisites)
- [Workflow](#workflow)
  - [Setup Process](#setup-process)
  - [Using the EFS ID](#using-the-efs-id)
  - [Cleanup Process](#cleanup-process)
- [Quick Commands](#quick-commands)
- [Important Notes](#important-notes)

## Scripts Overview

### `setup-env.sh` - Environment Configuration
**Purpose:** Sets required environment variables for all other scripts.

**Usage:** `source ./setup-env.sh` (must be sourced, not executed)

**What it does:**
- Lists available EKS clusters
- Prompts for cluster selection
- Auto-detects cluster region
- Sets `CLUSTER_NAME` and `CLUSTER_REGION` environment variables
- Optionally makes variables persistent in shell profile

### `install-efs-csi-driver.sh` - CSI Driver Installation
**Purpose:** Installs the EFS CSI driver addon to enable EFS usage in Kubernetes.

**What it does:**
- Creates IAM role `AmazonEKS_EFS_CSI_DriverRole` with proper trust policy
- Attaches AWS managed policy `AmazonEFSCSIDriverPolicy`
- Installs/updates the `aws-efs-csi-driver` EKS addon
- Configures IRSA (IAM Roles for Service Accounts) integration

### `create-efs.sh` - EFS File System Creation
**Purpose:** Creates EFS file system and configures network access for your cluster.

**What it does:**
- Checks for existing EFS named `harmony-config-efs`
- Creates new encrypted EFS with `generalPurpose` performance mode
- Gets cluster VPC and subnet information
- Creates mount targets in all cluster subnets
- Configures security group rules (port 2049/TCP) for:
  - Cluster security group access
  - Node security group access
  - Self-referencing rules for cross-AZ communication

**Output:**
- EFS File System ID for use in your storage configurations
- Creates `efs-storage-info.txt` with configuration details

### `cleanup-efs.sh` - Resource Cleanup
**Purpose:** Safely removes EFS resources before cluster deletion.

**What it does:**
- Finds EFS by name `harmony-config-efs`
- Deletes all mount targets (waits for completion)
- Removes security group rules for NFS traffic
- Optionally deletes the EFS file system and all data

**Usage Options:**
- Interactive mode: `./cleanup-efs.sh` (prompts for each deletion)
- Automatic mode: `./cleanup-efs.sh --delete-storage` (no prompts)
- Help: `./cleanup-efs.sh --help`

**⚠️  Critical:** Must be run before deleting EKS cluster to avoid dependency issues.

## Prerequisites

- Bash shell (required to run the scripts in this directory)
- AWS CLI configured with EKS cluster access
- `kubectl` configured for your cluster
- Existing EKS cluster

## Workflow

### Setup Process

1. **Configure Environment**
   ```bash
   source ./setup-env.sh
   ```
   Verify variables are set:
   ```bash
   echo "Cluster: $CLUSTER_NAME, Region: $CLUSTER_REGION"
   ```

2. **Install CSI Driver**
   ```bash
   ./install-efs-csi-driver.sh
   ```

3. **Create EFS File System**
   ```bash
   ./create-efs.sh
   ```
   Save the returned EFS File System ID for your application configuration.

### Using the EFS ID

After creation, update your Kubernetes manifests or Helm values with the EFS ID:

```yaml
persistence:
  efs:
    fileSystemId: "fs-1234567890abcdef0"
```

### Cleanup Process

**Before deleting your EKS cluster:**

1. **Remove application dependencies** (delete pods/deployments using EFS)

2. **Run cleanup script**
   ```bash
   # Interactive mode - prompts for each deletion
   ./cleanup-efs.sh

   # OR automatic mode - deletes everything without prompts
   ./cleanup-efs.sh --delete-storage
   ```

3. **Choose whether to delete EFS** (in interactive mode only)

## Quick Commands

```bash
# Check CSI driver status
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver

# Check EFS file system
aws efs describe-file-systems --region $CLUSTER_REGION --query "FileSystems[?Name=='harmony-config-efs']"

# Check mount targets
aws efs describe-mount-targets --file-system-id <efs-id> --region $CLUSTER_REGION

# Check storage classes
kubectl get storageclass

# Check persistent volume claims
kubectl get pvc -A

# Check persistent volumes
kubectl get pv
```

## Important Notes

- All scripts require `CLUSTER_NAME` and `CLUSTER_REGION` environment variables
- Scripts are idempotent - safe to run multiple times
- Always run cleanup before cluster deletion to avoid orphaned resources
- EFS file system will incur costs until deleted
