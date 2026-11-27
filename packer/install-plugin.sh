#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Install the packer-plugin-builder-arm release binary, verified against the
# release's SHA256SUMS, into $PACKER_PLUGIN_PATH.
#
# Why not `packer init`: releases v1.1.1-v1.1.7 report their version as
# "1.1.0" (upstream never bumped version.go), so `packer init` refuses them,
# and v1.1.0 itself publishes its checksums under a name `packer init` does
# not look for. `packer plugins install --path` registers the binary under
# the version it reports, which is why bole.pkr.hcl requires "1.1.0".
set -euo pipefail

PLUGIN_VERSION="${PLUGIN_VERSION:-1.1.7}"
REPO="https://github.com/mkaczanowski/packer-plugin-builder-arm"

case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) echo "install-plugin.sh: unsupported host $(uname -m)" >&2; exit 1 ;;
esac

if packer plugins installed 2>/dev/null | grep -q "mkaczanowski/builder-arm/"; then
    echo "install-plugin.sh: builder-arm plugin already installed"
    exit 0
fi

name="packer-plugin-builder-arm_v${PLUGIN_VERSION}_x5.0_linux_${arch}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/$name.zip" "$REPO/releases/download/v$PLUGIN_VERSION/$name.zip"
curl -fsSL -o "$tmp/SHA256SUMS" "$REPO/releases/download/v$PLUGIN_VERSION/packer-plugin-builder-arm_v${PLUGIN_VERSION}_SHA256SUMS"
(cd "$tmp" && grep " $name.zip\$" SHA256SUMS | sha256sum -c -)

python3 -m zipfile -e "$tmp/$name.zip" "$tmp/x"
chmod +x "$tmp/x/$name"
packer plugins install --path "$tmp/x/$name" github.com/mkaczanowski/builder-arm
