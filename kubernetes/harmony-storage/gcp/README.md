# Filestore Storage Setup for GKE

This directory contains scripts to set up Google Cloud Filestore persistent storage for your GKE cluster.

## Table of Contents

- [Scripts Overview](#scripts-overview)
  - [`setup-env.sh` - Environment Configuration](#setup-envsh---environment-configuration)
  - [`install-nfs-csi-driver.sh` - CSI Driver Installation](#install-nfs-csi-driversh---csi-driver-installation)
  - [`create-filestore.sh` - Filestore Instance Creation](#create-filestoresh---filestore-instance-creation)
  - [`cleanup-filestore.sh` - Resource Cleanup](#cleanup-filestoresh---resource-cleanup)
- [Prerequisites](#prerequisites)
- [Workflow](#workflow)
  - [Setup Process](#setup-process)
  - [Using the Filestore Instance](#using-the-filestore-instance)
  - [Cleanup Process](#cleanup-process)
- [Quick Commands](#quick-commands)
- [Important Notes](#important-notes)

## Scripts Overview

### `setup-env.sh` - Environment Configuration
**Purpose:** Sets required environment variables for all other scripts.

**Usage:** `source ./setup-env.sh` (must be sourced, not executed)

**What it does:**
- Lists available Google Cloud projects (if no default project is set)
- Prompts for project selection
- Lists available GKE clusters in your project
- Prompts for cluster selection
- Auto-detects cluster location (region/zone)
- Sets `CLUSTER_NAME`, `CLUSTER_LOCATION`, `CLUSTER_ZONE` and `PROJECT_ID` environment variables
- Configures kubectl context for the selected cluster
- Optionally makes variables persistent in shell profile

### `install-nfs-csi-driver.sh` - CSI Driver Installation
**Purpose:** Installs the NFS CSI driver to enable mounting NFS shares in Kubernetes.

**Prerequisites:** Requires cluster-admin permissions to create ClusterRoles and ClusterRoleBindings.

**What it does:**
- Installs the Kubernetes NFS CSI driver
- Creates necessary RBAC resources (ClusterRoles, ClusterRoleBindings)
- Deploys CSI driver controller and node pods
- Verifies CSI driver pod deployment and readiness
- Validates CSIDriver resource creation

### `create-filestore.sh` - Filestore Instance Creation
**Purpose:** Creates Filestore instance and configures network access for your cluster.

**What it does:**
- Checks for existing Filestore named `harmony-config-filestore`
- Gets cluster VPC network information
- Creates new Filestore instance with:
  - Tier: `BASIC_HDD` (1TB minimum, configurable)
  - Share name: `harmony_data`
  - VPC network: Cluster network
  - Encryption: Google-managed keys
- Retrieves instance IP address and share name

**Output:**
- Filestore IP address and share name for use in your storage configurations
- Creates `filestore-storage-info.txt` with configuration details

### `cleanup-filestore.sh` - Resource Cleanup
**Purpose:** Safely removes Filestore resources before cluster deletion.

**What it does:**
- Finds Filestore by name `harmony-config-filestore`
- Checks for Kubernetes PVCs using the Filestore
- Optionally deletes PVCs and Filestore instance
- Removes configuration files

**Usage Options:**
- Interactive mode: `./cleanup-filestore.sh` (prompts for each deletion)
- Automatic mode: `./cleanup-filestore.sh --delete-storage` (no prompts)
- Help: `./cleanup-filestore.sh --help`

**⚠️  Critical:** Must be run before deleting GKE cluster to avoid orphaned resources.

## Prerequisites

- Bash shell (required to run the scripts in this directory)
- Google Cloud SDK configured with GKE cluster access
- `kubectl` configured for your cluster
- Existing GKE cluster

## Workflow

### Setup Process

1. **Configure Environment**
   ```bash
   source ./setup-env.sh
   ```
   Verify variables are set:
   ```bash
   echo "Cluster: $CLUSTER_NAME, Location: $CLUSTER_LOCATION, Zone: $CLUSTER_ZONE, Project: $PROJECT_ID"
   ```

2. **Install CSI Driver**
   ```bash
   ./install-nfs-csi-driver.sh
   ```

3. **Create Filestore Instance**
   ```bash
   ./create-filestore.sh
   ```
   Save the returned Filestore IP and share name for your application configuration.

### Using the Filestore Instance

After creation, update your Kubernetes manifests or Helm values with the Filestore details:

```yaml
global:
  platform: "gcp"

storageClass:
  filestore:
    ip: "10.0.0.2"              # From create-filestore.sh output
    share: "harmony_data"       # From create-filestore.sh output
```

### Cleanup Process

**Before deleting your GKE cluster:**

1. **Remove application dependencies** (delete pods/deployments using Filestore)

2. **Run cleanup script**
   ```bash
   # Interactive mode - prompts for each deletion
   ./cleanup-filestore.sh

   # OR automatic mode - deletes everything without prompts
   ./cleanup-filestore.sh --delete-storage
   ```

3. **Choose whether to delete Filestore** (in interactive mode only)

## Quick Commands

```bash
# Check NFS CSI driver status
kubectl get pods -n kube-system -l app=csi-nfs-node

# Check CSI driver registration
kubectl get csidriver nfs.csi.k8s.io

# Check Filestore instance
gcloud filestore instances describe harmony-config-filestore --location=$CLUSTER_ZONE --project=$PROJECT_ID

# Check storage classes
kubectl get storageclass

# Check persistent volume claims
kubectl get pvc -A
```

## Important Notes

**This setup uses the NFS CSI driver to mount pre-provisioned Filestore instances** (not the dynamic Filestore CSI driver)

- All scripts require `CLUSTER_NAME`, `CLUSTER_LOCATION`, `CLUSTER_ZONE` and `PROJECT_ID` environment variables
- Scripts are idempotent - safe to run multiple times
- Always run cleanup before cluster deletion to avoid orphaned resources
- Filestore instance will incur costs until deleted
- Filestore minimum capacity: BASIC_HDD (1TB), BASIC_SSD (2.5TB)
- Filestore instances are regional and cannot be moved between VPC networks
