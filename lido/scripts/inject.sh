#!/usr/bin/env bash
# Bake the provisioning payload into the flashed USB/SD card's ext4 rootfs using
# debugfs — NO root required (the `disk` group gives raw read/write, debugfs edits
# ext4 offline). Run from the repo root on `c` (so payload/ paths resolve).
#
# Target partition comes only from find-usb.sh (paranoid USB-only gate); we then pick
# the armbi_root partition on that USB disk. The NVMe is never reachable here.
source "$(dirname "$0")/lib.sh"
# e2fsprogs tools live in /usr/sbin, which a non-login SSH shell omits from PATH.
DEBUGFS=$(command -v debugfs || echo /usr/sbin/debugfs)
E2FSCK=$(command -v e2fsck || echo /usr/sbin/e2fsck)
[ -x "$DEBUGFS" ] || die "debugfs not found (e2fsprogs)"
[ -x "$E2FSCK" ]  || die "e2fsck not found (e2fsprogs)"
PAYLOAD="payload"
[ -d "$PAYLOAD/opt-lido" ] || die "run from repo root: $PAYLOAD/opt-lido missing"

# Proven vendor SPI firmware (factory_spi.img) bundled so stage1 can flashcp it on the
# board — kept OUT of git (large), sourced from the build host. Checksum travels with it.
SPI_FW="${LIDO_SPI_FW:-$HOME/factory_spi.img}"
[ -f "$SPI_FW" ] || die "SPI firmware not found: $SPI_FW (set LIDO_SPI_FW=/path/to/factory_spi.img)"
SPI_SHA=$(mktemp)
echo "$(sha256sum "$SPI_FW" | awk '{print $1}')  spi.img" > "$SPI_SHA"
log "bundling SPI firmware $SPI_FW ($(stat -c%s "$SPI_FW") bytes)"

DEV=$("$(dirname "$0")/find-usb.sh")            # dies unless a USB disk qualifies
# choose the Armbian root partition on that USB disk
PART=$(lsblk -lno PATH,LABEL "$DEV" | awk '$2=="armbi_root"{print $1; exit}')
[ -n "$PART" ] || PART="${DEV}1"
[ -b "$PART" ] || die "root partition not found on $DEV (looked for armbi_root / ${DEV}1)"

# Re-assert the parent disk is the USB we selected (no surprises).
parent="/dev/$(lsblk -no PKNAME "$PART" 2>/dev/null)"
[ "$parent" = "$DEV" ] || die "safety: $PART parent ($parent) != selected USB ($DEV)"
log "injecting payload into $PART (on $DEV)"

# debugfs runs a script of commands. rm-before-write makes re-injection idempotent;
# "File not found" on first run is expected and filtered from the log.
script=$(mktemp)
{
    echo "mkdir /opt"
    echo "mkdir /opt/lido"
    for f in lido.conf firstboot.sh stage1.sh stage2.sh; do
        echo "rm /opt/lido/$f"
        echo "write $PAYLOAD/opt-lido/$f /opt/lido/$f"
    done
    # bundle the proven vendor SPI firmware + its checksum
    echo "mkdir /opt/lido/firmware"
    echo "rm /opt/lido/firmware/spi.img"
    echo "write $SPI_FW /opt/lido/firmware/spi.img"
    echo "rm /opt/lido/firmware/spi.img.sha256"
    echo "write $SPI_SHA /opt/lido/firmware/spi.img.sha256"
    echo "rm /etc/systemd/system/lido-provision.service"
    echo "write $PAYLOAD/lido-provision.service /etc/systemd/system/lido-provision.service"
    # enable the unit: symlink in multi-user.target.wants -> the unit file
    echo "rm /etc/systemd/system/multi-user.target.wants/lido-provision.service"
    echo "symlink /etc/systemd/system/multi-user.target.wants/lido-provision.service /etc/systemd/system/lido-provision.service"
} >"$script"

"$DEBUGFS" -w -f "$script" "$PART" 2>&1 \
    | grep -viE "debugfs 1\.|Using EXT2FS|File not found by ext2_lookup|rm:.*File not found" || true
rm -f "$script" "$SPI_SHA"

log "verifying injection"
"$DEBUGFS" -R "ls /opt/lido" "$PART" 2>&1 | tr ' ' '\n' | grep -E "lido.conf|firstboot|stage1|stage2" | sort -u
# confirm the bundled firmware landed with a sane size (16 MiB SPI image)
fwsz=$("$DEBUGFS" -R "stat /opt/lido/firmware/spi.img" "$PART" 2>/dev/null | grep -oE 'Size: [0-9]+' | grep -oE '[0-9]+' | head -1)
[ "${fwsz:-0}" -ge 1000000 ] && log "SPI firmware bundled ($fwsz bytes)" || die "SPI firmware missing/short on card (got '${fwsz:-none}')"
"$DEBUGFS" -R "stat /etc/systemd/system/multi-user.target.wants/lido-provision.service" "$PART" 2>&1 \
    | grep -qi "Fast link dest" && log "service enabled (symlink OK)" || die "service symlink missing"

# debugfs edits can leave the fs needing a check; fix it so first boot is clean.
log "fsck after edit"
"$E2FSCK" -fy "$PART" >/dev/null 2>&1 || true
log "inject complete — card is a full lido installer"
