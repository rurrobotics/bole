# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for ansible/roles/bootconfig/files/bole-apply-config."""

from __future__ import annotations

import importlib.machinery
import importlib.util
from pathlib import Path

import pytest
import yaml

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "ansible/roles/bootconfig/files/bole-apply-config"
TEMPLATE = REPO / "ansible/roles/bootconfig/templates/bole.yaml.j2"

_loader = importlib.machinery.SourceFileLoader("bole_apply_config", str(SCRIPT))
_spec = importlib.util.spec_from_loader("bole_apply_config", _loader)
bac = importlib.util.module_from_spec(_spec)
_loader.exec_module(bac)

BUILD = {
    "user": "bole",
    "hostname": "bole",
    "timezone": "Europe/Belgrade",
    "ssh_password_auth": True,
    "wifi_country": "RS",
}


@pytest.fixture
def root(tmp_path: Path) -> Path:
    """A minimal fake system root."""
    (tmp_path / "etc").mkdir()
    (tmp_path / "etc/passwd").write_text("root:x:0:0::/root:/bin/bash\nbole:x:1000:1000::/home/bole:/bin/bash\n")
    (tmp_path / "etc/hosts").write_text("127.0.0.1 localhost\n")
    (tmp_path / "home/bole").mkdir(parents=True)
    (tmp_path / "boot/firmware").mkdir(parents=True)
    for zone in ("Europe/Belgrade", "Etc/UTC"):
        z = tmp_path / "usr/share/zoneinfo" / zone
        z.parent.mkdir(parents=True, exist_ok=True)
        z.write_text("")
    (tmp_path / "etc/bole").mkdir()
    (tmp_path / "etc/bole/build.yaml").write_text(yaml.safe_dump(BUILD))
    return tmp_path


def write_config(root: Path, data: dict | str) -> Path:
    path = root / "boot/firmware/bole.yaml"
    path.write_text(data if isinstance(data, str) else yaml.safe_dump(data))
    return path


def run(root: Path, *extra: str) -> int:
    return bac.main(["--root", str(root), "--offline", *extra])


def load(root: Path, data: dict) -> dict:
    return bac.load_config(write_config(root, data), BUILD, root)


# ---------------------------------------------------------------- template


def render_template() -> str:
    jinja2 = pytest.importorskip("jinja2")
    return jinja2.Template(TEMPLATE.read_text()).render(
        bole_hostname="bole",
        bole_timezone="Europe/Belgrade",
        bole_user="bole",
        ssh_password_auth=True,
        wifi_country="RS",
    )


def test_shipped_template_is_valid(root: Path) -> None:
    write_config(root, render_template())
    assert run(root, "--check") == 0


def test_shipped_template_applies(root: Path) -> None:
    write_config(root, render_template())
    assert run(root) == 0
    assert (root / "etc/hostname").read_text() == "bole\n"
    assert (root / "etc/netplan/60-bole.yaml").exists()


# ---------------------------------------------------------------- validation


@pytest.mark.parametrize(
    ("data", "message"),
    [
        ({"hostnme": "x"}, "unknown setting 'hostnme'"),
        ({"wifi": {"ssid": "x"}}, "unknown setting 'wifi.ssid'"),
        ({"hostname": "bad_name"}, "hostname"),
        ({"timezone": "Mars/Olympus"}, "unknown 'timezone'"),
        ({"wifi": {"networks": [{"ssid": "x", "password": "short"}]}}, "8-63"),
        ({"wifi": {"networks": [{"ssid": "x", "password": 12345678}]}}, "in quotes"),
        ({"wifi": {"networks": [{"ssid": 1234, "password": "longenough"}]}}, "quoted text"),
        ({"wifi": {"networks": [{"ssid": "x", "pasword": "longenough"}]}}, "wifi.networks[1].pasword"),
        ({"wifi": {"country": "Serbia"}}, "country"),
        ({"user": {"password": "a", "password_hash": "$6$x"}}, "only one"),
        ({"user": {"password_hash": "plain"}}, "crypt hash"),
        ({"user": {"ssh_authorized_keys": ["not a key"]}}, "not a public key"),
        ({"ros": {"domain_id": 500}}, "domain_id"),
        ({"ros": {"rmw": "cyclone"}}, "rmw"),
        ({"ros": {"deploy_key": "../etc/shadow"}}, "deploy_key"),
        ({"ros": {"deploy_key": "missing_key"}}, "not found"),
        ({"ros": {"workspace": "relative/ws"}}, "workspace"),
        ({"ethernet": {"dhcp": False}}, "ethernet.address"),
        ({"ssh": {"password_auth": "yes"}}, "true or false"),
    ],
)
def test_invalid_configs_are_rejected(root: Path, data: dict, message: str) -> None:
    with pytest.raises(bac.ConfigError) as exc:
        load(root, data)
    assert message in str(exc.value)


