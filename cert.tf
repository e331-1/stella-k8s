
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

# # 2. Cloudflare API Token 用の Secret を作成
# resource "kubectl_manifest" "cloudflare_api_token_secret" {
#   yaml_body = yamlencode({
#     apiVersion = "v1"
#     kind       = "Secret"
#     metadata = {
#       name      = "cloudflare-api-token-secret"
#       namespace = "cert-manager"
#     }
#     spec = {
#       refreshInterval = "1h"
#       secretStoreRef = {
#         name = "vault-backend"
#         kind = "ClusterSecretStore"
#       }
#       target = {
#         name = "cloudflare-api-token-secret" # K8s 内に自動生成される Secret 名
#         creationPolicy = "Owner"
#       }
#       data = [
#         {
#           secretKey = "api-token"
#           remoteRef = {
#             key      = "cert-manager/cloudflare"
#             property = "api-token"
#           }
#         }
#       ]
#     }
#   })

#   depends_on = [
#     kubectl_manifest.cert_manager_namespace # Namespace ができてから作成する
#   ]
# }



# 2. Cloudflare API Token 用の Secret を作成
# resource "kubectl_manifest" "cloudflare_api_token_secret" {
#   yaml_body = yamlencode({
#     apiVersion = "v1"
#     kind       = "Secret"
#     metadata = {
#       name      = "cloudflare-api-token-secret"
#       namespace = "cert-manager"
#     }
#     type = "Opaque"
#     stringData = {
#       api-token = var.cloudflare_api_token
#     }
#   })

#   depends_on = [
#     kubectl_manifest.cert_manager_namespace # Namespace ができてから作成する
#   ]
# }
