# The token secret is never written in a file: export it before running terraform
#   export TF_VAR_proxmox_api_token_secret='xxxxxxxx-xxxx-...'
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_insecure
}
