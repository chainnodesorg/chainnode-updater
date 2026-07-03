#!/usr/bin/env bash
# Clone the PROVEN SPI bootloader from the host this runs on (must be c — an
# Orange Pi 5 Plus that boots NVMe from SPI) into build/spi/. This exact image is
# what gets flashed to the fleet's SPI: it is empirically known to boot the identical
# hardware, unlike the distro package's rkspi_loader.img that bricked boards #1/#2.
#
# Run via `make capture-spi` on c (vany is in the `disk` group → can read mtdblock0).
source "$(dirname "$0")/lib.sh"
need dd; need sha256sum
MTD=/dev/mtdblock0
OUT=build/spi

[ -e "$MTD" ] || die "$MTD not present — run this on an Orange Pi 5 Plus (c), not your workstation"
br=$(awk -F= '/^BOARD=/{gsub(/"/,"",$2);print $2}' /etc/armbian-release 2>/dev/null)
soc=$(awk -F= '/^BOOT_SOC=/{gsub(/"/,"",$2);print $2}' /etc/armbian-release 2>/dev/null)
[ "$br" = orangepi5-plus ] || die "this host BOARD='$br', expected orangepi5-plus — wrong machine to clone SPI from"
[ "$soc" = rk3588 ]        || die "this host BOOT_SOC='$soc', expected rk3588"

mkdir -p "$OUT"
log "cloning proven SPI $MTD (16 MiB) from $(hostname) [$br/$soc]"
dd if="$MTD" of="$OUT/spi.img" bs=1M
sz=$(stat -c %s "$OUT/spi.img")
[ "$sz" = 16777216 ] || die "captured $sz bytes, expected 16777216 (16 MiB)"
( cd "$OUT" && sha256sum spi.img > spi.img.sha256 )
log "captured: $OUT/spi.img  sha256=$(awk '{print $1}' "$OUT/spi.img.sha256")"
log "re-run 'make installer' to bundle this proven image into the card."
