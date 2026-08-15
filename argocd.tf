
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


