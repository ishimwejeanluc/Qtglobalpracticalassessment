# ---------- Proxmox connection ----------
variable "proxmox_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
  default     = "https://192.168.160.16:8006/"
}

variable "proxmox_api_token_id" {
  description = "API token ID (user@realm!tokenname)"
  type        = string
  default     = "candidate1@pve!exam"
}

variable "proxmox_api_token_secret" {
  description = "API token secret. Pass via TF_VAR_proxmox_api_token_secret, never commit it."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (Proxmox uses a self-signed certificate)"
  type        = bool
  default     = true
}

# ---------- Placement ----------
variable "node_name" {
  type    = string
  default = "Server1"
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "pool_id" {
  type    = string
  default = "exam-c1"
}

variable "template_vm_id" {
  description = "VMID of the Ubuntu 24.04 template to clone"
  type        = number
  default     = 9000
}

# ---------- Network ----------
variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_cidr_prefix" {
  description = "Prefix length of the LAN (192.168.160.0/24)"
  type        = number
  default     = 24
}

variable "gateway" {
  type    = string
  default = "192.168.160.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["8.8.8.8", "1.1.1.1"]
}

# ---------- VM login (cloud-init) ----------
variable "vm_username" {
  description = "Login user created on every VM by cloud-init"
  type        = string
  default     = "devops"
}

variable "vm_password" {
  description = "Password for vm_username (console/SSH fallback for examiners)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Public key injected into vm_username's authorized_keys"
  type        = string
  default     = "~/.ssh/qt_exam_ed25519.pub"
}

# ---------- Ansible hand-off ----------
variable "ansible_inventory_path" {
  description = "Where to write the generated Ansible inventory (relative to iac/)"
  type        = string
  default     = "../ansible/inventory/hosts.ini"
}

# ---------- VM sizing defaults ----------
variable "cpu_type" {
  description = "QEMU CPU model for all VMs (x86-64-v3 = AVX/AVX2, needed by MongoDB >= 5)"
  type        = string
  default     = "x86-64-v3"
}

variable "default_cores" {
  type    = number
  default = 4
}

variable "default_memory_mb" {
  type    = number
  default = 4096
}

variable "default_disk_gb" {
  type    = number
  default = 30
}

# ---------- The VMs ----------
variable "vms" {
  description = <<-EOT
    VMs to create. Key = VM name / hostname.
    ip is optional: omit it to use DHCP, or set a static IPv4 address.
    cores/memory_mb/disk_gb are optional overrides.
  EOT
  type = map(object({
    vm_id     = number
    role      = string
    ip        = optional(string)
    cores     = optional(number)
    memory_mb = optional(number)
    disk_gb   = optional(number)
  }))

  validation {
    condition     = alltrue([for vm in values(var.vms) : vm.ip == null || can(cidrhost("${vm.ip}/32", 0))])
    error_message = "vms[*].ip must be omitted (DHCP) or be a valid IPv4 address."
  }
}