def test_invalid_yaml_is_rejected(root: Path) -> None:
    with pytest.raises(bac.ConfigError, match="not valid YAML"):
        bac.load_config(write_config(root, "wifi: [unclosed"), BUILD, root)


def test_missing_config_uses_defaults(root: Path) -> None:
    cfg = bac.load_config(root / "boot/firmware/bole.yaml", BUILD, root)
    assert cfg["hostname"] == "bole"
    assert cfg["wifi"]["country"] == "RS"


def test_normalisation(root: Path) -> None:
    cfg = load(root, {"hostname": "  MyBot ", "wifi": {"country": "de"}})
    assert cfg["hostname"] == "mybot"
    assert cfg["wifi"]["country"] == "DE"


# ---------------------------------------------------------------- rendering


def test_netplan_wifi_and_ethernet(root: Path) -> None:
    cfg = load(
        root,
        {
            "wifi": {
                "networks": [
                    {"ssid": "Home", "password": "password123"},
                    {"ssid": "Open"},
                    {"ssid": "Lab", "password": "labpassword", "hidden": True},
                ]
            }
        },
    )
    net = yaml.safe_load(bac.render_netplan(cfg))["network"]
    assert net["ethernets"]["bole-eth"]["dhcp4"] is True
    wlan = net["wifis"]["wlan0"]
    assert wlan["regulatory-domain"] == "RS"
    assert wlan["optional"] is True
    assert wlan["access-points"]["Home"] == {"password": "password123"}
    assert wlan["access-points"]["Open"] == {}
    assert wlan["access-points"]["Lab"] == {"password": "labpassword", "hidden": True}


def test_netplan_static_ethernet(root: Path) -> None:
    cfg = load(
        root,
        {"ethernet": {"dhcp": False, "address": "10.0.0.5/24", "gateway": "10.0.0.1", "dns": ["1.1.1.1"]}},
    )
    eth = yaml.safe_load(bac.render_netplan(cfg))["network"]["ethernets"]["bole-eth"]
    assert eth["addresses"] == ["10.0.0.5/24"]
    assert eth["routes"] == [{"to": "default", "via": "10.0.0.1"}]
    assert eth["nameservers"] == {"addresses": ["1.1.1.1"]}
    assert "dhcp4" not in eth


def test_netplan_nothing_enabled(root: Path) -> None:
    assert bac.render_netplan(load(root, {"ethernet": {"enabled": False}})) is None


def test_authorized_keys_keeps_unmanaged_keys() -> None:
    existing = "ssh-ed25519 AAAAmanual me@pc\n"
    out = bac.render_authorized_keys(existing, ["ssh-ed25519 AAAAnew a@b"])
    assert "AAAAmanual" in out and "AAAAnew" in out
    # Re-rendering with a different key replaces only the managed block
    out2 = bac.render_authorized_keys(out, ["ssh-rsa AAAAother c@d"])
    assert "AAAAmanual" in out2 and "AAAAother" in out2 and "AAAAnew" not in out2
    # Removing all keys drops the block
    assert bac.render_authorized_keys(out2, []) == existing


