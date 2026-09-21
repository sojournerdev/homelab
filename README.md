# Homelab

A personal homelab for learning, experimenting, and enjoying my passion for
tech outside of work.

## Architecture

### Hardware

| Component | Details |
|---|---|
| Host | ASUS ROG G700TF desktop server |
| Operating system | Ubuntu Linux |
| CPU | Intel Core Ultra 5 225F |
| Memory | 16 GB |
| Storage | 1 TB NVMe |
| GPU | NVIDIA GeForce RTX 5060 with 8 GB VRAM |
| Workstation | macOS system used for administration and development |

### Software

| Component | Responsibility |
|---|---|
| Linux server | Compute, local storage, and cluster host |
| K3s | Container orchestration |
| Flux | Keeps the cluster in sync with Git |
| Ansible | Machine provisioning and configuration |
| GPU runtime | Runs GPU-enabled workloads and AI experiments |
| SOPS and age | Keeps secrets encrypted |

## Limitations

K3s runs on one server, along with the storage and services it hosts. This
keeps the platform simple, but if the server, storage, power, or network goes
down, the services go down with it.
