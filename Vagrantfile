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

Vagrant.configure("2") do |config|
  config.vm.box = BOX
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
