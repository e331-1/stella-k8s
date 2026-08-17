
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
  values = [ <<EOT
global:
  domain: argocd.example.com

dex:
  enabled: true
  config: |
    connectors:
      - type: google
        id: google
        name: Google
        config:
          clientID: "${var.oidc_client_id}"
          clientSecret: "${var.oidc_client_secret}"
          redirectURI: https://argocd.pitpe.com/api/dex/callback
          groups:
            - capsule.clastix.io

    # Device Flow (CLI用) を有効化する場合
    strategy:
      device:
        userCode: choice

    staticClients:
      - id: kubernetes-device
        name: 'Kubernetes CLI (Device Flow)'
        secret: "${var.device_client_secret}"
        grantTypes:
          - authorization_code                       # ← 通常のブラウザ自動起動用
          - urn:ietf:params:oauth:grant-type:device_code  # ← Device Flow (暗証番号) 用
          - refresh_token                            # ← トークン自動更新用
        redirectURIs:
          - http://localhost:8000/callback           # kubeloginのローカルリダイレクト用
          - http://127.0.0.1:8000/callback

configs:
  rbac:
    policy.csv: |
      g, capsule.clastix.io, role:admin
EOT
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


