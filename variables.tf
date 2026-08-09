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
  description = "デプロイ環境 (production または staging)"
  default     = "staging"

  validation {
    condition     = contains(["production", "staging"], var.environment)
    error_message = "environment は 'production' または 'staging' を指定してください。"
  }
}