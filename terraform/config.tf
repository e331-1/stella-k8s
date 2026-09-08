#
#    talosconfig
#


# 2. 生成されたtalosconfigを一時的にローカルファイルとして書き出し
resource "local_file" "talosconfig_temp" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/.talosconfig-${var.environment}.tmp"
}

# 3. ~/.talos/config へマージ（統合）
resource "null_resource" "update_configs" {
  depends_on = [
    talos_machine_bootstrap.bootstrap,
    local_file.talosconfig_temp
  ]

  triggers = {
    environment      = var.environment
    control_plane_ip = var.node_ip
    config_hash      = sha256(data.talos_client_configuration.this.talos_config)
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e # エラーが発生したら即座に停止
      mkdir -p ~/.talos ~/.kube

      TARGET_CONTEXT="${data.talos_client_configuration.this.cluster_name}"

      # 1. 既存の同名コンテキストがあれば削除して重複増殖を防ぐ
      if [ -s ~/.talos/config ]; then
        # 削除対象がアクティブな場合のエラーを避けるため、カレントコンテキストを一時的に解除
        talosctl config context "" || true
        
        echo y | talosctl config remove "$TARGET_CONTEXT" || true
        talosctl config merge ${local_file.talosconfig_temp.filename}
      else
        cp ${local_file.talosconfig_temp.filename} ~/.talos/config
        chmod 600 ~/.talos/config
      fi
      # --- 2. kubeconfig の更新 ---
      # 一時ファイルを明示的に渡すことで ~/.talos/config 依存の問題を回避
      talosctl kubeconfig \
        --nodes ${var.node_ip} \
        --endpoints ${var.node_ip} \
        --talosconfig ${local_file.talosconfig_temp.filename} \
        --force \
        ~/.kube/config

      # --- 3. 最後に作業用一時ファイルを削除 ---
      rm -f ${local_file.talosconfig_temp.filename}
    EOT
  }
}

