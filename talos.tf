data "talos_client_configuration" "this" {
  cluster_name         = "stella-k8s"
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.node_ip]
}

# --- 1. Talosの機密鍵・証明書設定を自動生成 ---
resource "talos_machine_secrets" "this" {}

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
        inlineManifests=[
          {
            name = "proxmox-cloud-controller-manager"
            contents = <<EOT
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: proxmox-cloud-controller-manager
  namespace: kube-system
stringData:
  config.yaml: |
    clusters:
      - url: ${trimsuffix(var.proxmox_endpoint, "/")}/api2/json
        insecure: true
        token_id: "${proxmox_virtual_environment_user.kubernetes.user_id}!${proxmox_virtual_environment_user_token.ccm.token_name}"
        token_secret: "${element(split("=", proxmox_virtual_environment_user_token.ccm.value), 1)}"
        region: ${var.proxmox_clustername}
EOT
          },{
            name = "proxmox-csi-plugin"
            contents = <<EOT
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: proxmox-csi-plugin
  namespace: csi-proxmox
stringData:
  config.yaml: |
    clusters:
      - url: ${trimsuffix(var.proxmox_endpoint, "/")}/api2/json
        insecure: true
        token_id: "${proxmox_virtual_environment_user.kubernetes-csi.user_id}!${proxmox_virtual_environment_user_token.csi.token_name}"
        token_secret: "${element(split("=", proxmox_virtual_environment_user_token.csi.value), 1)}"
        region: ${var.proxmox_clustername}
EOT
          },
{
            name = "custom-proxmox-storageclass"
            contents = <<EOT
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: proxmox-local-lvm
  annotations:
    storageclass.kubernetes.io/is-default-class: "true" # デフォルトにしたい場合は追加
provisioner: csi.proxmox.sinextra.dev
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
parameters:
  # Proxmox VE の WebUI に表示されている正確な Storage ID を指定します
  # (例: "local-lvm", "local-zfs", "ceph-store" など)
  storage: "storage-01"
  
  # ディスクフォーマット (ext4, xfs 等)
  csi.storage.k8s.io/fstype: "ext4"

  # （任意）帯域制限やキャッシュ制御等のオプション
  # cache: "none"
  # ssd: "1"
EOT
          }
        ]
        externalCloudProvider ={
          enabled = true
          manifests=[
            "https://raw.githubusercontent.com/sergelogvinov/proxmox-cloud-controller-manager/main/docs/deploy/cloud-controller-manager.yml",
            "https://raw.githubusercontent.com/sergelogvinov/proxmox-csi-plugin/main/docs/deploy/proxmox-csi-plugin.yml"
          ]
        }

        allowSchedulingOnControlPlanes = true
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      
      }
      apiServer={
        extraArgs = {
          "oidc-issuer-url" = var.oidc_issuer_url
          "oidc-client-id" = var.oidc_client_id
          "oidc-username-claim" = "email"
        }
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
        kubelet = {
          extraArgs = {
            cloud-provider = "external"
          }
        }
        network = {
          # hostname=var.vm_name
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
    ,
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = var.vm_name # または "talos-single"
      auto       = "off"
    })
  ]

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