locals {
  ssh_public_key = file(var.ssh_public_key)
}

data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/user_data.yaml.tftpl", {
      vm_name         = local.vm_full_name
      user_name       = var.user_name
      ssh_public_key  = local.ssh_public_key
      ansilume_public_key = local.ansilume_pub_key
      runner_public_key   = file(pathexpand("~/.ssh/ansilume_runner.pub"))
    })
  }
}

data "cloudinit_config" "network_config" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/network_config.yaml.tftpl", {
      network_interface = var.network_interface
    })
  }
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit.iso"
  user_data      = data.cloudinit_config.user_data.rendered
  network_config = data.cloudinit_config.network_config.rendered
  pool           = libvirt_pool.domains.name
}