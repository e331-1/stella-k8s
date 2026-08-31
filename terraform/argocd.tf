
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

  timeout = 1200

  depends_on = [
    time_sleep.wait_for_k8s_api
  ]
  values = [ <<EOT
global:
  domain: argocd.example.com
server:
  extraArgs:
    - --insecure
dex:
  enabled: true

# ★ ここが重要です: dex.config は configs.cm の下に記述します
configs:
  cm:
    url: https://argocd.pitpe.app
    dex.config: |
      connectors:
        - type: google
          id: google
          name: Google
          config:
            clientID: "${var.oidc_client_id}"
            clientSecret: "${var.oidc_client_secret}"
            redirectURI: https://argocd.pitpe.app/api/dex/callback
            groups:
              - capsule.clastix.io

      strategy:
        device:
          userCode: choice

      staticClients:
        - id: kubernetes-client
          name: 'Kubernetes CLI'
          secret: "${var.device_client_secret}"
          grantTypes:
            - authorization_code
            - urn:ietf:params:oauth:grant-type:device_code
            - refresh_token
          redirectURIs:
            - http://localhost:8000
            - http://127.0.0.1:8000

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
      sources = [
        {
          repoURL        = "https://github.com/e331-1/stella-k8s.git" # 対象リポジトリ
          targetRevision = "${var.environment== "production" ? "main" : "develop"}" # ブランチ名
          path           = "argocd/apps/helm" # リポジトリ内のディレクトリパス
        },
        {
          repoURL        = "https://github.com/e331-1/stella-k8s.git" # 対象リポジトリ
          targetRevision = "${var.environment== "production" ? "main" : "develop"}" # ブランチ名
          path           = "argocd/apps/manifests/overlays/${var.environment}" # リポジトリ内のディレクトリパス
        }
      ]
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
