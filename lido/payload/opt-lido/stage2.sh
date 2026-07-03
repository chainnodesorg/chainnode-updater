#!/usr/bin/env bash
# STAGE 2 (runs as root on the NVMe-booted system): configure the node — user, time,
# Docker, eth-docker (installed only, NOT configured), blockchain volume, network,
# sshd, log rotation — then disable provisioning so boot 3+ is a clean system.
#
# VALIDATED end-to-end on a fresh OPi5+ (2026-07-02). Non-fatal steps warn and continue;
# the stage only marks itself done at the very end AND only if Docker is up (guard below),
# so a mid-way failure (e.g. clock/apt race) simply retries on the next boot.
set -uo pipefail
source /opt/lido/lido.conf
echo "### STAGE2 $(date -u) — configure node"
[ "$(id -u)" = 0 ] || { echo "FATAL: stage2 must run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

# hostname
hostnamectl set-hostname "$HOSTNAME_TARGET" 2>/dev/null || echo "$HOSTNAME_TARGET" >/etc/hostname

# user + password + groups (full device control)
id "$PROV_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$PROV_USER"
echo "${PROV_USER}:${PROV_PASS}" | chpasswd
for g in $USER_GROUPS; do getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$PROV_USER"; done

# time: UTC + Armbian's timesyncd
timedatectl set-timezone UTC 2>/dev/null || ln -sf /usr/share/zoneinfo/UTC /etc/localtime
systemctl enable --now systemd-timesyncd 2>/dev/null || true

# WAIT for the clock to sync BEFORE any apt. Debian trixie verifies repo signatures with
# sqv, which rejects any signature whose validity window starts in the future — so a board
# that boots with a behind clock fails EVERY repo ("Not live until <date>") and Docker never
# installs. Block until timesyncd sets the clock (bounded), so apt sees valid signatures.
echo "waiting for NTP clock sync before apt..."
for _i in $(seq 1 60); do
    [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] && break
    sleep 2
done
[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] \
    && echo "clock synced: $(date -u +%FT%TZ)" \
    || echo "WARN: NTP not synced after 120s — apt signature checks may fail"

# base packages
apt-get update -y
apt-get install -y net-tools iputils-ping make jq mc curl ca-certificates git rsync gnupg

# Docker from the official repo, pinned to `c`'s versions where possible.
install -m0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    >/etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y "docker-ce=$DOCKER_VER" "docker-ce-cli=$DOCKER_VER" containerd.io docker-buildx-plugin docker-compose-plugin \
    || apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# log rotation so the 4 TB can't fill from logs: docker json-file caps + journald cap.
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "50m", "max-file": "5" } }
JSON
systemctl restart docker || true
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=500M\n' >/etc/systemd/journald.conf.d/lido-cap.conf
systemctl restart systemd-journald || true

# one big blockchain volume on the NVMe root, owned by the operator user
mkdir -p "$BC_VOLUME"
chown "$PROV_USER:$PROV_USER" "$BC_VOLUME"

# eth-docker: CHECK OUT only (no client choice, no .env, no `ethd up`). Operator configures.
if [ ! -d "$ETHD_DIR/.git" ]; then
    git clone "$ETHD_REPO" "$ETHD_DIR"
fi
chown -R "$PROV_USER:$PROV_USER" "$ETHD_DIR"
# We deliberately do NOT run `./ethd install`: eth-docker refuses to run it as root ("Please
# install Eth Docker as a non-root user"), and as the user it would need passwordless sudo.
# Everything it does — Docker engine + compose, the docker group, prerequisite packages — we
# already set up above, so the checkout is ready. The operator runs `./ethd config && ./ethd up`
# and points chain data at $BC_VOLUME there (eth-docker owns its own .eth/ dir — we don't touch
# it; there is no pre-set data symlink to make).

