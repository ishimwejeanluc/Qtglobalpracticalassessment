# Hand-off to Ansible: write the inventory from the real VM IPs, so nothing is copied by hand.
# Re-running `terraform apply` rewrites the file only when an IP or VM changes.

locals {
  hosts_by_role = {
    for role in distinct([for vm in var.vms : vm.role]) :
    role => { for name, vm in var.vms : name => local.vm_ips[name] if vm.role == role }
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.root}/${var.ansible_inventory_path}"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    hosts_by_role   = local.hosts_by_role
    ssh_user        = var.vm_username
    ssh_private_key = local.ssh_key
  })
}
