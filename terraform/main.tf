resource "libvirt_volume" "ubuntu_base" {
  name = "${var.vm_name}-ubuntu-base.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = abspath("${path.module}/ubuntu-24.04-server-cloudimg-amd64.img")
    }
  }
}

resource "libvirt_volume" "vm_disk" {
  name     = "${var.vm_name}.qcow2"
  pool     = "default"
  capacity = var.disk_size_gb * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "cloudinit" {
  name = "${var.vm_name}-cloudinit"
  user_data = templatefile("${path.module}/cloud-init/user-data.yaml", {
    vm_name        = var.vm_name
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  })
  meta_data = file("${path.module}/cloud-init/meta-data.yaml")
}

resource "libvirt_volume" "cloudinit_iso" {
  name = "${var.vm_name}-seed.iso"
  pool = "default"

  target = {
    format = {
      type = "iso"
    }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.cloudinit.path
    }
  }
}

resource "libvirt_domain" "vm" {
  name        = var.vm_name
  type        = "kvm"
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.vcpu_count
  running     = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    boot_devices = [{ dev = "hd" }]
  }

  devices = {
    disks = [
      {
        device = "disk"
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          file = {
            file = libvirt_volume.vm_disk.path
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device = "cdrom"
        driver = {
          name = "qemu"
          type = "raw"
        }
        source = {
          file = {
            file = libvirt_volume.cloudinit_iso.path
          }
        }
        target = {
          dev = "hdd"
          bus = "ide"
        }
        read_only = true
      }
    ]

    interfaces = [
      {
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = "default"
          }
        }
      }
    ]
  }
}
