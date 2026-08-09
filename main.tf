# --- 1. Talosの機密鍵・証明書設定を自動生成 ---
resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "this" {
  cluster_name         = "stella-k8s"
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.node_ip]
}

# データセンターレベルでセキュリティグループを定義
resource "proxmox_virtual_environment_cluster_firewall_security_group" "talos_sg" {
  name    = "talos-nodes"
  comment = "Firewall rules for Talos Linux nodes"
  
  rule {
    type    = "out"
    action  = "REJECT"
    dest    = "192.168.0.0/24"
    comment = "ローカルへのアクセスを禁止"
    enabled = true
  }

}

# --- 2. シングルノード用の Machine Configuration を作成 ---
data "talos_machine_configuration" "controlplane" {
  cluster_name       = "stella-k8s"
  machine_type       = "controlplane"
  cluster_endpoint   = "https://${var.node_ip}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = "v1.36.2"
  talos_version      = "v1.13.8"

  # シングルノード（Taint解除）と静的IP設定をオーバーライド
  config_patches = [
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
      machine = {
        network = {
          nameservers = [
            "1.1.1.1",
            "8.8.8.8" #これがないと10.0.1.1で名前解決しようとする
          ]
          interfaces = [
            {
              interface = "eth0"
              dhcp      = false
              addresses = ["${var.node_ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway_ip
                }
              ]
            }
          ]
        }
      }
    })
  ]
}

# --- 3. Proxmox上に Talos VM を作成 ---
resource "proxmox_virtual_environment_vm" "talos_single" {
  name      = "talos-single"
  node_name = var.node_name
  vm_id     = 200

  agent {
    enabled = true # QEMU Guest Agent
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 6144 # 4GB RAM
  }
  bios = "ovmf" # UEFIブートを有効化
  efi_disk {
    datastore_id = "local-lvm"
    file_format  = "raw"
  }
  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = "local-lvm"
    size         = 20
    interface    = "scsi0"
    file_format  = "raw"
  }

  cdrom {
    file_id      = "local:iso/talos-v1.13.8-amd64.iso"
    interface    = "ide2"
  }
  
  

  network_device {
    bridge   = "vnetk8s" # SDN VNet
    model    = "virtio"
    firewall = true    # このNICでファイアウォールを有効化
    mac_address = "BC:24:11:CB:45:C8" # ★ MACアドレスを明示的に固定
  }

  boot_order = ["ide2", "scsi0"]
}

# resource "proxmox_virtual_environment_firewall_rules" "security_group_rules" {
#   depends_on = [
#     proxmox_virtual_environment_vm.talos_single,
#     proxmox_virtual_environment_cluster_firewall_security_group.talos_sg,
#   ]

#   node_name = proxmox_virtual_environment_vm.talos_single.node_name
#   vm_id     = proxmox_virtual_environment_vm.talos_single.vm_id


#   rule {
#     security_group = proxmox_virtual_environment_cluster_firewall_security_group.talos_sg.name
#   }
# }



# --- 4. VMのTalos APIに構成(config)を適用 ---
resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = var.node_ip

  depends_on = [proxmox_virtual_environment_vm.talos_single]
}

# --- 5. クラスタのブートストラップ（初期化） ---
resource "talos_machine_bootstrap" "bootstrap" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip

  depends_on = [talos_machine_configuration_apply.controlplane]
}

# --- 6. kubeconfig の取得 (resourceへ変更) ---
resource "talos_cluster_kubeconfig" "kubeconfig" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip

  depends_on = [talos_machine_bootstrap.bootstrap]
}

# --- 7. ローカルに kubeconfig と talosconfig ファイルを出力 ---
resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw # ★ data. を削除
  filename = "${path.module}/kubeconfig"
}


resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talosconfig"
}


# --- K8s API サーバー (6443) が完全起動するまで 60 秒待つ ---
resource "time_sleep" "wait_for_k8s_api" {
  create_duration = "240s"

  depends_on = [
    talos_machine_bootstrap.bootstrap,
    talos_cluster_kubeconfig.kubeconfig
  ]
}

# ------------------------------------------------------------------------------
provider "helm" {
  kubernetes={
    host                   = talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.host
    client_certificate     = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.ca_certificate)
  }
}

provider "kubectl" {
  host                   = talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.host
  client_certificate     = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.ca_certificate)
  load_config_file       = false
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "3.5.0" # ※必要に応じて最新チャートバージョンに変更
  namespace        = "argocd"
  create_namespace = true
  wait             = true   # CRDが準備完了するまで待機する

  depends_on = [
    time_sleep.wait_for_k8s_api # ★ ここを time_sleep に差し替える！
  ]
  # 必要に応じてパラメータのカスタマイズ（例: Ingressの有効化やServer設定など）
  # set {
  #   name  = "server.insecure"
  #   value = "true"
  # }
}

resource "kubectl_manifest" "root_application" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/e331-1/stella-k8s.git" # 対象リポジトリ
        targetRevision = "HEAD"
        path           = "apps" # リポジトリ内のディレクトリパス
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  })
  depends_on = [
    helm_release.argocd
  ]
}

resource "kubectl_manifest" "cert_manager_config_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "cert-manager-config"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/e331-1/stella-k8s.git"
        targetRevision = "HEAD"
        # ★ ここで Kustomize overlay (production / staging) を動的に切り替えます
        path           = "manifests/cert-manager-config/overlays/${var.environment}"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  })

  depends_on = [
    helm_release.argocd
  ]
}