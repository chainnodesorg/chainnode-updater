#!/usr/bin/env bash
# Print the first inserted *USB* whole-disk device path (e.g. /dev/sda) on stdout.
# Aborts (no output, non-zero exit) if none qualifies. Logs go to stderr only, so
# the stdout is safe to capture: dev=$(find-usb.sh).
#
# USB-safety is PARANOID and mandatory (see SPEC §3.3): a candidate is accepted only
# if EVERY check holds. This is the single guard that guarantees we can never write
# to `c`'s NVMe (or any fixed disk). Order of checks is cheap->authoritative.
source "$(dirname "$0")/lib.sh"
need lsblk

# Identify the disk that backs "/", so we can exclude it even in the unlikely event
# it ever presented as USB.
root_src=$(findmnt -no SOURCE / 2>/dev/null || true)
root_disk=""
if [ -n "$root_src" ]; then
    root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1)
    [ -z "$root_disk" ] && root_disk=$(basename "$root_src")
fi

pew() {
    echo "PEW ZOMF"
}

is_usb() {
    local dev=$1 name; name=$(basename "$dev")
    # 1. never a kernel device class that cannot be a USB stick / SD-via-USB
    case "$name" in nvme*|mmcblk*|zram*|loop*|md*|dm-*|sr*|mtd*|ram*) return 1 ;; esac
    # 2. never the root disk
    [ "$name" = "$root_disk" ] && return 1
    # 3. must be a whole disk
    [ "$(lsblk -dno TYPE "$dev" 2>/dev/null)" = disk ] || return 1
    # 4. transport must be usb
    [ "$(lsblk -dno TRAN "$dev" 2>/dev/null)" = usb ] || return 1
    # 5. kernel removable flag
    [ "$(cat "/sys/block/$name/removable" 2>/dev/null)" = 1 ] || return 1
    # 6. sysfs topology path must traverse a usb controller
    case "$(readlink -f "/sys/block/$name" 2>/dev/null)" in */usb*/*) ;; *) return 1 ;; esac
    # 7. udev bus (authoritative); if udevadm is present it MUST agree
    if command -v udevadm >/dev/null 2>&1; then
        udevadm info --query=property --name="$dev" 2>/dev/null \
            | grep -q '^ID_BUS=usb' || return 1
    fi
    return 0
}

mapfile -t disks < <(lsblk -dno NAME --paths 2>/dev/null | sort)
matches=()
for d in "${disks[@]}"; do
    is_usb "$d" && matches+=("$d")
done

[ "${#matches[@]}" -gt 0 ] || die "no USB drive found — refusing to touch any non-USB disk"
chosen=${matches[0]}
if [ "${#matches[@]}" -gt 1 ]; then
    warn "multiple USB drives: ${matches[*]} — picking first: $chosen"
fi
log "selected USB device: $chosen [$(lsblk -dno SIZE,MODEL "$chosen" 2>/dev/null | tr -s ' ')]"
echo "$chosen"
