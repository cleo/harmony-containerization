# Harmony Init Helm Chart

One-time initialization job for Harmony application.

## Table of Contents

- [Overview](#overview)
- [Chart Structure](#chart-structure)
- [Values Configuration](#values-configuration)
  - [Example Configuration](#example-configuration)
- [Prerequisites](#prerequisites)
  - [Example system settings file](#example-cleo-system-settings-file)
  - [Example config/runtime files](#example-cleo-config-repo-and-cleo-runtime-repo-files)
  - [Example log system settings file](#example-cleo-log-system-file)
- [Deployment](#deployment)
- [Quick Commands](#quick-commands)
- [Secret Creation Examples](#secret-creation-examples)
- [Important Notes](#important-notes)

## Overview

The `harmony-init` Helm chart provides a standardized way to perform one-time initialization of Harmony application on Kubernetes. It creates:

- **Kubernetes Job**: Runs the Harmony container with initialization parameters
- **Secret Mounting**: Mounts required secrets for licensing and configuration
- **Persistent Storage**: Integrates with shared storage for configuration persistence

The chart supports:
- **Licensing**: Automated license file and verification code setup
- **Configuration**: Initial system settings and repository configuration
- **Security**: Default admin password setup

## Chart Structure

```text
harmony-init/
├── Chart.yaml              # Chart metadata and version info
├── values.yaml             # Default configuration values
├── values.example.yaml     # Example configuration with detailed comments
├── README.md               # This documentation
└── templates/              # Kubernetes resource templates
    ├── _helpers.tpl        # Template helper functions
    └── job.yaml            # Kubernetes Job resource template
```

## Values Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Global Settings** | | |
| `global.namespace` | Target namespace for all resources | `harmony` |
| **Image Configuration** | | |
| `harmonyInit.image.name` | Container name in the pod | `harmony` |
| `harmonyInit.image.repository` | Docker image repository | `cleodev/harmony` |
| `harmonyInit.image.tag` | Image tag (use specific versions in production) | `latest` |
| `harmonyInit.image.pullPolicy` | Image pull policy (Always, IfNotPresent, Never) | `Always` |
| **Job Configuration** | | |
| `harmonyInit.job.backoffLimit` | Number of retries before marking job as failed | `2` |
| `harmonyInit.job.restartPolicy` | Job restart policy (Never, OnFailure) | `Never` |
| **Environment Variables** | | |
| `harmonyInit.env.systemName` | Name of this Harmony system (unique per environment) | `System1` |
| `harmonyInit.env.secretsMountPoint` | Location where secrets will be mounted | `/var/secrets` |
| **Volume Configuration** | | |
| `harmonyInit.volumes.secrets.sources` | Array of secret sources to mount | 7 secrets (see below) |
| **Persistence Configuration** | | |
| `persistence.enabled` | Enable persistent storage mounting | `false` |
| `persistence.claimName` | Name of the PersistentVolumeClaim | `harmony-pvc` |
| `persistence.mountPath` | Mount point in the harmony file system | `/shared-config` |

> [!NOTE]
> Default values are contained in the [values.yaml](values.yaml) file.

> [!TIP]
> See [values.example.yaml](values.example.yaml) for a comprehensive configuration example with detailed comments.

### Example Configuration

```yaml
# my-values.yaml
global:
  namespace: harmony

harmonyInit:
  image:
    name: harmony
    repository: cleodev/harmony
    tag: "v1.2.3"  # Use specific version in production
    pullPolicy: IfNotPresent

  job:
    backoffLimit: 2
    restartPolicy: Never

  env:
    systemName: "System1"
    secretsMountPoint: "/var/secrets"

  volumes:
    secrets:
      sources:
        - secretName: cleo-license
        - secretName: cleo-license-verification-code
        - secretName: cleo-config-repo
        - secretName: cleo-runtime-repo
        - secretName: cleo-default-admin-password
        - secretName: cleo-system-settings
        - secretName: cleo-log-system
          optional: true

persistence:
  enabled: false
  claimName: "harmony-pvc"
  mountPath: "/shared-config"
```

## Prerequisites

- Kubernetes 1.19+ with Helm 3.x
- Target namespace created (default: `harmony`)
- **All 6 required secrets created** (see [Secret Creation Examples](#secret-creation-examples))
- Optional: `harmony-storage` chart deployed (if using persistent storage)

> **Note:** For complete deployment prerequisites and secret details, see the [main README](../README.md#prerequisites).

### Example `cleo-system-settings` file

The bare minimum information that needs to be present in the system setting file is the node configuration. This is used by each Harmony application instance to discover any other active nodes. A best practice is to specify more nodes than are planned to be used to leave room for scaling up the number of nodes in the future. The following yaml snippet configures discovery for up to 5 nodes, even though the default number that will be started is 2.

Sample system settings file is [here](secrets/sample-system-settings.yaml) - This is the complete set of supported values for reference.

```yaml
---
nodes:
- alias: harmony-1
  url: https://harmony-1.harmony-service.harmony.svc.cluster.local:6443
- alias: harmony-2
  url: https://harmony-2.harmony-service.harmony.svc.cluster.local:6443
- alias: harmony-3
  url: https://harmony-3.harmony-service.harmony.svc.cluster.local:6443
- alias: harmony-4
  url: https://harmony-4.harmony-service.harmony.svc.cluster.local:6443
- alias: harmony-5
  url: https://harmony-5.harmony-service.harmony.svc.cluster.local:6443
```

### Example `cleo-config-repo` and `cleo-runtime-repo` files

> [!NOTE]
> If Kubernetes persistent storage is being used then use a **File** connector configuration with `rootPath: /shared-config` and set the `persistence.enabled` value to `true`.

The following are some example secret files that can be used with the `cleo-config-repo` and `cleo-runtime-repo` secrets. These files define the repository configurations for the Harmony application. The type of repository can be File, S3, SMB, AzureBlob or GCS, and the configuration will vary based on the type. See [here](https://developer.cleo.com/api/api-reference/resource-connections) for the full set of `connectorProperties`.

Sample config/runtime files are [here](secrets/sample-config-repo.yaml) and [here](secrets/sample-runtime-repo.yaml).

Example **File** secret file:

```yaml
---
type: file
connectorProperties:
  rootPath: /app/hostrepo
advancedProperties:
  outboxSort: Date/Time Modified
```

Example **S3** secret file:

```yaml
---
type: s3
rootPath: <path>
connectorProperties:
  bucket: <bucket>
  region: <region>
  protocol: HTTPS
  accessKey: <access-key>
  secretAccessKey: <secret-access-key>
advancedProperties:
  outboxSort: Date/Time Modified
```

Example **SMB** secret file:

```yaml
---
type: smb
connectorProperties:
  sharePath: //1.2.3.4/containershare
  userName: <username>
  userPassword: <password>
advancedProperties:
  outboxSort: Date/Time Modified
```

Example **AzureBlob** secret file:

```yaml
---
type: AzureBlob
rootPath: <path>
connectorProperties:
  accessKey: <access-key>
  blobType: BLOCK_BLOB
  storageAccountName: <storage-account-name>
  container: <container>
advancedProperties:
  outboxSort: Date/Time Modified
```

Example **GCS** secret file:
```yaml
---
type: GCPBucket
rootPath: <path>
connectorProperties:
  googleAccountKey: |
    {
    "type": "<type>",
    "project_id": "<project_id>",
    "private_key_id": "<project_key_id>",
    "private_key": "<private_key>",
    "client_email": "<client_email>",
    "client_id": "<client_id>",
    "auth_uri": "<auth_uri>",
    "token_uri": "<token_uri>",
    "auth_provider_x509_cert_url": "<auth_provider_x509_cert_url>",
    "client_x509_cert_url": "<client_x509_cert_url>"
    }
  bucketName: <bucket-name>
  projectId: <project-id>
advancedProperties:
  outboxSort: Date/Time Modified
```

### Example `cleo-log-system` file

The following are some example secret files that can be used with the `cleo-log-system` secret. These files define the logger configuration for the Harmony application. The type of logger can be Datadog or Splunk and the configuration will vary based on the type. See [here](https://developer.cleo.com/api/api-reference/resource-connections) for the full set of `connectorProperties`.

Example **Datadog** secret file:

```yaml
---
type: datadog
connectorProperties:
  apiKey: <api-key>
  appKey: <app-key>
  site: us3.datadoghq.com
  host: %hostname%
  index: eventlogs
  batchCount: 10000
```

Example **Splunk** secret file:

```yaml
---
type: splunk
connectorProperties:
  url: <url>
  host: <host>
  token: <token>
advancedProperties:
  logLevel: DEBUG
```

## Deployment

> **Tip:** Copy and customize the example values file:
> ```bash
> cp values.example.yaml my-values.yaml
> # Edit my-values.yaml with your configuration
> helm install harmony-init . -f my-values.yaml -n harmony
> ```

1. Create all required secrets (see [Secret Creation Examples](#secret-creation-examples))
2. Customize configuration (copy `values.example.yaml` to `my-values.yaml` and edit)
3. Install chart: `helm install harmony-init . -f my-values.yaml -n harmony`
4. Monitor: `kubectl wait --for=condition=complete job/harmony-init -n harmony --timeout=600s`
5. Verify: `kubectl logs job/harmony-init -n harmony`

## Quick Commands

```bash
# Install
helm install harmony-init . -f my-values.yaml -n harmony

# Monitor job
kubectl wait --for=condition=complete job/harmony-init -n harmony --timeout=600s

# View logs
kubectl logs job/harmony-init -n harmony

# Rerun initialization (delete and reinstall)
helm uninstall harmony-init -n harmony
helm install harmony-init . -f my-values.yaml -n harmony
```

> **Tip:** See the [main README Quick Reference](../README.md#quick-reference-cheat-sheet) for more commands.

```bash
# Check job status
kubectl get jobs -n harmony

# Check job pods
kubectl get pods -n harmony -l app=harmony-init

# Check job completion
kubectl get job harmony-init -n harmony -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'

# View job logs
kubectl logs job/harmony-init -n harmony

# Check job events
kubectl get events --field-selector involvedObject.name=harmony-init -n harmony
```

> [!NOTE]
> If secrets already exist then they must be deleted with `kubectl delete secret` prior to being recreated.
> 
## Secret Creation Examples

```bash
# Create license file secret
kubectl create secret generic cleo-license -n harmony \
  --from-file=cleo-license=secrets/license-key.txt

# Create license verification code secret
kubectl create secret generic cleo-license-verification-code -n harmony \
  --from-literal=cleo-license-verification-code='YOUR_VERIFICATION_CODE'

# Create default admin password secret
kubectl create secret generic cleo-default-admin-password -n harmony \
  --from-literal=cleo-default-admin-password='YOUR_ADMIN_PASSWORD'

# Create system settings secret
kubectl create secret generic cleo-system-settings -n harmony \
  --from-file=cleo-system-settings=secrets/system-settings.yaml

# Create log system secret (OPTIONAL)
kubectl create secret generic cleo-log-system -n harmony \
  --from-file=cleo-log-system=secrets/log-system.yaml

# Create config repository secret
kubectl create secret generic cleo-config-repo -n harmony \
  --from-file=cleo-config-repo=secrets/config-repo.yaml

# Create runtime repository secret
kubectl create secret generic cleo-runtime-repo -n harmony \
  --from-file=cleo-runtime-repo=secrets/runtime-repo.yaml

# Verify secrets were created correctly
kubectl get secrets -n harmony

# View contents of each individual secret
kubectl get secret cleo-license -n harmony  -o jsonpath='{.data.cleo-license}' | base64 --decode
kubectl get secret cleo-license-verification-code -n harmony -o jsonpath='{.data.cleo-license-verification-code}' | base64 --decode
kubectl get secret cleo-default-admin-password -n harmony  -o jsonpath='{.data.cleo-default-admin-password}' | base64 --decode
kubectl get secret cleo-system-settings -n harmony  -o jsonpath='{.data.cleo-system-settings}' | base64 --decode
kubectl get secret cleo-log-system -n harmony  -o jsonpath='{.data.cleo-log-system}' | base64 --decode
kubectl get secret cleo-config-repo -n harmony -o jsonpath='{.data.cleo-config-repo}' | base64 --decode
kubectl get secret cleo-runtime-repo -n harmony -o jsonpath='{.data.cleo-runtime-repo}' | base64 --decode
```

## Important Notes

- This chart is designed for **initial setup only** - it can safely be deleted once the job has run to completion
- Running the job multiple times may overwrite existing configuration
- Always backup configuration before re-running initialization
- Document your specific configuration values and secret creation process