def test_ros_env_is_shell_safe(root: Path) -> None:
    cfg = load(
        root,
        {
            "ros": {
                "repo": "https://example.com/r.git",
                "launch": "ros2 launch pkg a.launch.py use_sim:=false",
                "domain_id": 7,
                "rmw": "rmw_cyclonedds_cpp",
                "environment": {"FOO": "it's $HOME", "FLAG": True},
            }
        },
    )
    env = bac.render_ros_env(cfg, "/home/bole", None)
    assert "BOLE_ROS_WORKSPACE=/home/bole/ros2_ws" in env
    assert "ROS_DOMAIN_ID=7" in env
    assert "RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" in env
    assert "FLAG=true" in env
    assert "BOLE_ROS_LAUNCH='ros2 launch pkg a.launch.py use_sim:=false'" in env
    assert "FOO='it'\"'\"'s $HOME'" in env


def test_render_hosts_replaces_existing_line() -> None:
    out = bac.render_hosts("127.0.0.1 localhost\n127.0.1.1 old\n", "new")
    assert out == "127.0.0.1 localhost\n127.0.1.1 new\n"


# ---------------------------------------------------------------- applying


def test_apply_is_idempotent(root: Path, caplog: pytest.LogCaptureFixture) -> None:
    write_config(root, {"hostname": "robot", "wifi": {"networks": [{"ssid": "Home", "password": "password123"}]}})
    assert run(root) == 0
    assert (root / "etc/hostname").read_text() == "robot\n"
    assert "127.0.1.1 robot" in (root / "etc/hosts").read_text()
    assert str((root / "etc/localtime").readlink()) == "/usr/share/zoneinfo/Europe/Belgrade"
    assert oct((root / "etc/netplan/60-bole.yaml").stat().st_mode & 0o777) == "0o600"
    caplog.clear()
    caplog.set_level("INFO", logger="bole-apply-config")
    assert run(root) == 0
    assert "no changes" in caplog.text


def test_invalid_config_changes_nothing_and_reports(root: Path) -> None:
    write_config(root, {"hostname": "robot", "ros": {"deploy_key": "missing"}})
    assert run(root) == 1
    assert not (root / "etc/hostname").exists()
    assert "not found" in (root / "boot/firmware/bole-error.txt").read_text()
    # Fixing the config removes the error file
    write_config(root, {"hostname": "robot"})
    assert run(root) == 0
    assert not (root / "boot/firmware/bole-error.txt").exists()


def test_deploy_key_is_copied_and_removed(root: Path) -> None:
    (root / "boot/firmware/deploy_key").write_text("-----BEGIN KEY-----\r\nabc\r\n-----END KEY-----")
    write_config(root, {"ros": {"repo": "git@example.com:a/b.git", "deploy_key": "deploy_key"}})
    assert run(root) == 0
    key = root / "home/bole/.ssh/bole_deploy_key"
    assert key.read_text() == "-----BEGIN KEY-----\nabc\n-----END KEY-----\n"
    assert oct(key.stat().st_mode & 0o777) == "0o600"
    assert "BOLE_ROS_DEPLOY_KEY=/home/bole/.ssh/bole_deploy_key" in (root / "etc/bole/ros.env").read_text()
    write_config(root, {"ros": {"repo": "git@example.com:a/b.git"}})
    assert run(root) == 0
    assert not key.exists()


def test_password_change_runs_chpasswd_once(root: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[str]] = []
    monkeypatch.setattr(bac.subprocess, "run", lambda cmd, **kw: calls.append(cmd))
    write_config(root, {"user": {"password_hash": "$6$salt$hash"}, "ethernet": {"enabled": False}})
    args = ["--root", str(root)]
    assert bac.main(args) == 0
    assert any(c[0] == "chpasswd" and "-e" in c for c in calls)
    calls.clear()
    assert bac.main(args) == 0
    assert not any(c[0] == "chpasswd" for c in calls)
