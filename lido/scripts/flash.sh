#!/usr/bin/env bash
# Write a decompressed Armbian .img to the first inserted USB drive, then read-back
# verify. The target is chosen solely by find-usb.sh (paranoid USB-only guard), and
# re-asserted here immediately before the write — there is no way to pass a non-USB
# device in. Destructive by design; aborts on any doubt.
#
# Usage: flash.sh <image.img>
source "$(dirname "$0")/lib.sh"
need dd; need lsblk; need sha256sum

IMG=${1:?usage: flash.sh <image.img>}
[ -f "$IMG" ] || die "image not found: $IMG (run 'make fetch' first)"

DEV=$("$(dirname "$0")/find-usb.sh")   # dies if no USB device qualifies
name=$(basename "$DEV")

# Re-assert the two strongest invariants right before writing (belt and suspenders).
[ "$(lsblk -dno TRAN "$DEV" 2>/dev/null)" = usb ]        || die "re-check failed: $DEV is not USB"
[ "$(cat "/sys/block/$name/removable" 2>/dev/null)" = 1 ] || die "re-check failed: $DEV not removable"

# Unmount anything mounted off this device so the write is consistent.
while read -r part mnt; do
    [ -n "$mnt" ] || continue
    warn "unmounting $part ($mnt)"
    umount "$part" || die "cannot unmount $part — aborting"
done < <(lsblk -lno PATH,MOUNTPOINT "$DEV" | tail -n +2)

isz=$(stat -c %s "$IMG")
# Use O_DIRECT for BOTH write and read-back so we never build a big dirty page cache that
# has to be flushed all at once. On the build host `c` (hardware watchdog, 22s timeout), a
# buffered write+read-back of a 1.6 GB image to a slow USB-2 stick starved PID 1 past the
# timeout and the watchdog HARD-RESET the machine. Direct I/O streams at device speed and
# keeps the host responsive. O_DIRECT needs 4 KiB+ alignment; our image is 4 MiB-aligned,
# else fall back to buffered (and warn).
if [ $((isz % 4194304)) -eq 0 ]; then DW=oflag=direct; DR=iflag=direct; blocks=$((isz/4194304))
else warn "image not 4MiB-aligned ($isz) — using buffered I/O (may stress the host)"; DW=; DR=; fi

log "writing $IMG ($((isz/1024/1024)) MiB) -> $DEV"
dd if="$IMG" of="$DEV" bs=4M $DW conv=fsync status=progress
sync

log "verifying read-back ($((isz/1024/1024)) MiB)"
img_sum=$(sha256sum "$IMG" | awk '{print $1}')
if [ -n "$DR" ]; then
    dev_sum=$(dd if="$DEV" bs=4M $DR count="$blocks" 2>/dev/null | sha256sum | awk '{print $1}')
else
    dev_sum=$(head -c "$isz" "$DEV" | sha256sum | awk '{print $1}')
fi
[ "$img_sum" = "$dev_sum" ] || die "VERIFY FAILED — read-back differs from image on $DEV"
log "flash OK and verified on $DEV"
