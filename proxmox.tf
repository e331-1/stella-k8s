
# --- 3. Proxmox上に Talos VM を作成 ---
resource "proxmox_virtual_environment_vm" "talos_single" {
  name      = var.vm_name
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