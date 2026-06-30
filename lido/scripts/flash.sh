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
log "writing $IMG ($((isz/1024/1024)) MiB) -> $DEV"
dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
sync

log "verifying read-back ($((isz/1024/1024)) MiB)"
img_sum=$(sha256sum "$IMG" | awk '{print $1}')
dev_sum=$(head -c "$isz" "$DEV" | sha256sum | awk '{print $1}')
[ "$img_sum" = "$dev_sum" ] || die "VERIFY FAILED — read-back differs from image on $DEV"
log "flash OK and verified on $DEV"
