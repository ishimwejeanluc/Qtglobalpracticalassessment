output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "ip_address" {
  description = "Static IP if configured, otherwise the first non-loopback IPv4 reported by the guest agent"
  value = coalesce(
    var.ip_address,
    try([for ip in flatten(proxmox_virtual_environment_vm.this.ipv4_addresses) : ip if !startswith(ip, "127.")][0], null),
    "unknown"
  )
}

output "mac_address" {
  description = "MAC address of the first NIC"
  value       = proxmox_virtual_environment_vm.this.network_device[0].mac_address
}
