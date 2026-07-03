# RUNBOOK — flashing the proven SPI firmware (no third brick)

Context: two boards bricked by flashing a wrong-build SPI u-boot. Root cause + fix in
[MEMO.md](MEMO.md). All 20 boards are identical to `c` (OPi5+ / RK3588), so **`c`'s own
working SPI is the proven firmware**. This runbook does it gated and supervised.

Reach `c`: it's a LAN host, **Tailscale DOWN**, `ssh -o HostName=<c-ip> c` (IP changes by
location — confirm the current one).

## 0. Prep (already done, offline)
- `stage1` SPI step now: refuses unless `BOARD=orangepi5-plus`/`BOOT_SOC=rk3588`; flashes
  ONLY `/opt/lido/firmware/spi.img` (checksum-verified); zeroes first; `dd`→`/dev/mtdblock0`;
  read-back `cmp`; aborts-without-poweroff on any failure.
- `make capture-spi` clones c's SPI; `make installer` bundles it into the card.
- `WRITE_SPI=1` in `lido.conf`. Without the firmware bundled, stage1 **safe-aborts** (never
  flashes an unverified image).

## 1. Capture the proven firmware (on c)
```
ssh c 'cd ~/lidoflash && make capture-spi'      # dumps /dev/mtdblock0 -> build/spi/spi.img (+ .sha256)
```
Sanity: it must report 16777216 bytes and a sha256. (Optional: confirm it boots c — c
already runs from it, so it's proven.)

## 2. Recover the two bricked boards FIRST (so we're not down hardware)
Try the cheap path before maskrom:
1. Flash a **clean stock Armbian** OPi5+ image to a **microSD**, insert in the board's
   microSD slot, power on.
2. If it boots → zero the bad SPI: `sudo dd if=/dev/zero of=/dev/mtdblock0 count=4096 bs=512`
   (board now SD/NVMe-recoverable), then treat it as a fresh board.
3. If it still red-LEDs (BootROM hung on bad SPI) → **maskrom** (needs a real USB **data**
   cable + USB-A host): `rkdeveloptool ld` → `db ~/lidoflash/recover/radxa-rkbin/bin/rk35/rk3588_spl_loader_v1.22.114.bin`
   → `ef` → `rd`. Then microSD-boot.

## 3. Bake the card with proven firmware
```
# card in c's USB reader
ssh c 'cd ~/lidoflash && make installer'        # flash + inject + bundle build/spi/spi.img
# verify on card: WRITE_SPI=1, firmware present
ssh c '/usr/sbin/debugfs -R "cat /opt/lido/lido.conf" /dev/sda1 | grep -E "WRITE_SPI|EXPECT|SPI_IMG"; /usr/sbin/debugfs -R "ls -l /opt/lido/firmware" /dev/sda1'
```

## 4. Flash ONE board first (recovery on standby)
1. Card in the board's **microSD slot** + ethernet + HDMI. Power on.
2. Boot 1: stage1 installs NVMe, then (gates pass) zeroes+writes proven SPI, read-back
   verifies, **powers off**. If it stays on → a gate/verify failed; read the console, do
   NOT proceed.
3. Remove card, power on. Boot 2: should boot **NVMe** → stage2 → IP banner. `ssh user@<ip>`.
4. Only after this one is confirmed good end-to-end, do the rest.

## Hard rules (prevent brick #3)
- NEVER flash a SPI image that isn't `c`'s captured dump (checksum-verified). No package files.
- NEVER write SPI on a board whose `/etc/armbian-release` isn't `orangepi5-plus`/`rk3588`.
- ALWAYS zero-then-write-then-read-back; abort (no poweroff) on mismatch.
- Have a recovery path ready (microSD image, and ideally the maskrom data cable) BEFORE writing.
- One board at a time until proven.
