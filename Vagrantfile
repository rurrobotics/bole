# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Full test of the Ansible playbook in an Ubuntu 26.04 VM (libvirt).
#   vagrant up --provider=libvirt   # provision and run the end-to-end checks
#   vagrant provision               # re-run: the playbook must report changed=0
#   vagrant ssh
#
# The VM is x86_64, so Raspberry Pi specific tasks (config.txt, first-boot
# partition growing) are skipped; everything else runs exactly as on a Pi.
# tests/vagrant/bole.yaml stands in for the SD card's bole.yaml.

BOX = ENV.fetch("BOLE_VAGRANT_BOX", "cloud-image/ubuntu-26.04")
BOX_VERSION = "20260927.0.0"
# Direct link to the amd64 libvirt build, for Vagrant < 2.4 (see below).
BOX_AMD64_URL = "https://vagrantcloud.com/cloud-image/boxes/ubuntu-26.04/versions/" \
                "#{BOX_VERSION}/providers/libvirt/amd64/vagrant.box"

Vagrant.configure("2") do |config|
  if ENV.key?("BOLE_VAGRANT_BOX")
    config.vm.box = BOX
  elsif Gem::Version.new(Vagrant::VERSION) >= Gem::Version.new("2.4.0")
    config.vm.box = BOX
    config.vm.box_version = BOX_VERSION
    config.vm.box_architecture = "amd64"
  else
    # Vagrant < 2.4 (e.g. Fedora's 2.3.x) doesn't understand multi-architecture
    # boxes and may pick the arm64 build, which hangs at "Booting from Hard
    # Disk...". Download the amd64 build directly under its own name instead.
    config.vm.box = "bole/ubuntu-26.04-amd64"
    config.vm.box_url = BOX_AMD64_URL
  end
  config.vm.hostname = "bole-vagrant"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider :libvirt do |lv|
    lv.memory = 4096
    lv.cpus = 4
  end

  # Put the test bole.yaml where the boot partition would be (only once,
  # so edits made inside the VM survive re-provisioning).
  config.vm.provision "bole-yaml-upload", type: "file",
    source: "tests/vagrant/bole.yaml", destination: "/tmp/bole.yaml"
  config.vm.provision "bole-yaml", type: "shell", inline: <<~SHELL
    mkdir -p /boot/firmware
    [ -f /boot/firmware/bole.yaml ] || cp /tmp/bole.yaml /boot/firmware/bole.yaml
  SHELL

  config.vm.provision "ansible" do |ansible|
    ansible.compatibility_mode = "2.0"
    ansible.playbook = "ansible/site.yml"
    ansible.config_file = "ansible/ansible.cfg"
    ansible.galaxy_role_file = "ansible/requirements.yml"
    ansible.galaxy_command = "ansible-galaxy collection install -r %{role_file}"
    ansible.extra_vars = {
      bole_build_mode: "live",
      bole_target: "vagrant",
    }
  end

  config.vm.provision "check", type: "shell", path: "tests/vagrant/check.sh"
end
