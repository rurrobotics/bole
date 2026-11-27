#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Post-build checks, run inside the image chroot by Packer. Fails the build
# if the image is not what we expect.
set -uo pipefail

failures=0
check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok    $name"
    else
        echo "FAIL  $name"
        failures=$((failures + 1))
    fi
}
build_value() { sed -n "s/^$1: \"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" /etc/bole/build.yaml; }

distro=$(build_value ros_distro)
user=$(build_value user)

check "build.yaml present" test -f /etc/bole/build.yaml
check "ROS 2 $distro installed" test -f "/opt/ros/$distro/setup.bash"
check "ros2 command works" bash -c ". /opt/ros/$distro/setup.bash && ros2 --help"
check "colcon installed" command -v colcon
check "rosdep initialised" test -f /etc/ros/rosdep/sources.list.d/20-default.list
check "user $user exists" id "$user"
check "bole command installed" test -x /usr/local/bin/bole
check "bole.yaml on boot partition" test -f /boot/firmware/bole.yaml
check "bole.yaml is valid" /usr/local/sbin/bole-apply-config --check
check "netplan config generated" test -f /etc/netplan/60-bole.yaml
check "cloud-init disabled" test -f /etc/cloud/cloud-init.disabled
check "cloud-init seed files removed" test ! -e /boot/firmware/user-data
check "config.txt has bole block" grep -q "bole managed block" /boot/firmware/config.txt
for unit in bole-firstboot bole-config bole-ros-workspace bole-ros-launch ssh avahi-daemon; do
    check "$unit.service enabled" systemctl is-enabled "$unit.service"
done
check "no SSH host keys baked in" bash -c '! compgen -G "/etc/ssh/ssh_host_*"'
check "machine-id is empty" test ! -s /etc/machine-id
check "policy-rc.d removed" test ! -e /usr/sbin/policy-rc.d

if [ "$failures" -gt 0 ]; then
    echo "verify: $failures check(s) failed"
    exit 1
fi
echo "verify: all checks passed"
