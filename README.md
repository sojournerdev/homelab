# Homelab

A personal, single-host homelab for learning Kubernetes and infrastructure
engineering through practical experimentation.

## Architecture

### Host

| Component | Details |
|---|---|
| System | ASUS ROG G700TF desktop server |
| Operating system | Ubuntu Linux |
| Processor | Intel Core Ultra 5 225F |
| Memory | 16 GB |
| Primary storage | 1 TB NVMe |
| GPU | NVIDIA GeForce RTX 5060 with 8 GB VRAM |

### Platform

| Component | Responsibility |
|---|---|
| Ansible | Host provisioning and configuration |
| K3s | Single-node Kubernetes distribution |
| Helm | Application packaging and release management |
| Kustomize | Native Kubernetes resource composition |
| MetalLB | Load balancing for services on the local network |
| Prometheus and Alertmanager | Metrics and alerting |
| Zot | Private OCI registry |
| NVIDIA runtime | GPU-enabled workloads and experiments |

The K3s server and agent run together on the host. Applications are managed
through Kubernetes APIs, Helm charts, and Kustomize resources.

## Storage

The host uses the `vg_system` volume group with separate logical volumes for
K3s data and workload storage:

| Logical volume | Mount point | Purpose |
|---|---|---|
| `lv_cluster` | `/var/lib/rancher/k3s` | K3s data and container runtime state |
| `lv_workloads` | `/var/lib/rancher/k3s/storage` | Local-path persistent workload volumes |

Both volumes are 150 GiB ext4 filesystems. Remaining volume-group capacity is
reserved for future expansion.
