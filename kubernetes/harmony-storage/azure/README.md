# NFS Storage Setup for AKS

This directory contains scripts to set up Azure Files NFS persistent storage for your AKS cluster.

## Table of Contents

- [Scripts Overview](#scripts-overview)
  - [`setup-env.sh` - Environment Configuration](#setup-envsh---environment-configuration)
  - [`install-nfs-csi-driver.sh` - CSI Driver Installation](#install-nfs-csi-driversh---csi-driver-installation)
  - [`create-nfs.sh` - NFS Share Creation](#create-nfssh---nfs-share-creation)
  - [`cleanup-nfs.sh` - Resource Cleanup](#cleanup-nfssh---resource-cleanup)
- [Prerequisites](#prerequisites)
- [Workflow](#workflow)
  - [Setup Process](#setup-process)
  - [Using the Storage Account](#using-the-storage-account)
  - [Cleanup Process](#cleanup-process)
- [Quick Commands](#quick-commands)
- [Important Notes](#important-notes)

## Scripts Overview

### `setup-env.sh` - Environment Configuration
**Purpose:** Sets required environment variables for all other scripts.

**Usage:** `source ./setup-env.sh` (must be sourced, not executed)

**What it does:**
- Lists available AKS clusters
- Prompts for cluster and resource group selection
- Auto-detects cluster location
- Sets `CLUSTER_NAME`, `RESOURCE_GROUP`, `NODE_RESOURCE_GROUP` and `LOCATION` environment variables
- Optionally makes variables persistent in shell profile

### `install-nfs-csi-driver.sh` - CSI Driver Installation
**Purpose:** Installs the Azure Files NFS CSI driver addon to enable NFS usage in Kubernetes.

**What it does:**
- Enables the `azure-file-csi-driver` AKS addon
- Configures necessary permissions for NFS access
- Validates driver installation and readiness

### `create-nfs.sh` - NFS Share Creation
**Purpose:** Creates Azure Files NFS storage account and file share for your cluster.

**What it does:**
- Checks for existing storage account named `harmonyconfignfs` in both user and managed resource groups
- Creates new Premium storage account with NFS 4.1 support in the AKS managed resource group (for CSI driver compatibility)
- Gets cluster subnet information for network access
- Creates file share with appropriate performance tier
- Configures network access rules for cluster subnets
- Sets up service endpoint for Azure Files

**Output:** Storage Account name and File Share name for use in your storage configurations

**⚠️  Important:** The storage account is created in the AKS managed resource group (e.g., `MC_yourRG_yourCluster_region`) to ensure compatibility with the Azure Files CSI driver.

### `cleanup-nfs.sh` - Resource Cleanup
**Purpose:** Safely removes Azure Files NFS resources before cluster deletion.

**What it does:**
- Finds storage account by name `harmonyconfignfs` in both user and managed resource groups
- Removes network access restrictions
- Optionally deletes the file share and storage account
- Cleans up service endpoints and network rules

**Usage Options:**
- Interactive mode: `./cleanup-nfs.sh` (prompts for each deletion)
- Automatic mode: `./cleanup-nfs.sh --delete-storage` (no prompts)
- Help: `./cleanup-nfs.sh --help`

**⚠️  Critical:** Must be run before deleting AKS cluster to avoid dependency issues.

## Prerequisites

- Bash shell (required to run the scripts in this directory)
- Azure CLI configured with AKS cluster access
- `kubectl` configured for your cluster
- Existing AKS cluster with Premium tier support
- `jq` installed (JSON processor)

## Workflow

### Setup Process

1. **Configure Environment**
   ```bash
   source ./setup-env.sh
   ```
   Verify variables are set:
   ```bash
   echo "Cluster: $CLUSTER_NAME, Resource Group: $RESOURCE_GROUP, Node Resource Group: $NODE_RESOURCE_GROUP, Location: $LOCATION"
   ```

2. **Install CSI Driver**
   ```bash
   ./install-nfs-csi-driver.sh
   ```

3. **Create NFS Storage Account and Share**
   ```bash
   ./create-nfs.sh
   ```
   Save the returned Storage Account name and File Share name for your application configuration.

### Using the Storage Account

After creation, update your Kubernetes manifests or Helm values with the storage account details:

```yaml
storageClass:
  nfs:
    storageAccountName: "harmonyconfignfsXXXXX"
    shareName: "harmony-config-share"
```

Or deploy with Helm:
```bash
helm upgrade your-release . \
  --set global.platform=azure \
  --set storageClass.nfs.storageAccountName=harmonyconfignfsXXXXX \
  --set storageClass.nfs.shareName=harmony-config-share
```

### Cleanup Process

**Before deleting your AKS cluster:**

1. **Remove application dependencies** (delete pods/deployments using NFS)

2. **Run cleanup script**
   ```bash
   # Interactive mode - prompts for each deletion
   ./cleanup-nfs.sh

   # OR automatic mode - deletes everything without prompts
   ./cleanup-nfs.sh --delete-storage
   ```

3. **Choose whether to delete storage account** (in interactive mode only)

## Quick Commands

```bash
# Check CSI driver status
kubectl get pods -n kube-system -l app=csi-azurefile-controller

# Check storage account (in user resource group)
az storage account show --name <storage-account-name> --resource-group $RESOURCE_GROUP

# Check storage account (in managed resource group, if created by script)
az storage account show --name <storage-account-name> --resource-group $NODE_RESOURCE_GROUP

# Check file shares
az storage share list --account-name <storage-account-name> --resource-group $RESOURCE_GROUP

# Check storage classes
kubectl get storageclass

# Check persistent volume claims
kubectl get pvc -A

# Check persistent volumes
kubectl get pv
```

## Important Notes

- All scripts require `CLUSTER_NAME`, `RESOURCE_GROUP`, `NODE_RESOURCE_GROUP` and `LOCATION` environment variables
- Scripts are idempotent - safe to run multiple times
- Always run cleanup before cluster deletion to avoid orphaned resources
- Storage account names must be globally unique and will have random suffix added
- Azure Files Premium NFS will incur costs until deleted
- The cleanup script searches for storage accounts in both user and managed resource groups
- **Storage accounts are created in the AKS managed resource group** (e.g., `MC_yourRG_yourCluster_region`) for Azure Files CSI driver compatibility
