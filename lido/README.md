# lido — Armbian USB flasher for the chainnode fleet

Builds a bootable Armbian Orange Pi 5 Plus USB and (later) provisions it into a clean
node with Docker + eth-docker installed and a large NVMe blockchain volume. The
operator picks clients/config himself (`ethd config`). See `SPEC.md` and
`../.claude/research/lido-provisioning.md`.

## Build host
Everything runs on **`c`** (Linux, has the USB reader). Reach it with **Tailscale
down** — it's a LAN host: `ssh -o HostName=192.168.14.242 c`.

## Run
```sh
rsync -a --delete ./ c:~/lidoflash/          # sync this folder to the build host
ssh c 'cd ~/lidoflash && make fetch'         # Armbian image (verified) + eth-docker
ssh c 'cd ~/lidoflash && make verify-usb'    # OPTIONAL, DESTRUCTIVE counterfeit test
ssh c 'cd ~/lidoflash && make flash'         # write Armbian to the first USB drive
```

`make flash` and `make verify-usb` only ever touch a device that passes **every** USB
check in `scripts/find-usb.sh` (`TRAN=usb`, `removable=1`, sysfs `/usb` path, udev
`ID_BUS=usb`, not root, not `nvme*`/`mmcblk*`). `c`'s NVMe can never be selected.

## Layout
- `Makefile` — `fetch` / `verify-usb` / `flash` / `clean` (build-host targets).
- `scripts/lib.sh` — logging + fail-loud helpers.
- `scripts/find-usb.sh` — paranoid first-USB-drive selector (the safety gate).
- `scripts/fetch.sh` — download/verify Armbian, clone eth-docker.
- `scripts/flash.sh` — write image to USB + read-back verify.
- `scripts/verify-usb.py` — O_DIRECT offset-encoded capacity test.
- `build/` — artifacts (gitignored).

## Status
Build-host toolchain implemented and runnable. **On-device provisioning** (stage1:
SPI u-boot + NVMe install; stage2: users/network/sshd/time/logs, Docker, eth-docker
install, blockchain volume) is **pending validation on a spare box** — `make image`/
`payload` deliberately fail until then. See `SPEC.md` §5.
