# ------------------------------------------------------------------------------
# CCMのインストール
# ------------------------------------------------------------------------------

resource "proxmox_virtual_environment_role" "ccm" {
  role_id = "CCM"

  privileges = [
    "Sys.Audit",
    "VM.Audit",
    "VM.GuestAgent.Audit",
  ]
}

import {
  to = proxmox_virtual_environment_role.ccm
  id = "CCM"
}

resource "proxmox_virtual_environment_user" "kubernetes" {

  comment = "Kubernetes"
  user_id = "kubernetes${var.environment == "production" ? "" : "-dev"}@pve"
}

# ユーザー自身への ACL は分離して定義する
resource "proxmox_virtual_environment_acl" "user_ccm" {
  user_id   = proxmox_virtual_environment_user.kubernetes.user_id
  role_id   = proxmox_virtual_environment_role.ccm.role_id
  path      = "/"
  propagate = true
}

resource "proxmox_virtual_environment_user_token" "ccm" {
  comment    = "Kubernetes CCM"
  token_name = "ccm"
  user_id    = proxmox_virtual_environment_user.kubernetes.user_id
}

resource "proxmox_virtual_environment_acl" "ccm" {
  token_id = proxmox_virtual_environment_user_token.ccm.id
  role_id  = proxmox_virtual_environment_role.ccm.role_id

  path      = "/"
  propagate = true
}



resource "null_resource" "patch_proxmox_ccm_deployment" {
  provisioner "local-exec" {
    # ★ --validate=false を追加して余計な OpenAPI スキーマ取得通信によるエラーを防止
   command = "kubectl --kubeconfig=${local_file.kubeconfig.filename} patch deployment proxmox-cloud-controller-manager -n kube-system --type='json' -p='[{\"op\": \"add\",\"path\": \"/spec/template/spec/containers/0/args/-\",\"value\": \"--controllers=*\"}]'"
  }
  depends_on = [
    helm_release.argocd
  ]
}


# ------------------------------------------------------------------------------
# CSIのインストール
# ------------------------------------------------------------------------------

resource "proxmox_virtual_environment_role" "csi" {
  role_id = "Kubernetes-CSI"

  privileges = [
    "VM.Audit",
    "VM.Config.Disk",
    "Datastore.Allocate",
    "Datastore.AllocateSpace",
    "Datastore.Audit",
  ]
}

import {
  to = proxmox_virtual_environment_role.csi
  id = "Kubernetes-CSI"
}


resource "proxmox_virtual_environment_user" "kubernetes-csi" {
  acl {
    path      = "/"
    propagate = true
    role_id   = proxmox_virtual_environment_role.csi.role_id
  }

  comment = "Kubernetes"
  user_id = "kubernetes-csi${var.environment == "production" ? "" : "-dev"}@pve"
}

resource "proxmox_virtual_environment_user_token" "csi" {
  comment    = "Kubernetes CSI"
  token_name = "csi"
  user_id    = proxmox_virtual_environment_user.kubernetes-csi.user_id
}

resource "proxmox_virtual_environment_acl" "csi" {
  token_id = proxmox_virtual_environment_user_token.csi.id
  role_id  = proxmox_virtual_environment_role.csi.role_id

  path      = "/"
  propagate = true
}