# network: both wired NICs -> DHCP; WiFi radio on but no saved connection.
# This image ships systemd-networkd (no NetworkManager / nmcli), where every ethernet
# already gets DHCP by default (that's how this box got its lease). So only use nmcli if
# it's actually present; otherwise just make sure networkd is up and the wifi radio is on.
if command -v nmcli >/dev/null 2>&1; then
    nmcli radio wifi on || true
    for dev in $(nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="ethernet"{print $1}'); do
        nmcli connection show "dhcp-$dev" >/dev/null 2>&1 || \
            nmcli connection add type ethernet ifname "$dev" con-name "dhcp-$dev" \
                ipv4.method auto ipv6.method auto autoconnect yes || true
    done
else
    systemctl enable --now systemd-networkd 2>/dev/null || true      # wired DHCP is the default
    command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi 2>/dev/null || true  # radio on, no connection
fi

# sshd on + verify it answers on localhost
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
sleep 2
if (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null; then echo "sshd OK on localhost:22"; exec 3>&- || true
else echo "WARN: sshd not answering on localhost:22"; fi

# headless console banner: show ALL IPv4 addresses on tty1 BEFORE the login prompt,
# so an operator with only a monitor (no keyboard) can read the box's DHCP IPs.
# Mirrors `c`'s getty ExecStartPre approach; stock agetty's --noclear keeps it on screen.
install -d /usr/local/sbin
cat >/usr/local/sbin/show-sysinfo <<'SYS'
#!/bin/bash
# Printed on tty1 before login. Lists board, hostname, and every global IPv4 per iface.
VERSION=$(awk -F= '/^VERSION=/{gsub(/"/,"",$2);print $2}' /etc/armbian-release 2>/dev/null)
BOARD=$(awk -F= '/^BOARD_NAME=/{gsub(/"/,"",$2);print $2}' /etc/armbian-release 2>/dev/null)
echo ""
echo " ${BOARD:-Orange Pi} | Armbian ${VERSION} | $(hostname) | Linux $(uname -r)"
echo ""
echo " IPv4 addresses:"
IPS=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2" "$4}' \
        | grep -Ev '^(lo|docker|veth|br-|virbr)')
if [ -n "$IPS" ]; then
    echo "$IPS" | while read -r ifc cidr; do printf "   %-12s %s\n" "$ifc" "$cidr"; done
else
    echo "   (no DHCP lease yet — check the cable / switch)"
fi
echo ""
SYS
chmod +x /usr/local/sbin/show-sysinfo
install -d /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/pre-info.conf <<'CONF'
[Service]
ExecStartPre=/usr/local/sbin/show-sysinfo
CONF
systemctl daemon-reload || true
# getty@tty1 already started at boot (before this drop-in existed), so restart it now to
# show the IP banner on THIS first stage2 boot — otherwise it only appears next reboot.
systemctl restart getty@tty1 2>/dev/null || true

# finalize privileges — re-apply group membership AFTER Docker (and the packages above)
# created their groups. The first pass at user-creation ran before the `docker` group
# existed, so `getent group docker` failed there; `docker` (and any late-created group)
# only actually sticks here. usermod -aG is idempotent, so re-running is safe.
for g in $USER_GROUPS; do getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$PROV_USER"; done

# let `user` power the box off / reboot and ping without a password prompt (headless
# assembly-line ops). `c` has no dedicated group for this — ping is setuid-root and
# shutdown goes through sudo — so we grant it explicitly, scoped to these exact commands.
cat >/etc/sudoers.d/lido-power <<SUDO
${PROV_USER} ALL=(ALL) NOPASSWD: /usr/sbin/poweroff, /sbin/poweroff, /usr/sbin/reboot, /sbin/reboot, /usr/sbin/shutdown, /sbin/shutdown, /usr/sbin/halt, /sbin/halt, /usr/bin/ping
SUDO
chmod 0440 /etc/sudoers.d/lido-power
visudo -cf /etc/sudoers.d/lido-power >/dev/null 2>&1 || { echo "WARN: bad sudoers drop-in, removing"; rm -f /etc/sudoers.d/lido-power; }

# Refuse to mark "done" if Docker didn't actually land — a Docker-less node is a failed
# provision (usually the clock/apt race above). Leaving provisioning ENABLED means the next
# boot retries stage2, by which time the clock is synced and apt works.
if ! command -v docker >/dev/null 2>&1 || ! systemctl is-active --quiet docker; then
    echo "FATAL: Docker missing/inactive — NOT marking done; will retry on next boot."
    echo ">>> Reboot the board to retry (clock is synced now, so apt will succeed)."
    exit 1
fi

# done — disable provisioning so the next boot is a clean working system.
rm -f /etc/systemd/system/multi-user.target.wants/lido-provision.service
touch "$STATE_DIR/stage2.done"
echo "### STAGE2 complete — node ready."
echo ">>> Operator: cd $ETHD_DIR && ./ethd config (point data at $BC_VOLUME) && ./ethd up"
