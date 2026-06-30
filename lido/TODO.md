# TODO — lido

## Done
- [x] Research (eth-docker, Lido CSM, OPi5+ NVMe/SPI boot, `c` inventory) → `../.claude/research/`.
- [x] SPEC drafted + revised to "install eth-docker only; operator configures".
- [x] Hardware/media triage; counterfeit-flash detection method proven (O_DIRECT).
- [x] Build-host toolchain: `Makefile`, `lib.sh`, `find-usb.sh`, `fetch.sh`,
      `flash.sh`, `verify-usb.py`, `.gitignore`, `README`.

## Next (runnable on `c` now)
- [ ] Run `make fetch` on `c`, confirm Armbian image verifies + eth-docker clones.
- [ ] Run `make flash` to the genuine SD-card-in-USB-reader; confirm read-back verify.
- [ ] Boot the flashed media on a spare OPi5+ to confirm it comes up.

## Pending spare-device validation (then implement)
- [ ] `stage1.sh` — write u-boot to SPI (`armbian-install` "Boot from SPI"; manual
      `rkspi_loader.img` fallback), wipe + single ext4 over NVMe, install Armbian,
      copy payload, install stage2 oneshot, set hostname/user. Confirm boot order →
      decide power-off-vs-reboot between boot 1 and 2.
- [ ] `stage2.sh` — Docker (pin to `c` versions) + pkgs (net-tools, gmake, jq, mc);
      big NVMe blockchain volume; `./ethd install` (no `ethd up`); network (2× wired
      DHCP, WiFi radio up no-connect); sshd (verify `ssh localhost`); timesyncd UTC;
      log rotation (journald cap + docker json-file caps + logrotate); self-disable.
- [ ] `config/` units + drop-ins; `make payload` / `make image`.
