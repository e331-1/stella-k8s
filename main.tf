

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


