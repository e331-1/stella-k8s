terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.config.proxmox_endpoint
  username = var.config.proxmox_username
  password = var.secret_config.proxmox_password
  insecure = true # 自己署名証明書の場合
}