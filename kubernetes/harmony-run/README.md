# Harmony Runtime Helm Chart

Deployment of Harmony application runtime instances.

## Table of Contents

- [Overview](#overview)
- [Chart Structure](#chart-structure)
- [Values Configuration](#values-configuration)
  - [Platform-Specific Configuration](#platform-specific-configuration)
  - [Example Configuration](#example-configuration)
  - [Protocol Support](#protocol-support)
- [Prerequisites](#prerequisites)
  - [Kubernetes Requirements](#kubernetes-requirements)
  - [Required Secrets](#required-secrets)
  - [Infrastructure Requirements](#infrastructure-requirements)
- [Deployment](#deployment)
- [Accessing the Harmony Admin UI](#accessing-the-harmony-admin-ui)
- [Quick Commands](#quick-commands)
  - [Chart Management](#chart-management)
  - [Service Verification](#service-verification)
  - [Troubleshooting](#troubleshooting)
- [Important Notes](#important-notes)
  - [Scaling Considerations](#scaling-considerations)

## Overview

The `harmony-run` Helm chart provides a production-ready deployment of Harmony runtime instances on Kubernetes. Harmony is a CLEO integration platform that handles various communication protocols for enterprise data exchange.

The chart creates:

- **StatefulSet**: Manages Harmony runtime instances with persistent identities and ordered deployment
- **Headless Service**: Enables internal service discovery and communication between instances
- **Load Balancer Service**: Provides external access with session affinity and protocol-specific port configuration
- **Secret Management**: Securely mounts licensing and configuration secrets
- **Persistent Storage**: Optional shared storage for configuration files and data persistence

The chart supports:

- **Multi-Protocol**: FTP, SFTP, HTTP/HTTPS, AS2, SMTP, OFTP with configurable port mappings
- **High Availability**: Multiple runtime instances with session affinity
- **Cloud Integration**: AWS, Azure, and GCP load balancer optimizations
- **Security**: Encrypted secret mounting and network policy support

## Chart Structure

```text
harmony-run/
├── Chart.yaml              # Chart metadata and version info
├── values.yaml             # Default configuration values
├── values.example.yaml     # Example configuration with detailed comments
├── README.md               # This documentation
└── templates/              # Kubernetes resource templates
    ├── _helpers.tpl        # Template helper functions
    ├── statefulset.yaml    # StatefulSet resource template
    └── service.yaml        # Service resources template
```

## Values Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Global Settings** | | |
| `global.namespace` | Target namespace for all resources | `harmony` |
| `global.platform` | **[REQUIRED]** Cloud platform (`aws`, `azure`, or `gcp`) | *None* |
| **Image Configuration** | | |
| `harmony.image.name` | Container name in the pod | `harmony` |
| `harmony.image.repository` | Docker image repository | `cleodev/harmony` |
| `harmony.image.tag` | Image tag (use specific versions in production) | `PR-11140` |
| `harmony.image.pullPolicy` | Image pull policy (Always, IfNotPresent, Never) | `Always` |
| **StatefulSet Configuration** | | |
| `harmony.statefulset.replicas` | Number of Harmony runtime instances | `2` |
| `harmony.statefulset.ordinalStart` | Starting ordinal number for pod naming | `1` |
| **Environment Variables** | | |
| `harmony.env.systemName` | Name of this Harmony system (group of instances) | `System1` |
| `harmony.env.secretsMountPoint` | Location where secrets will be mounted | `/var/secrets` |
| **Resource Configuration** | | |
| `harmony.resources.requests.memory` | Memory request per instance | `4096Mi` |
| `harmony.resources.limits.memory` | Memory limit per instance | `8192Mi` |
| **Volume Configuration** | | |
| `harmony.volumes.secrets.sources` | Array of secret sources to mount | 4 secrets (see below) |
| **Headless Service** | | |
| `service.headless.enabled` | Enable headless service for internal communication | `true` |
| `service.headless.name` | Name of the headless service | `harmony-service` |
| **Load Balancer Service** | | |
| `service.loadBalancer.enabled` | Enable external load balancer service | `true` |
| `service.loadBalancer.name` | Name of the load balancer service | `harmony` |
| `service.loadBalancer.type` | Service type (LoadBalancer, NodePort, ClusterIP) | `LoadBalancer` |
| `service.loadBalancer.sessionAffinity` | Session affinity setting for connection persistence | `ClientIP` |
| `service.loadBalancer.externalTrafficPolicy` | Traffic policy (Local, Cluster) | `Local` |
| **Protocol Ports** | | |
| `service.loadBalancer.ports[].name` | Port identifier (admin, http, https, sftp, etc.) | Various |
| `service.loadBalancer.ports[].port` | External port number | Various |
| `service.loadBalancer.ports[].targetPort` | Container port number | Various |
| `service.loadBalancer.ports[].enabled` | Enable/disable specific port | Various |
| **FTP Passive Ports** | | |
| `service.loadBalancer.passiveFtp.enabled` | Enable FTP passive data ports | `false` |
| `service.loadBalancer.passiveFtp.passivePorts[]` | Array of passive port configurations | 10 ports (25900-25909) |
| **Persistence Configuration** | | |
| `persistence.enabled` | Enable persistent storage mounting | `true` |
| `persistence.claimName` | Name of the PersistentVolumeClaim | `harmony-pvc` |
| `persistence.mountPath` | Mount point in the harmony file system | `/shared-config` |

> [!NOTE]
> Default values are contained in the [values.yaml](values.yaml) file.

### Platform-Specific Configuration

The chart supports automatic configuration for different cloud platforms through the `global.platform` setting:

#### AWS Configuration
When `global.platform: aws` (default), the following load balancer annotations are automatically applied:
- `service.beta.kubernetes.io/aws-load-balancer-type: external`
- `service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing`
- `service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: instance`
- `service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"`
- `service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "preserve_client_ip.enabled=true,stickiness.enabled=true,stickiness.type=source_ip"`

#### Azure Configuration
When `global.platform: azure`, the following load balancer annotations are automatically applied:
- `service.beta.kubernetes.io/azure-load-balancer-client-ip: "true"`

#### GCP Configuration
When `global.platform: gcp`, the GKE load balancer is used with default settings. No special annotations are required as GKE automatically provides:
- Network Load Balancer with source IP preservation
- Session affinity support via `sessionAffinity: ClientIP`
- Cross-zone load balancing

#### Usage Examples
```yaml
# For AWS deployment
global:
  platform: aws

# For Azure deployment
global:
  platform: azure

# For GCP deployment
global:
  platform: gcp
```

> [!TIP]
> See [values.example.yaml](values.example.yaml) for comprehensive configuration examples including protocol settings, resource allocation, and cloud-specific configurations.

### Example Configuration

```yaml
# my-values.yaml
global:
  namespace: harmony
  platform: aws  # REQUIRED: must be 'aws', 'azure', or 'gcp'

harmony:
  image:
    name: harmony
    repository: cleodev/harmony
    tag: "v1.2.3"  # Use specific version in production
    pullPolicy: IfNotPresent

  statefulset:
    replicas: 2  # Scale for high availability
    ordinalStart: 1

  env:
    systemName: "Production-System"
    secretsMountPoint: "/var/secrets"

  resources:
    requests:
      memory: "4096Mi"  # Adjust based on load
    limits:
      memory: "8192Mi"

  volumes:
    secrets:
      sources:
        - secretName: cleo-license
        - secretName: cleo-license-verification-code
        - secretName: cleo-config-repo
        - secretName: cleo-runtime-repo
        - secretName: cleo-log-system
          optional: true

service:
  headless:
    enabled: true
    name: harmony-service

  loadBalancer:
    enabled: true
    name: harmony
    type: LoadBalancer
    sessionAffinity: ClientIP
    externalTrafficPolicy: Local
    
    # Enable protocols based on requirements
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
  enabled: false
  claimName: "harmony-pvc"
  mountPath: "/shared-config"
```

> [!NOTE]
> If Kubernetes persistent storage is being used then set the `persistence.enabled` value to `true`.

### Protocol Support

The chart supports multiple enterprise communication protocols:

- **Admin Console** (Port 5080): Web-based administration console
- **HTTP/HTTPS** (Ports 80/443): Web-based file transfer and API access
- **FTP** (Ports 20/21): File Transfer Protocol with optional passive mode
- **SFTP** (Port 22): Secure File Transfer Protocol over SSH
- **OFTP** (Ports 3305/6619): Odette File Transfer Protocol (standard and TLS)
- **SMTP** (Ports 25/587/465): Simple Mail Transfer Protocol variants

Enable only the protocols you need for security and resource efficiency.

**⚠️  Critical:** If any changes are made via the admin console to port enablement and/or port values/ranges, then the chart must be updated with the new values in order to open up the protocols/ports on the load balancer. The only port open by default is for the admin console (5080). Additionally, if FTP is enabled then the configured passive port range must match those in the values file.

> [!NOTE]
> The maximum number of open ports allowed on an AWS load balancer is 50, keep this number in mind when enabling protocols and FTP passive mode ranges.

## Prerequisites

### Kubernetes Requirements
- Kubernetes cluster version >= 1.19.0
- Helm 3.x installed
- `kubectl` configured for your cluster
- Target namespace must exist (default: `harmony`)
- Sufficient cluster resources for the configured number of replicas

### Required Secrets

Before installing this chart, you must create the following secrets in the target namespace. These secrets should be created as described in the [Secret Creation Examples](../harmony-init/README.md#secret-creation-examples).

[!NOTE]
> The `cleo-log-system` secret is optional. If not provided, Harmony will use default logging configuration. The chart will continue to function without this secret.

### Required Secrets (4)

| Secret Name | Description | Contents |
|-------------|-------------|----------|
| `cleo-license` | Harmony license file | Contains the typical `license_key.txt` file used with Harmony |
| `cleo-license-verification-code` | License verification code | The verification code used to validate the license key |
| `cleo-config-repo` | Static configuration repository | Repository configuration files for accessing static config |
| `cleo-runtime-repo` | Runtime configuration repository | Repository configuration files for accessing runtime config |

### Optional Secrets (1)

| Secret Name | Description | Contents |
|-------------|-------------|----------|
| `cleo-log-system` | Log system settings configuration | YAML file containing log system settings for Harmony |

### Infrastructure Requirements

- **Load Balancer**: Cloud provider must support LoadBalancer services (AWS ELB/NLB, Azure Load Balancer, GCP Load Balancer)
- **Persistent Storage**: If persistence is enabled, ensure PVC can be created or already exists
- **Network Security**: Configure security groups/firewall rules for enabled protocol ports
- **Resource Capacity**: Ensure cluster has sufficient CPU and memory for the configured replicas

## Deployment

> **Tip:** Copy and customize the example values file:
> ```bash
> cp values.example.yaml my-values.yaml
> # Edit my-values.yaml with your configuration (especially global.platform)
> helm install harmony-runtime . -f my-values.yaml -n harmony
> ```

1. Customize configuration (copy `values.example.yaml` to `my-values.yaml` and edit)
2. Set `global.platform` in `my-values.yaml` (required: `aws`, `azure`, or `gcp`)
3. Install: `helm install harmony-runtime . -f my-values.yaml -n harmony`
4. Monitor: `kubectl wait --for=condition=ready pod -l app=harmony -n harmony --timeout=600s`
5. Get endpoint: `kubectl get svc harmony -n harmony`

## Accessing the Harmony Admin UI

Once the deployment is complete and the load balancer is provisioned, you can access the Harmony Admin UI through your web browser.

1. **Get the Load Balancer Address**:
   ```bash
   kubectl get svc harmony -n harmony -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   # Or for IP-based load balancers:
   kubectl get svc harmony -n harmony -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. **Access the Admin UI**:
   Open your browser and navigate to:
   ```
   http://<load-balancer-address>:5080/Harmony
   ```

   For example:
   - Using DNS: `http://harmony.example.com:5080/Harmony`
   - Using IP: `http://192.168.1.100:5080/Harmony`

> [!NOTE]
> The Admin UI port (5080) must be enabled in your `values.yaml` configuration. This is enabled by default.

> [!TIP]
> If you have configured a custom DNS name pointing to your load balancer, use that for easier access. You may also want to configure HTTPS for production environments.

## Quick Commands

```bash
# Scale
kubectl scale statefulset harmony --replicas=3 -n harmony

# Get load balancer endpoint
kubectl get svc harmony -n harmony

# Access admin console locally (port forwarding)
kubectl port-forward svc/harmony 5080:5080 -n harmony
# Open: http://localhost:5080/Harmony

# View logs
kubectl logs harmony-1 -n harmony --tail=50
```

> **Tip:** See the [main README Quick Reference](../README.md#quick-reference-cheat-sheet) for comprehensive command examples.

### Chart Management
```bash
# Install chart with values file (ensure platform is set in my-values.yaml)
helm install harmony-runtime . -f my-values.yaml -n harmony

# Install for AWS with inline overrides
helm install harmony-runtime . -f my-values.yaml -n harmony \
  --set global.platform=aws

# Install for Azure with inline overrides
helm install harmony-runtime . -f my-values.yaml -n harmony \
  --set global.platform=azure

# Install for Google with inline overrides
helm install harmony-runtime . -f my-values.yaml -n harmony \
  --set global.platform=gcp

# Upgrade chart
helm upgrade harmony-runtime . -f new-values.yaml -n harmony

# Uninstall chart
helm uninstall harmony-runtime -n harmony

# Check chart status
helm status harmony-runtime -n harmony

# View chart values
helm get values harmony-runtime -n harmony

# Dry run installation
helm install harmony-runtime . -f my-values.yaml --dry-run --debug -n harmony
```

### Service Verification
```bash
# Check services
kubectl get svc -n harmony

# Check service endpoints
kubectl get endpoints -n harmony

# Test admin port connectivity
kubectl port-forward svc/harmony 5080:5080 -n harmony
```

After port forwarding you can visit the admin console at http://localhost:5080

### Troubleshooting
```bash
# Check StatefulSet events
kubectl describe statefulset harmony -n harmony

# Check pod events
kubectl describe pod harmony-1 -n harmony

# Check service configuration
kubectl describe svc harmony -n harmony

# Verify secret mounts
kubectl exec harmony-1 -n harmony -- ls -la /var/secrets

# Check persistent volume (if enabled)
kubectl describe pvc harmony-pvc -n harmony

# View all resources
kubectl get all -n harmony
```

## Important Notes

### Scaling Considerations

- Instances are created with ordered, persistent identities (harmony-1, harmony-2, etc.)
- ClientIP affinity ensures clients connect to the same instance
- Each instance requires significant memory (default 4-8GB)
- Load balancer distributes connections across healthy instances
- Shared persistent storage ensures configuration consistency
