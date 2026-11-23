locals {
  # Static IP if configured, otherwise the DHCP address reported by the QEMU guest agent
  vm_ips  = { for name, vm in module.vm : name => vm.ip_address }
  ssh_key = trimsuffix(var.ssh_public_key_path, ".pub")
}

output "vm_ips" {
  description = "IP address of each VM"
  value       = local.vm_ips
}

output "vm_ids" {
  description = "Proxmox VMID of each VM"
  value       = { for name, vm in module.vm : name => vm.vm_id }
}

output "vm_macs" {
  description = "MAC address of each VM"
  value       = { for name, vm in module.vm : name => vm.mac_address }
}

output "ssh_commands" {
  description = "Ready-to-use SSH commands"
  value       = { for name, ip in local.vm_ips : name => "ssh -i ${local.ssh_key} ${var.vm_username}@${ip}" }
}

output "ansible_inventory_file" {
  description = "Inventory written for Ansible"
  value       = abspath(local_file.ansible_inventory.filename)
}
