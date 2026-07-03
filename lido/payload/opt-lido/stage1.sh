#!/usr/bin/env bash
# STAGE 1 — headless, faithful replication of `armbian-install` option 4
# ("Boot from MTD/SPI Flash — system on NVMe") for Orange Pi 5 Plus.
#
# Verified against c (the working reference) + the armbian-install source:
#   * NVMe is FILESYSTEM-ONLY (no bootloader at raw offsets); SPI is the sole loader.
#   * NVMe layout = GPT + single ext4 spanning the disk — exactly what c boots from.
#   * SPI gets the OrangePi VENDOR u-boot (factory_spi.img). Writing the ARMBIAN u-boot
#     (c's type, rkspi_loader.img) BRICKS these boards — c is NOT the bootloader reference.
#     Written with flashcp on the CHAR device /dev/mtd0 (erase+program+verify), NEVER dd to
#     the cached /dev/mtdblock0 — that raw no-erase write also bricked boards.
set -euo pipefail
source /opt/lido/lido.conf
# Any failure: shout it (this reaches HDMI via firstboot's tee) and DON'T power off — leave
# the board on so the operator can read what went wrong instead of a silent shutdown.
trap 'rc=$?; echo ""; echo "########## STAGE1 FAILED (exit $rc) near line $LINENO — board left ON. Read above / $LOG, then reboot with the card to retry. ##########"' ERR
echo "### STAGE1 $(date -u) — armbian-install option-4 replication (NVMe + SPI, matched)"
[ "$(id -u)" = 0 ] || { echo "FATAL: must be root"; exit 1; }

# Board gate (refuse anything but OPi5+/RK3588).
br=$(awk -F= '/^BOARD=/{gsub(/"/,"",$2);print $2}' /etc/armbian-release 2>/dev/null)
[ "$br" = "${EXPECT_BOARD:-orangepi5-plus}" ] || { echo "FATAL: BOARD='$br' != ${EXPECT_BOARD:-orangepi5-plus}"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
command -v rsync  >/dev/null || { apt-get update -y && apt-get install -y rsync; }
command -v parted >/dev/null || apt-get install -y parted

NVME=${NVME_DEV:-/dev/nvme0n1}
[ -b "$NVME" ] || { echo "FATAL: $NVME not present"; exit 1; }

# ---- 1) partition + format NVMe (armbian-install: wipe 10M, gpt, ext4 0%-100%) ----
echo "wiping + partitioning $NVME (gpt, single ext4)"
dd if=/dev/zero of="$NVME" bs=1M count=10 conv=fsync status=none
partprobe -s "$NVME" 2>/dev/null || true
parted -s "$NVME" mktable gpt
parted -s "$NVME" mkpart primary ext4 0% 100%
partprobe -s "$NVME"; sleep 2
PART="${NVME}p1"
[ -b "$PART" ] || { echo "FATAL: $PART did not appear"; exit 1; }
mkfs.ext4 -qF "$PART"

# ---- 2) rsync rootfs (INCLUDING /boot; keep /opt/lido so stage2 runs on NVMe) ----
MP=/mnt/nvme-root; mkdir -p "$MP"; mount "$PART" "$MP"
echo "copying rootfs to NVMe (several minutes)"
rsync -aHAXx --delete \
    --exclude=/dev/* --exclude=/proc/* --exclude=/sys/* --exclude=/tmp/* \
    --exclude=/run/* --exclude=/mnt/* --exclude=/media/* --exclude="/lost+found" \
    / "$MP/"
mkdir -p "$MP"/{dev,proc,sys,tmp,run,mnt,media}

# ---- 3) fstab + armbianEnv rootdev (option-4 MTD branch: SPI u-boot reads these) ----
UUID=$(blkid -s UUID -o value "$PART")
[ -n "$UUID" ] || { echo "FATAL: no UUID for $PART"; umount "$MP"; exit 1; }
echo "NVMe root UUID=$UUID"
printf 'UUID=%s / ext4 defaults,noatime,commit=600,errors=remount-ro 0 1\n' "$UUID" > "$MP/etc/fstab"
if [ -f "$MP/boot/armbianEnv.txt" ]; then
    sed -i "s,^rootdev=.*,rootdev=UUID=$UUID,g" "$MP/boot/armbianEnv.txt"
    grep -q '^rootdev'    "$MP/boot/armbianEnv.txt" || echo "rootdev=UUID=$UUID" >> "$MP/boot/armbianEnv.txt"
    sed -i "s,^rootfstype=.*,rootfstype=ext4,g"      "$MP/boot/armbianEnv.txt"
    grep -q '^rootfstype' "$MP/boot/armbianEnv.txt" || echo "rootfstype=ext4" >> "$MP/boot/armbianEnv.txt"
fi
# Mark THIS board's NVMe as installed. The marker lives on the BOARD (its NVMe), not on the
# card — so one card provisions the whole fleet. firstboot checks for this on the next
# removable boot instead of a card-side marker (which made the card single-use).
mkdir -p "$MP/opt/lido"; touch "$MP/opt/lido/stage1.done"
sync; umount "$MP"

# ---- 4) SPI bootloader: the VENDOR image (factory_spi.img) — the ONLY one that doesn't brick ----
# HARD-WON, DO NOT FORGET: the fleet ships the OrangePi VENDOR u-boot. Writing the ARMBIAN
# u-boot (c's type, rkspi_loader.img) BRICKS these boards — c is NOT the bootloader reference.
# We tried it (matched-pair theory) and bricked board #6. So we write the vendor image we
# captured from a working fleet board, bundled at /opt/lido/firmware/spi.img, via flashcp on
# /dev/mtd0 (erase+program+verify) — never dd to the cached /dev/mtdblock0.
# NOTE: vendor u-boot does not brick and drives HDMI. The "inconsistent NVMe boot" chased
# earlier was very likely THIS card-reuse bug (a 2nd board on a used card skipped the install
# entirely via a card-side marker) — the board simply never got installed. Re-validate now.
FW="$STATE_DIR/firmware/spi.img"
[ -f "$FW" ] || { echo "FATAL: bundled SPI firmware missing: $FW"; exit 1; }
[ -f "$FW.sha256" ] && { ( cd "$(dirname "$FW")" && sha256sum -c "$(basename "$FW").sha256" ) \
    || { echo "FATAL: SPI firmware checksum mismatch — refusing to flash"; exit 1; }; }
MTD=/dev/mtd0
[ -c "$MTD" ] || { echo "FATAL: $MTD (char mtd) missing"; exit 1; }
command -v flashcp >/dev/null || { apt-get update -y && apt-get install -y mtd-utils; }
echo "SPI: erase + program + verify (vendor u-boot)  $FW -> $MTD"
flash_erase --quiet "$MTD" 0 0        # full chip erase (clean slate)
flashcp -v "$FW" "$MTD"               # program + read-back verify; set -e aborts on mismatch
sync
echo "SPI write verified OK (vendor u-boot)"

# (NO card-side marker — the done-flag was written to the NVMe above, so this card stays
# reusable for the whole fleet.)
echo "### STAGE1 complete — NVMe installed + vendor SPI u-boot. This board is done."
echo ">>> REMOVE THE CARD and power on -> it boots from NVMe and runs phase 2."
echo ">>> The SAME card provisions the next board — just plug it into the next one."
sync; systemctl poweroff
