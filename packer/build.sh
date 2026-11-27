#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the bole image locally. Extra arguments go to `packer build`, e.g.:
#   ./packer/build.sh -var ros_distro=jazzy
#
# Needs: packer, ansible-core, xz, sfdisk, parted, e2fsprogs, qemu-img, kpartx
# and sudo. On x86_64 hosts also qemu user-mode emulation for aarch64
# (Fedora: qemu-user-static-aarch64, Debian/Ubuntu: qemu-user-static or
# qemu-user + qemu-user-binfmt).
set -euo pipefail

cd "$(dirname "$0")/.."
repo=$(pwd)

die() {
    echo "build.sh: $*" >&2
    exit 1
}

for tool in packer ansible-playbook ansible-galaxy curl python3 xz sfdisk parted resize2fs qemu-img kpartx; do
    command -v "$tool" >/dev/null || die "'$tool' not found, see the README for build dependencies"
done

export PACKER_PLUGIN_PATH="$repo/.packer/plugins"
export PACKER_CACHE_DIR="$repo/packer_cache"
export ANSIBLE_COLLECTIONS_PATH="$repo/ansible/collections"

extra=()
if [ "$(uname -m)" = aarch64 ]; then
    export DONT_SETUP_QEMU=1
else
    qemu=""
    for candidate in /usr/bin/qemu-aarch64-static /usr/bin/qemu-aarch64; do
        if [ -x "$candidate" ]; then
            qemu="$candidate"
            break
        fi
    done
    [ -n "$qemu" ] || die "no qemu aarch64 user-mode emulator found (x86 hosts need it)"
    grep -qs "$qemu" /proc/sys/fs/binfmt_misc/* || die "$qemu is not registered in binfmt_misc"
    extra+=(-var "qemu_binary=$qemu")
    echo "build.sh: x86_64 host, emulating arm64 with $qemu (this is slow)"
fi

version=$(git describe --tags --always --dirty 2>/dev/null || echo dev)

ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections >/dev/null
packer/install-plugin.sh
packer validate -var "version=$version" "${extra[@]}" "$@" packer/

sudo --preserve-env=PACKER_PLUGIN_PATH,PACKER_CACHE_DIR,ANSIBLE_COLLECTIONS_PATH,DONT_SETUP_QEMU \
    env "PATH=$PATH" packer build -var "version=$version" "${extra[@]}" "$@" packer/

sudo chown -R "$(id -u):$(id -g)" output packer_cache
echo "build.sh: done, image in output/"
