# AGENTS.md

Instructions for AI coding agents (and humans) working on **bole**.

## What this project is

bole builds a flashable **Ubuntu Server image with ROS 2** for **Raspberry Pi 4 and 5**.

- **Ansible** (`ansible/`) does all the provisioning.
- **Packer** (`packer/`) with the [packer-plugin-builder-arm](https://github.com/mkaczanowski/packer-plugin-builder-arm) plugin (installed by `packer/install-plugin.sh`, not `packer init`, because of an upstream versioning bug) downloads the official Ubuntu raspi image, grows it, loop-mounts it and runs the Ansible playbook inside a chroot.
- **GitHub Actions** (`.github/workflows/`) builds the image on native arm64 runners on every push and attaches it to a Release on `v*` tags.
- **Runtime configuration** lives in `bole.yaml` on the FAT boot partition (`/boot/firmware/bole.yaml` on the Pi). The `bole-config.service` re-applies it on every boot, so WiFi, passwords, SSH keys and the ROS project can change without rebuilding the image.

Defaults: Ubuntu 26.04 LTS, ROS 2 Lyrical Luth, `ros-base`. The distro is a variable (`ros_distro`), and so is the base image URL.

## Layout

| Path | Purpose |
|---|---|
| `ansible/site.yml` | Main playbook, which applies all roles in order |
| `ansible/group_vars/all.yml` | Every build-time default, documented inline |
| `ansible/inventory/` | `image.yml` (chroot, used by Packer), `pi.example.yml` (a live Pi over SSH); Vagrant generates its own |
| `ansible/roles/base` | Locale, timezone, packages, snapd removal, Pi `config.txt` |
| `ansible/roles/users` | Default user and groups |
| `ansible/roles/ssh` | sshd drop-in, host key handling |
| `ansible/roles/network` | netplan/wpasupplicant, regulatory domain, avahi |
| `ansible/roles/ros` | ROS 2 apt source, packages, rosdep, environment |
| `ansible/roles/bootconfig` | `bole-apply-config`, first-boot service, default `bole.yaml`, `bole` command |
| `ansible/roles/ros_workspace` | Clone/build/launch the user's ROS project at boot |
| `ansible/roles/cleanup` | Image-only cleanup (apt cache, machine-id, logs) |
| `packer/` | Packer template, variables, `install-plugin.sh`, `verify.sh`, `build.sh` wrapper |
| `tests/` | pytest unit tests for `bole-apply-config`; `tests/vagrant/` test `bole.yaml` and end-to-end checks |
| `Vagrantfile` | Full playbook run in a libvirt VM |

## Hard rules

1. **Image mode vs live mode.** `bole_build_mode` is `image` (Packer chroot) or `live` (Vagrant or a real Pi).
   - In image mode, **never start, restart or reload services** and never rely on a running systemd, D-Bus, udev or network manager. Use `ansible.builtin.systemd_service` with `enabled: true` only, or guard the task with `when: bole_build_mode == 'live'`.
   - Handlers that restart services must also be guarded.
2. **No secrets in the repo or the image.** The CI image is public. Real credentials only ever go in `bole.yaml` on the user's SD card. Build-time defaults (`bole`/`bole`) are placeholders.
3. **Everything idempotent.** A second playbook run must report `changed=0`.
4. **The Pi-specific bits are guarded** by `bole_target == 'pi'` (the default). Vagrant sets `bole_target=vagrant`.
5. A new user-facing setting goes in **either** `group_vars/all.yml` (build-time) **or** the `bole.yaml` template (runtime), and is documented in the README's configuration table.
6. **Git LFS only when needed.** No binary assets are tracked today. If one gets added (e.g. an image for the README), add a specific `filter=lfs` pattern to `.gitattributes` in the same commit.

## Commands

```bash
# Lint and test (CI runs the same)
yamllint --strict .
(cd ansible && ansible-lint)
shellcheck packer/*.sh tests/vagrant/*.sh ansible/roles/bootconfig/files/bole ansible/roles/bootconfig/files/bole-firstboot
packer fmt -check packer/ && packer validate packer/
pytest tests/

# Build the image locally (arm64 Linux, or x86 with qemu-user-static)
./packer/build.sh

# Full playbook in a VM
vagrant up --provider=libvirt
vagrant provision   # idempotency check: expect changed=0
```

## Git conventions

- Use **Conventional Commits**: `feat(scope):`, `fix:`, `docs:`, `chore:`, `ci:`, `test:`, `refactor:`. Scopes match role or directory names (`ros`, `bootconfig`, `packer`, `ci`).
- Keep commits small and logical.
- **Ask the maintainer for approval before every commit**: show the files and the message, and wait.
- Never commit build outputs (`output/`, `packer_cache/`, `*.img*`).
