



# データセンターレベルでセキュリティグループを定義
resource "proxmox_virtual_environment_cluster_firewall_security_group" "talos_sg" {
  name    = "talos-nodes"
  comment = "Firewall rules for Talos Linux nodes"
  
  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.0.100"
    comment = "proxmox VE ノードへのアクセスを許可(proxmox ccm・csi用)"
    enabled = true
  }
  rule {
    type    = "out"
    action  = "REJECT"
    dest    = "192.168.0.0/24"
    comment = "ローカルへのアクセスを禁止"
    enabled = true
  }

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


# --- 3. Proxmox上に Talos VM を作成 ---
resource "proxmox_virtual_environment_vm" "talos_single" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id

  agent {
    enabled = true # QEMU Guest Agent
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192 # 4GB RAM
    floating = 8192
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
    iothread     = true
    discard      = "on"
    file_id = "local:import/talos-1.13.9.raw"
  }
  

  disk {
    datastore_id = var.environment == "production" ? "storage-01" : "storage-01-dev" # SDN VNet
    size         = 20
    interface    = "scsi1"
    iothread     = true
    discard      = "on"
  }
  

  network_device {
    bridge   = var.environment == "production" ? "k8s" : "k8sDEV" # SDN VNet
    model    = "virtio"
    firewall = true    # このNICでファイアウォールを有効化
    mac_address = "BC:24:11:CB:45:C8" # ★ MACアドレスを明示的に固定
  }

  network_device {
    bridge   = "vmbr0" # 物理ブリッジ
    model    = "virtio"
    firewall = true    # 必要に応じて true/false を設定
  }
  hostpci {
    device = "hostpci0"
    id = "0000:00:02.0"
    mdev = "i915-GVTg_V5_4"
  }

  boot_order = ["scsi0"]
}