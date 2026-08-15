


# # データセンターレベルでセキュリティグループを定義
# resource "proxmox_virtual_environment_cluster_firewall_security_group" "talos_sg" {
#   name    = "talos-nodes"
#   comment = "Firewall rules for Talos Linux nodes"
  
#   rule {
#     type    = "out"
#     action  = "ACCEPT"
#     dest    = "192.168.0.100"
#     comment = "proxmox VE ノードへのアクセスを許可(proxmox ccm用)"
#     enabled = true
#   }
#   rule {
#     type    = "out"
#     action  = "REJECT"
#     dest    = "192.168.0.0/24"
#     comment = "ローカルへのアクセスを禁止"
#     enabled = true
#   }

# }




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
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name = "cloudflare-api-token-secret" # K8s 内に自動生成される Secret 名
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "api-token"
          remoteRef = {
            key      = "cert-manager/cloudflare"
            property = "api-token"
          }
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.cert_manager_namespace # Namespace ができてから作成する
  ]
}


