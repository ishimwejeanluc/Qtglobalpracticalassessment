# Inputs for ONE Ubuntu VM cloned from a Proxmox template and configured by cloud-init.

variable "name" {
  description = "VM name (also becomes the hostname via cloud-init)"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VMID"
  type        = number
}

variable "role" {
  description = "Free-text role, used in the description and tags"
  type        = string
}

variable "node_name" {
  type = string
}

variable "pool_id" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "template_vm_id" {
  type = number
}

variable "cpu_type" {
  description = "QEMU CPU model. x86-64-v3 exposes AVX/AVX2 (required by MongoDB >= 5)"
  type        = string
  default     = "x86-64-v3"
}

variable "cores" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 4096
}

variable "disk_gb" {
  type    = number
  default = 30
}

variable "network_bridge" {
  type = string
}

variable "ip_address" {
  description = "Static IPv4 address without prefix, or null for DHCP"
  type        = string
  default     = null
}

variable "cidr_prefix" {
  type = number
}

variable "gateway" {
  type = string
}

variable "dns_servers" {
  type = list(string)
}

variable "username" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type = string
}
