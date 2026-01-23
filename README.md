# Cleo Harmony Containerization

In the context of Cleo Harmony, containerization refers to packaging Harmony services into lightweight, portable containers using Docker and orchestrated via Kubernetes or another platform, resulting in faster deployments and scalable infrastructure.

This document outlines requirements, and containerization specific platform instructions.

> [!NOTE]
> Currently, the only supported containerization platform is Kubernetes. See the [kubernetes](kubernetes/) directory for detailed deployment documentation.

## Requirements

Before you deploy Harmony in a containerized environment, certain requirements must be met to ensure that the system is properly licensed, has access to necessary configuration and runtime resources, and can operate properly in your environment.

### Enterprise License

A Harmony Enterprise license is required when running the product within containers. Please contact your Cleo sales representative for more information.

### Shared Repositories

Two shared, persisted, centralized repositories are required -- one for configuration and one for runtime.

#### Configuration Repository

Harmony creates a subdirectory under the base path using the system name. This directory stores configuration files shared across all nodes in the cluster, including hosts, options, certificates, and more.

**Supported repository types:** `smb`, `s3`, `azureblob`, `gcpbucket`

#### Runtime Repository

Each Harmony node creates a parent subdirectory using the system name (if not already present), with a child subdirectory named after the host. This directory stores node-specific runtime files, primarily protocol message IDs and receipts.

**Supported repository types:** `smb`

### Access to cleo.com

Each Harmony container verifies the enterprise license at startup. To do this, https://license.cleo.com must be accessible from the container.

If license.cleo.com is not accessible at startup, Harmony will still start up and periodically retry license verification. However, a 4-day grace period is initiated. If the license is not verified during this period, the container will exit. In case the problem reaching license.cleo.com is on Cleo's side, an internal IT ticket is created for the enterprise license's serial number by posting to https://it-ticket.cleo.com.

Harmony will email the system administrator if the grace period is initiated. Therefore, Cleo strongly recommends setting the system administrator email address and the necessary SMTP proxy.

### Resource Requirements

Refer to the latest Harmony release system requirements: [Cleo Harmony 5.8.1 System Requirements](https://documentation.cleo.com/harmony/5.8.1/Content/SystemRequirements.htm).

### VLProxy

If you're using Cleo VLProxy within your network, note that VLProxy itself is not containerized and its setup remains the same. The only difference when configuring it for a Harmony container cluster is in the **VLProxy Serial Numbers** property. Instead of specifying a static serial number, use a regular expression.

For example, if your Enterprise license serial number is `HC1234-ZZ5678`, set the VLProxy Serial Numbers property to `HC1234-ZZ5678-.*` to match relevant container instances.

## Setting Up a Harmony Container

Setting up a Harmony container involves several key steps to ensure the environment is properly initialized, securely configured, and ready for operation. See the platform sections below for platform specfic instructions.

The following diagram illustrates the Harmony containerization environment:

![Harmony Containerization Overview](https://raw.githubusercontent.com/wiki/cleo/harmony-containerization/images/Harmony_C14n_Overview.png)

## Platforms

| Platform | Status |
|----------|--------|
| [Kubernetes](kubernetes/README.md) | Supported |
