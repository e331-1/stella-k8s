
variable "secret_config" {
  sensitive = true
  type = object({
    
    proxmox_password = string
    oidc_client_secret = string
    device_client_secret = string
  })
}
variable "config" {
  type = object({
    proxmox_endpoint = optional(string, "https://192.168.0.100:8006/")
    proxmox_username = optional(string, "root@pam")
    proxmox_clustername = optional(string, "stella")
    node_name = optional(string, "stella-01")
    node_ip = optional(string, "10.0.1.2")
    oidc_client_id = optional(string)
    oidc_issuer_url = optional(string, "https://accounts.google.com")
    vm_id = optional(string, "200")
    vm_name = optional(string, "talos-single")
  })
}