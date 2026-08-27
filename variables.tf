variable "proxmox_endpoint" {
  type    = string
  default = "https://192.168.0.100:8006/"
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_clustername" {
  type      = string
  default = "stella"
}

variable "node_name" {
  type    = string
  default = "stella-01" # Proxmoxのノード名
}

variable "node_ip" {
  type    = string
  default = "10.0.1.2" # VMに割り当てるIP
}

variable "gateway_ip" {
  type    = string
  default = "10.0.1.1"
}

variable "environment" {
  type        = string
  description = "デプロイ環境 (production または development)"
  default     = "development"

  validation {
    condition     = contains(["production",  "development"], var.environment)
    error_message = "environment は 'production' または 'development' を指定してください。"
  }
}

# variable "cloudflare_api_token" {
#   type      = string
#   sensitive = true
  
# }

variable "vm_name" {
  type    = string
  default = "talos-single"
}


variable "oidc_client_id" {
  type    = string
}

variable "oidc_client_secret" {
    type      = string
    sensitive = true
}

variable "device_client_secret" {
  type      = string
  sensitive = true
}

variable "oidc_issuer_url" {
  type    = string
  default = "https://accounts.google.com"
}
