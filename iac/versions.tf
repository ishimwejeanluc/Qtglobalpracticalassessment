terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
