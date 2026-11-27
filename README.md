# Homelab

A single-host homelab for learning.

## Architecture

### Hardware

| Component | Details |
|---|---|
| System | ASUS ROG G700TF desktop server |
| Operating system | Ubuntu Linux |
| Processor | Intel Core Ultra 5 225F |
| Memory | 16 GB |
| Primary storage | 1 TB NVMe |
| GPU | NVIDIA GeForce RTX 5060 with 8 GB VRAM |

### Software

| Component | Responsibility |
|---|---|
| Ansible | Host provisioning and configuration |
| K3s | Single-node Kubernetes distribution |
| Helm | Application packaging and release management |
| Kustomize | Native Kubernetes resource composition |
| MetalLB | Load balancing for services on the local network |
| Prometheus, Alertmanager, and Grafana | Metrics, alerting, and dashboards |
| Zot | Private OCI registry |
| NVIDIA runtime | GPU-enabled workloads and experiments |
