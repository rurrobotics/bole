# Build-time image settings. Override with -var, e.g.:
#   ./packer/build.sh -var ros_distro=jazzy -var ubuntu_version=24.04.3 ...
# Ansible build-time settings live in ansible/group_vars/all.yml.

variable "ubuntu_version" {
  type        = string
  default     = "26.04.1"
  description = "Ubuntu Server point release of the base image."
}

variable "ubuntu_image_url" {
  type        = string
  default     = "https://cdimage.ubuntu.com/releases/26.04/release/ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz"
  description = "Official Ubuntu preinstalled server image for Raspberry Pi (arm64+raspi)."
}

variable "ubuntu_image_sha256" {
  type        = string
  default     = "d59ef9c6e85b906995501f166d00726ab80b59be7b65cdeac0fa31b996053e13"
  description = "SHA256 of ubuntu_image_url, from the release's SHA256SUMS file."
}

variable "ros_distro" {
  type        = string
  default     = "lyrical"
  description = "ROS 2 distro; must have binaries for the Ubuntu release (26.04: lyrical, 24.04: jazzy/kilted)."
}

variable "pi_model" {
  type        = string
  default     = "all"
  description = "Target Raspberry Pi model: all, pi4 or pi5. Scopes config.txt settings and labels the image."

  validation {
    condition     = contains(["all", "pi4", "pi5"], var.pi_model)
    error_message = "The pi_model must be one of: all, pi4, pi5."
  }
}

variable "image_size" {
  type        = string
  default     = "8G"
  description = "Size of the built image. The root partition grows to fill the SD card on first boot."
}

variable "version" {
  type        = string
  default     = "dev"
  description = "Version label used in the output file name (build.sh passes git describe)."
}

variable "qemu_binary" {
  type        = string
  default     = "/usr/bin/qemu-aarch64-static"
  description = "qemu user-mode binary for building on x86 hosts (ignored when DONT_SETUP_QEMU is set on arm64)."
}

variable "ansible_extra_args" {
  type        = string
  default     = ""
  description = "Extra ansible-playbook arguments, e.g. \"-e base_remove_snapd=false\"."
}
