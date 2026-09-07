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



resource "kubectl_manifest" "patch_proxmox_ccm" {
  yaml_body = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: proxmox-cloud-controller-manager
  namespace: kube-system
spec:
  template:
    spec:
      containers:
        - name: proxmox-cloud-controller-manager # コンテナ名を適宜合わせてください
          args:
            - --v=4
            - --cloud-provider=proxmox
            - --cloud-config=/etc/proxmox/config.yaml
            - --controllers=cloud-node,cloud-node-lifecycle
            - --leader-elect-resource-name=cloud-controller-manager-proxmox
            - --use-service-account-credentials
            - --secure-port=10258
            - --authorization-always-allow-paths=/healthz,/livez,/readyz,/metrics

            - "--controllers=*"
YAML

  # すでにあるリソースを上書き・パッチ統合する設定
  force_new      = false
  server_side_apply = true
  
  # 強制的に競合を解消して上書き適用する設定を追加
  force_conflicts = true

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



