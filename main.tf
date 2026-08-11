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
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      #   apiServer = {
      #     admissionControl = [
      #       {
      #         name = "PodSecurity"
      #         configuration = {
      #           apiVersion = "pod-security.admission.config.k8s.io/v1"
      #           kind       = "PodSecurityConfiguration"
      #           defaults = {
      #             enforce         = "baseline"
      #             enforce-version = "latest"
      #             audit           = "restricted"
      #             audit-version   = "latest"
      #             warn            = "restricted"
      #             warn-version    = "latest"
      #           }
      #           exemptions = {
      #             namespaces = ["kube-system"] # Cilium が存在する kube-system を除外
      #           }
      #         }
      #       }
      #     ]
      #   }
      }
      machine = {
        #cilium用
        # ★ localhost:7445 (KubePrism) を有効化して Cilium が API サーバーを見つけられるようにする
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = null
        }
        network = {
          nameservers = [
            "1.1.1.1",
            "8.8.8.8" #これがないと10.0.1.1で名前解決しようとする
          ]
          interfaces = [
            {
              # 1つ目のNIC (vnetk8s 側) - ノード自身の通信用
              interface = "ens18" # ※必要に応じて ens18 に変更
              dhcp      = false
              addresses = ["${var.node_ip}/24"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway_ip
                }
              ]
            },
            {
              # ★ 2つ目のNIC (vmbr0 側) - Cilium L2 Announcement 専有
              interface = "ens19" # または "eth1" (MACアドレスで固定する場合は hardwareAddr を使用)
              dhcp      = false   # IPもDHCPも指定しない
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

  network_device {
    bridge   = "vmbr0" # 物理ブリッジ
    model    = "virtio"
    firewall = false   # 必要に応じて true/false を設定
  }

  boot_order = ["scsi0","ide2"]
}

resource "proxmox_virtual_environment_firewall_rules" "security_group_rules" {
  depends_on = [
    proxmox_virtual_environment_vm.talos_single,
    proxmox_virtual_environment_cluster_firewall_security_group.talos_sg,
  ]

  node_name = proxmox_virtual_environment_vm.talos_single.node_name
  vm_id     = proxmox_virtual_environment_vm.talos_single.vm_id


  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.talos_sg.name
  }
}



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
  # filename = "${path.module}/kubeconfig"
  filename = pathexpand("~/.kube/config")
}


resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = pathexpand("~/.talos/config")
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


# 1. 公式 GitHub から Gateway API の CRD YAML を取得
# 1. Gateway API CRD を公式 YAML から直接適用
resource "null_resource" "gateway_api_crds" {
  provisioner "local-exec" {
    # ★ --validate=false を追加して余計な OpenAPI スキーマ取得通信によるエラーを防止
    command = "kubectl --kubeconfig=${local_file.kubeconfig.filename} apply --validate=false -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml"
  }
  depends_on = [
    time_sleep.wait_for_k8s_api
  ]
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.20.0"
  namespace  = "kube-system"
  wait       = true

  values = [
    yamlencode({
      ipam = {
        mode = "kubernetes"
      }

      kubeProxyReplacement = true

      operator = {
        replicas = 1
      }
      
      # securityContext = {
      #   capabilities = {
      #     ciliumAgent = [
      #       "CHOWN",
      #       "KILL",
      #       "NET_ADMIN",
      #       "NET_RAW",
      #       "IPC_LOCK",
      #       "SYS_ADMIN",
      #       "SYS_RESOURCE",
      #       "DAC_OVERRIDE",
      #       "FOWNER",
      #       "SETGID",
      #       "SETUID"
      #     ]
      #     cleanCiliumState = [
      #       "NET_ADMIN",
      #       "SYS_ADMIN",
      #       "SYS_RESOURCE"
      #     ]
      #   }
      # }
      securityContext={
        privileged = true
      }


      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }

      k8sServiceHost = "localhost"
      k8sServicePort = 7445

      gatewayAPI = {
        enabled           = true
        enableAlpn        = true
        enableAppProtocol = true
      }

      l2announcements = {
        enabled = true
      }
    })
  ]

  depends_on = [
    null_resource.gateway_api_crds
  ]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  
  #https://github.com/argoproj/argo-helm
  #最新バージョンはここからチェック
  version          = "10.3.0" # ※必要に応じて最新チャートバージョンに変更

  namespace        = "argocd"
  create_namespace = true
  wait             = true   # CRDが準備完了するまで待機する

  timeout = 600

  depends_on = [
    time_sleep.wait_for_k8s_api
  ]

  
  # 必要に応じてパラメータのカスタマイズ（例: Ingressの有効化やServer設定など）
  # set {
  #   name  = "server.insecure"
  #   value = "true"
  # }
}


# 1. cert-manager 用の Namespace を自動作成
resource "kubectl_manifest" "cert_manager_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "cert-manager"
    }
  })

  depends_on = [
    time_sleep.wait_for_k8s_api
  ]
}

# 2. Cloudflare API Token 用の Secret を作成
resource "kubectl_manifest" "cloudflare_api_token_secret" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "cloudflare-api-token-secret"
      namespace = "cert-manager"
    }
    type = "Opaque"
    stringData = {
      api-token = var.cloudflare_api_token
    }
  })

  depends_on = [
    kubectl_manifest.cert_manager_namespace # Namespace ができてから作成する
  ]
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
