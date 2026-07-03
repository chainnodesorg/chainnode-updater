#!/usr/bin/env bash
# First-boot dispatcher (run by lido-provision.service every boot until stage2 done).
# Picks the stage from WHERE we booted: removable media -> stage1 (install to NVMe),
# NVMe -> stage2 (configure). State markers make each stage run once.
set -uo pipefail
source /opt/lido/lido.conf
mkdir -p "$STATE_DIR"
# Log to a FILE only — reliable. Do NOT route the install's own stdout through a tee to
# /dev/tty1: that raised "tee: io error", broke the pipe, and SIGPIPE-killed stage1 partway
# through the install (right after partitioning) -> half-done board = brick. Any future HDMI
# mirror MUST be an isolated background reader that can never touch the install's stdout.
exec >>"$LOG" 2>&1

echo "=== lido firstboot $(date -u) ==="
root_src=$(findmnt -no SOURCE / 2>/dev/null || true)
echo "root device: $root_src"

case "$root_src" in
    *nvme*)
        # Booted from NVMe -> configuration stage.
        [ -f "$STATE_DIR/stage2.done" ] && { echo "stage2 already done"; exit 0; }
        /bin/bash /opt/lido/stage2.sh
        ;;
    *)
        # Booted from the removable installer. Decide whether to install by looking at THIS
        # board's OWN NVMe, NOT a marker on the card. stage1 runs from the card, so a card-side
        # "done" marker made the card SINGLE-USE: after it provisioned one board, every next
        # board saw the marker, skipped the install, and just powered off. The marker now lives
        # on the board's NVMe, so one card provisions the whole fleet.
        prov=no
        if [ -b "${NVME_DEV}p1" ]; then
            _m=$(mktemp -d)
            if mount -o ro "${NVME_DEV}p1" "$_m" 2>/dev/null; then
                [ -e "$_m/opt/lido/stage1.done" ] && prov=yes
                umount "$_m" 2>/dev/null
            fi
            rmdir "$_m" 2>/dev/null
        fi
        if [ "$prov" = yes ]; then
            echo ""
            echo "##################################################################"
            echo "#  This board is already installed.  REMOVE THE CARD, power on.  #"
            echo "#  It will boot from NVMe and run phase 2 automatically.          #"
            echo "##################################################################"
            exit 0
        fi
        /bin/bash /opt/lido/stage1.sh
        ;;
esac
