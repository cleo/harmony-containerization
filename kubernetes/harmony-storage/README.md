# Harmony Storage Helm Chart

Shared storage infrastructure for Harmony application using cloud provider persistent storage.

## Table of Contents

- [Overview](#overview)
- [Chart Structure](#chart-structure)
- [Values Configuration](#values-configuration)
  - [Example Configuration](#example-configuration)
- [Prerequisites](#prerequisites)
  - [AWS Specific](#aws-specific)
  - [Azure Specific](#azure-specific)
  - [GCP Specific](#gcp-specific)
- [Deployment](#deployment)
- [Quick Commands](#quick-commands)
- [Cloud Provider Specific Setup](#cloud-provider-specific-setup)
  - [AWS (EFS)](#aws-efs)
  - [Azure (Azure Files)](#azure-azure-files-nfs)
  - [GCP (Google Cloud Filestore)](#gcp-google-cloud-filestore)
- [Important Notes](#important-notes)
  - [Resource Persistence](#resource-persistence)
  - [Security Considerations](#security-considerations)
  - [Troubleshooting Tips](#troubleshooting-tips)
  - [Backup and Recovery](#backup-and-recovery)

## Overview

The `harmony-storage` Helm chart provides a standardized way to deploy shared persistent storage for Harmony applications across different cloud providers. It creates:

- **StorageClass**: Defines the storage provisioner and configuration
- **PersistentVolumeClaim (PVC)**: Requests storage that can be shared across multiple pods

The chart supports:
- **AWS**: Amazon EFS (Elastic File System) with the EFS CSI driver
- **Azure**: Azure Files NFS with the Azure Files CSI driver
- **GCP**: Google Cloud Filestore with the NFS CSI driver

## Chart Structure

```text
harmony-storage/
├── Chart.yaml                    # Chart metadata and version info
├── values.yaml                   # Default configuration values
├── values.example.yaml           # Example configuration with detailed comments
├── README.md                     # This documentation
├── test/                         # Cross platform script/mount tests
│   ├── CROSS-PLATFORM.md         # Cross-platform compatibility documentation
│   ├── test-cross-platform.sh    # Test script to validate changes to the platform specific scripts
│   └── test-storage-pod.yaml     # Kubernetes manifest to test persistent storage mounting inside a pod
├── aws/                          # AWS EFS setup scripts and documentation
│   ├── README.md                 # Detailed AWS setup instructions
│   ├── setup-env.sh              # Environment configuration
│   ├── install-efs-csi-driver.sh # EFS CSI driver installation
│   ├── create-efs.sh             # EFS file system creation
│   └── cleanup-efs.sh            # Resource cleanup
├── azure/                        # Azure Files NFS setup scripts and documentation
│   ├── README.md                 # Detailed Azure setup instructions
│   ├── setup-env.sh              # Environment configuration
│   ├── install-nfs-csi-driver.sh # Azure Files CSI driver installation
│   ├── create-nfs.sh             # Azure Files storage account creation
│   └── cleanup-nfs.sh            # Resource cleanup
├── gcp/                          # Google Cloud Filestore setup scripts and documentation
│   ├── README.md                 # Detailed GCP setup instructions
│   ├── setup-env.sh              # Environment configuration
│   ├── install-nfs-csi-driver.sh # NFS CSI driver installation
│   ├── create-filestore.sh       # Filestore instance creation
│   └── cleanup-filestore.sh      # Resource cleanup
└── templates/                    # Kubernetes resource templates
    ├── _helpers.tpl              # Template helper functions
    ├── storageclass.yaml         # StorageClass resource template
    └── pvc.yaml                  # PersistentVolumeClaim template
```

## Values Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Global Settings** | | |
| `global.namespace` | Target namespace for storage resources | `harmony` |
| `global.platform` | **[REQUIRED]** Cloud platform (`aws`, `azure`, or `gcp`) | *None* |
| **Storage Class Configuration** | | | |
| `storageClass.enabled` | Whether to create the storage class | `true` |
| `storageClass.name` | Name of the storage class | `harmony-sc` |
| `storageClass.reclaimPolicy` | Reclaim policy (Retain or Delete) | `Retain` |
| **EFS Configuration (AWS)** | | | |
| `storageClass.efs.fileSystemId` | EFS file system ID | `""` (**required**) |
| `storageClass.efs.accessPoint.path` | Root directory for access points | `/harmony-data` |
| `storageClass.efs.accessPoint.uid` | User ID for file ownership | `1000` |
| `storageClass.efs.accessPoint.gid` | Group ID for file ownership | `1000` |
| `storageClass.efs.accessPoint.permissions` | Directory permissions | `0755` |
| **NFS Configuration (Azure)** | | | |
| `storageClass.nfs.storageAccountName` | Azure Files storage account name | `""` (**required**) |
| `storageClass.nfs.shareName` | Azure Files NFS share name | `""` (**required**) |
| **Filestore Configuration (GCP)** | | |
| `storageClass.filestore.ip` | Filestore instance IP address | `""` (**required**) |
| `storageClass.filestore.share` | Filestore share name | `""` (**required**) |
| **PVC Configuration** | | | |
| `pvc.enabled` | Whether to create the PVC | `true` |
| `pvc.name` | Name of the PVC | `harmony-pvc` |
| `pvc.accessMode` | Access mode for the PVC | `ReadWriteMany` |
| `pvc.size` | Size of the PVC | `5Gi` |

> [!NOTE]
> Default values are contained in the [values.yaml](values.yaml) file.

> [!TIP]
> See [values.example.yaml](values.example.yaml) for complete configuration examples for AWS EFS, Azure Files NFS, and Google Cloud Filestore.

### Example Configuration

#### AWS EFS Example
```yaml
# my-values.yaml for AWS
global:
  namespace: harmony
  platform: aws  # REQUIRED: must be "aws", "azure", or "gcp"

storageClass:
  enabled: true
  name: "harmony-sc"
  reclaimPolicy: "Retain"
  efs:
    fileSystemId: "fs-1234567890abcdef0"  # Required for AWS
    accessPoint:
      path: "/harmony-data"
      uid: "1000"
      gid: "1000"
      permissions: "0755"

pvc:
  enabled: true
  name: "harmony-pvc"
  accessMode: ReadWriteMany
  size: 5Gi
```

#### Azure Files NFS Example
```yaml
# my-values.yaml for Azure
global:
  namespace: harmony
  platform: azure  # REQUIRED: must be "aws", "azure", or "gcp"

storageClass:
  enabled: true
  name: "harmony-sc"
  reclaimPolicy: "Retain"
  nfs:
    storageAccountName: "harmonyconfignfsXXXXX"  # Required for Azure
    shareName: "harmony-config-share"            # Required for Azure

pvc:
  enabled: true
  name: "harmony-pvc"
  accessMode: ReadWriteMany
  size: 5Gi
```

#### Google Cloud Filestore Example
```yaml
# my-values.yaml for GCP
global:
  namespace: harmony
  platform: gcp  # REQUIRED: must be "aws", "azure", or "gcp"

storageClass:
  enabled: true
  name: "harmony-sc"
  reclaimPolicy: "Retain"
  filestore:
    ip: "10.0.0.2"                    # Required for GCP
    share: "harmony_data"             # Required for GCP

pvc:
  enabled: true
  name: "harmony-pvc"
  accessMode: ReadWriteMany
  size: 5Gi
```

## Prerequisites

- Kubernetes cluster on AWS EKS, Azure AKS, or Google GKE
- Helm 3.x and `kubectl` configured
- Target namespace created (default: `harmony`)
- Bash shell (required to run platform-specific setup scripts)
- Cloud-specific requirements:

### AWS Specific
- AWS CLI with appropriate permissions
- EFS CSI driver installed
- EFS file system created

### Azure Specific
- Azure CLI configured with appropriate permissions
- `jq` JSON processor installed
- AKS cluster with Azure Files CSI driver
- Azure Files Premium storage account with NFS share created

### GCP Specific
- Google Cloud SDK (gcloud CLI) configured with appropriate permissions
- GKE cluster with Filestore CSI driver addon
- Google Cloud Filestore instance created and accessible from the cluster

## Deployment

> **Tip:** Copy and customize the example values file:
> ```bash
> cp values.example.yaml my-values.yaml
> # Edit my-values.yaml with your cloud storage details
> helm install harmony-storage . -f my-values.yaml -n harmony
> ```

1. Run cloud-specific setup scripts (see [Cloud Provider Specific Setup](#cloud-provider-specific-setup))
2. Update `my-values.yaml` with storage details (EFS ID, storage account name, or Filestore IP)
3. Install: `helm install harmony-storage . -f my-values.yaml -n harmony`
4. Verify: `kubectl get pvc harmony-pvc -n harmony` (status should be `Bound`)

## Quick Commands
```bash
# Check CSI driver pods (AWS)
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver

# Check CSI driver pods (Azure)
kubectl get pods -n kube-system -l app=csi-azurefile-node

# Check CSI driver pods (GCP)
kubectl get pods -n kube-system -l app=csi-nfs-node

# Check events for PVC issues
kubectl get events --field-selector involvedObject.name=harmony-pvc -n harmony

# Check storage class parameters
kubectl get storageclass harmony-sc -o yaml
```

> **Tip:** See the [main README Quick Reference](../README.md#quick-reference-cheat-sheet) for more commands.

## Cloud Provider Specific Setup

### AWS (EFS)
For detailed AWS setup instructions, see [aws/README.md](aws/README.md).

**Key Steps:**
1. Configure environment variables: `source ./aws/setup-env.sh`
2. Install EFS CSI driver: `./aws/install-efs-csi-driver.sh`
3. Create EFS file system: `./aws/create-efs.sh`
4. Update chart values with EFS ID
5. Cleanup when done: `./aws/cleanup-efs.sh`

### Azure (Azure Files NFS)
For detailed Azure setup instructions, see [azure/README.md](azure/README.md).

**Key Steps:**
1. Configure environment variables: `source ./azure/setup-env.sh`
2. Install NFS CSI driver: `./azure/install-nfs-csi-driver.sh`
3. Create Azure Files NFS share: `./azure/create-nfs.sh`
4. Update chart values with storage account name and share name
5. Cleanup when done: `./azure/cleanup-nfs.sh`

### GCP (Google Cloud Filestore)
For detailed GCP setup instructions, see [gcp/README.md](gcp/README.md).

**Key Steps:**
1. Configure environment variables: `source ./gcp/setup-env.sh`
2. Install NFS CSI driver: `./gcp/install-nfs-csi-driver.sh`
3. Create Filestore instance: `./gcp/create-filestore.sh`
4. Update chart values with Filestore IP and share name
5. Cleanup when done: `./gcp/cleanup-filestore.sh`

## Important Notes
### Resource Persistence
- Resources will **NOT** be deleted when the Helm chart is uninstalled
- This prevents accidental data loss during chart updates or removal
- To fully remove resources, delete them manually after uninstalling the chart

### Security Considerations
- **AWS**: EFS file systems are created with encryption at rest
- **AWS**: File ownership is set via UID/GID in the storage class configuration
- **Azure**: Azure Files Premium storage accounts use encryption at rest and in transit
- **Azure**: Network access is restricted to cluster VNet via service endpoints
- **GCP**: Filestore data is encrypted at rest using Google-managed encryption keys  
- **GCP**: Network access is controlled by VPC network membership

### Troubleshooting Tips
- Ensure CSI driver is running before creating PVCs
- **AWS**: Verify security group rules allow NFS traffic (port 2049)
- **AWS**: Check that EFS mount targets exist in all cluster subnets
- **Azure**: Ensure Premium_LRS storage account tier is used for NFS support
- **GCP**: Ensure NFS traffic (port 2049) is allowed in VPC firewall rules

### Backup and Recovery
- **AWS**: Consider enabling EFS backup and document your EFS file system ID for disaster recovery
- **Azure**: Consider enabling Azure Files backup and document storage account details for disaster recovery
- **GCP**: Use Filestore backups for data protection and document instance details for disaster recovery
- Test restore procedures in a non-production environment
- All platforms store configuration details in info files (efs-storage-info.txt / nfs-storage-info.txt / filestore-storage-info.txt)
