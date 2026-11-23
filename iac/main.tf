locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

# One module call, instantiated once per entry in var.vms.
module "vm" {
  source   = "./modules/proxmox-vm"
  for_each = var.vms

  name           = each.key
  vm_id          = each.value.vm_id
  role           = each.value.role
  node_name      = var.node_name
  pool_id        = var.pool_id
  datastore_id   = var.datastore_id
  template_vm_id = var.template_vm_id

  cpu_type  = var.cpu_type
  cores     = coalesce(each.value.cores, var.default_cores)
  memory_mb = coalesce(each.value.memory_mb, var.default_memory_mb)
  disk_gb   = coalesce(each.value.disk_gb, var.default_disk_gb)

  network_bridge = var.network_bridge
  ip_address     = each.value.ip
  cidr_prefix    = var.network_cidr_prefix
  gateway        = var.gateway
  dns_servers    = var.dns_servers

  username       = var.vm_username
  password       = var.vm_password
  ssh_public_key = local.ssh_public_key
}
