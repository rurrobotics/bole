#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# End-to-end checks inside the Vagrant VM: bole.yaml applied, the ROS project
# cloned and built, the launch command running and publishing.
set -euo pipefail

fail() {
    echo "FAIL: $*"
    exit 1
}

echo "== bole.yaml applied"
[ "$(cat /etc/hostname)" = "bole-vagrant" ] || fail "hostname not applied"
grep -q "ROS_DOMAIN_ID=42" /etc/bole/ros.env || fail "ros.env not written"
/usr/local/sbin/bole-apply-config --check

echo "== building the ROS workspace (first run can take a few minutes)"
systemctl restart bole-ros-workspace.service
[ -f /home/bole/ros2_ws/install/setup.bash ] || fail "workspace was not built"

echo "== starting the launch command"
systemctl restart bole-ros-launch.service
sleep 10
systemctl is-active --quiet bole-ros-launch.service || fail "bole-ros-launch is not running"

echo "== waiting for a message on /topic"
runuser -u bole -- bash -c '. /etc/bole/ros-env.sh && timeout 30 ros2 topic echo --once /topic' ||
    fail "no message received on /topic"

echo "== all Vagrant checks passed"
