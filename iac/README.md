# Task 1: Proxmox VMs with Terraform

This folder creates the 4 exam VMs on Proxmox: one Docker host and three Kubernetes nodes. Terraform also writes the Ansible inventory, using the IP each VM got from DHCP.

| VM ID | Name | Role | CPU / RAM / Disk | IP (DHCP) |
|---|---|---|---|---|
| 4101 | `c3-docker-host` | Docker Compose host | 4 / 4 GiB / 30 GB | 192.168.160.90 |
| 4102 | `c3-k8s-master` | Kubernetes control plane | 4 / 4 GiB / 30 GB | 192.168.160.95 |
| 4103 | `c3-k8s-worker-1` | Kubernetes worker | 4 / 4 GiB / 30 GB | 192.168.160.93 |
| 4104 | `c3-k8s-worker-2` | Kubernetes worker | 4 / 4 GiB / 30 GB | 192.168.160.92 |

Environment: Proxmox node `Server1`, pool `exam-c1`, storage `local-lvm`, template VMID `9000` (Ubuntu 24.04 with cloud-init), bridge `vmbr0`, provider `bpg/proxmox ~> 0.69`.

## Files

| File | Purpose |
|---|---|
| `versions.tf` | Terraform ≥ 1.5, the `bpg/proxmox` and `hashicorp/local` providers |
| `provider.tf` | Proxmox API endpoint and API token (the token secret comes from a variable, never from a file in Git) |
| `variables.tf` | Every setting has a variable and a default: endpoint, node, pool, storage, template, network, VM user, SSH key, sizing, and the `vms` map |
| `main.tf` | One `module "vm"` block, repeated with `for_each` over the `vms` map. No VM is written out twice |
| `modules/proxmox-vm/` | **Reusable module** for one VM: clone, CPU, RAM, disk, NIC, cloud-init, guest agent. Returns the VM's IP |
| `inventory.tf` + `templates/hosts.ini.tftpl` | Writes `../ansible/inventory/hosts.ini` from the real IPs |
| `outputs.tf` | `vm_ips`, `vm_ids`, `vm_macs`, `ssh_commands`, `ansible_inventory_file` |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` (git-ignored) |

## What the module configures

- **Clone:** a full clone of template 9000 on `Server1`, in pool `exam-c1`. The disk is on `local-lvm`, resized to 30 GB.
- **CPU type `x86-64-v3`:** MongoDB 5+ needs the AVX instructions. With the default CPU type, MongoDB exits with code 132.
- **Cloud-init:**
  - sets the hostname to the VM name;
  - creates the user `devops` with the SSH public key and a password;
  - uses `ip=dhcp`, or a static IP if `ip` is set for that VM in the map.
- **QEMU guest agent:** enabled. Terraform waits until the VM reports its IP, so the outputs and the inventory always contain real, usable addresses.

**Why DHCP?** The exam environment gives the IPs out by DHCP. Terraform doesn't guess addresses: it reads them from the guest agent. The Proxmox token needs the `VM.GuestAgent.Audit` permission for this.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars    # set vm_password; keep the file out of Git
export TF_VAR_proxmox_api_token_secret='...'    # or put it in terraform.tfvars

terraform init
terraform fmt -check && terraform validate
terraform plan
terraform apply
terraform output vm_ips
terraform output ssh_commands
```

Re-running `terraform plan` on the running VMs reports **"No changes"**.

## Verify

```bash
terraform output vm_ips                                     # 4 IPs
cat ../ansible/inventory/hosts.ini                          # same IPs, grouped for Ansible
cd ../ansible && ansible all -m ping                        # SSH works on all 4
ansible all -a 'hostname'                                   # names match
ansible all -a 'lsb_release -ds'                            # Ubuntu 24.04 LTS
ansible all -m shell -a 'nproc; free -h | grep Mem; lsblk -dn -o NAME,SIZE'   # 4 CPU, ~4 GiB, 30G disk
```

## Add or change a VM

Edit the `vms` map in `terraform.tfvars`, for example to add a worker:
```hcl
"c3-k8s-worker-3" = { vm_id = 4105, role = "k8s-worker" }
```
`cores`, `memory_mb`, `disk_gb` and `ip` can be set per VM. Without them, the defaults from `variables.tf` are used. Run `terraform apply`, and the inventory is regenerated automatically.
