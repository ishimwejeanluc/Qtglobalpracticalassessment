resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  description = "${var.role} - managed by Terraform"
  tags        = ["exam", "terraform", var.role]
  node_name   = var.node_name
  vm_id       = var.vm_id
  pool_id     = var.pool_id

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.node_name
    datastore_id = var.datastore_id
    full         = true
  }

  # QEMU guest agent: Terraform reads the DHCP-assigned IPs through it.
  # Requires VM.GuestAgent.Audit on the API token.
  agent {
    enabled = true
    timeout = "5m"
  }
  stop_on_destroy = true

  cpu {
    sockets = 1
    cores   = var.cores
    type    = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_gb
    iothread     = true
    discard      = "on"
  }

  # The template still has the installer ISO on ide2: eject it.
  cdrom {
    interface = "ide2"
    file_id   = "none"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Cloud-init: hostname = VM name, DHCP (or static IP), user + SSH key.
  initialization {
    datastore_id = var.datastore_id
    interface    = "ide0"

    ip_config {
      ipv4 {
        address = var.ip_address == null ? "dhcp" : "${var.ip_address}/${var.cidr_prefix}"
        gateway = var.ip_address == null ? null : var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.username
      password = var.password
      keys     = [var.ssh_public_key]
    }
  }

  started = true
  on_boot = true

  lifecycle {
    # Cloud-init only applies on first boot; avoid needless diffs afterwards.
    ignore_changes = [initialization[0].user_account]
  }
}
