# bole: flashable Ubuntu Server + ROS 2 image for Raspberry Pi 4 and 5.
#
# Run through ./packer/build.sh (needs root for loop devices and chroot).
# Packer downloads the official Ubuntu raspi image, grows it, mounts it at
# /tmp/bole-rootfs and Ansible provisions it through a chroot connection.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    arm = {
      # Packer plugin address, not a URL: Packer adds the "packer-plugin-" prefix,
      # so this resolves to https://github.com/mkaczanowski/packer-plugin-builder-arm
      source = "github.com/mkaczanowski/builder-arm"
      # We install release v1.1.7 with install-plugin.sh, but that binary reports
      # itself as "1.1.0" (upstream bug), so that is the version Packer sees.
      version = "1.1.0"
    }
  }
}

locals {
  model_label = var.pi_model == "all" ? "pi4-pi5" : var.pi_model
  output_name = "bole-${var.version}-${local.model_label}-ubuntu-${var.ubuntu_version}-${var.ros_distro}-arm64"
  output_dir  = "${path.cwd}/output"
  ansible_dir = "${path.root}/../ansible"
  # Must match ansible/inventory/image.yml
  mount_path = "/tmp/bole-rootfs"
}

source "arm" "ubuntu" {
  file_urls             = [var.ubuntu_image_url]
  file_checksum         = var.ubuntu_image_sha256
  file_checksum_type    = "sha256"
  file_target_extension = "xz"
  file_unarchive_cmd    = ["xz", "--decompress", "$ARCHIVE_PATH"]

  image_build_method = "resize"
  image_path         = "${local.output_dir}/${local.output_name}.img"
  image_size         = var.image_size
  image_type         = "dos"
  image_mount_path   = local.mount_path

  # Partition layout of the Ubuntu 24.04/26.04 raspi images (sfdisk -d).
  image_partitions {
    name         = "boot"
    type         = "c"
    start_sector = "2048"
    filesystem   = "fat"
    size         = "512M"
    mountpoint   = "/boot/firmware"
  }
  image_partitions {
    name         = "root"
    type         = "83"
    start_sector = "1050624"
    filesystem   = "ext4"
    size         = "0" # grow to fill image_size
    mountpoint   = "/"
  }

  image_chroot_env = [
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "DEBIAN_FRONTEND=noninteractive",
  ]
  qemu_binary_source_path      = var.qemu_binary
  qemu_binary_destination_path = "/usr/bin/qemu-aarch64-static"
}

build {
  sources = ["source.arm.ubuntu"]

  # Ubuntu's resolv.conf points into /run, which is empty in the chroot.
  provisioner "shell" {
    inline = [
      "mv /etc/resolv.conf /etc/resolv.conf.bole-bak",
      "printf 'nameserver 1.1.1.1\\nnameserver 8.8.8.8\\n' > /etc/resolv.conf",
    ]
  }

  # Ansible runs on the build host and reaches into the mounted image via chroot.
  provisioner "shell-local" {
    inline = [
      "cd ${local.ansible_dir}",
      "ansible-playbook -i inventory/image.yml site.yml -e ros_distro=${var.ros_distro} -e pi_model=${var.pi_model} ${var.ansible_extra_args}",
    ]
  }

  provisioner "shell" {
    script = "${path.root}/verify.sh"
  }

  provisioner "shell" {
    inline = [
      "rm -f /etc/resolv.conf",
      "mv /etc/resolv.conf.bole-bak /etc/resolv.conf",
    ]
  }

  post-processor "shell-local" {
    inline = [
      "cd ${local.output_dir}",
      "xz -T0 -6 -f ${local.output_name}.img",
      "sha256sum ${local.output_name}.img.xz > ${local.output_name}.img.xz.sha256",
      "cat ${local.output_name}.img.xz.sha256",
    ]
  }
}
