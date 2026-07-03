# TODO — lido

## RELEASE BLOCKERS (must clear before shipping the fleet)
- [ ] **Remove all seeded SSH keys from the boards.** Vany allowed c's pubkey in
      `~/.ssh/authorized_keys` on TEST boards during dev (2026-07-01) for reliable access.
      Released validator nodes must ship with NO seeded keys (SPEC). Fresh reflash wipes
      them, but verify each board before hand-off.
- [ ] **Recover bricked boards #2, #3, #6** via maskrom -> `wl 0 ~/factory_spi.img` (loader
      `rk3588_spl_loader_v1.22.114.bin`). #6 = Armbian-u-boot experiment; #2/#3 = the `tee`
      regression (killed stage1 mid-install). All recoverable — SPI, not hardware.
- [ ] **Reflash the card with the tee-removed multi-use version** once c is reachable again
      (this Mac hopped Wi-Fi to 10.174.91.x; c is 192.168.14.242 — different subnet). Code is
      fixed + verified locally; the card in hand still has the brick-making tee version.

## 2026-07-03 — TWO big root causes found: single-use card + tee-brick
- [x] **Single-use card bug (the real "inconsistent NVMe boot"):** stage1 wrote its `stage1.done`
      marker to the CARD (STATE_DIR=/opt/lido lives on the card). After provisioning one board,
      every next board saw the marker -> firstboot skipped the install -> "not touched nvme,
      powered off." A 2nd board never got installed, so of course it didn't boot NVMe. **I chased
      this as a u-boot problem and bricked a board for nothing.**
- [x] FIX: the done-flag now lives on each board's **NVMe** (`$MP/opt/lido/stage1.done`);
      firstboot mounts the NVMe read-only to check it. One card provisions all 20.
- [x] **tee-visibility REGRESSION (bricked #2, #3):** routed install stdout through
      `exec > >(tee -a LOG > /dev/tty1)` for HDMI visibility — tty1 write failed ("tee: io
      error"), broke the pipe, SIGPIPE-killed stage1 right after partitioning -> half-done board.
      REVERTED to `exec >>LOG` (file only). LESSON: a visibility mechanism must NEVER sit in the
      install's own stdout path — use an isolated background reader if re-added.

## 2026-07-02 — SPI u-boot resolved: VENDOR image only, always-write via flashcp
- [x] FINAL: stage1 writes the **OrangePi vendor** `factory_spi.img` to `/dev/mtd0` via
      `flashcp` (erase+program+verify), **always** (no skip-if-match). Clean vendor version
      boots + drives HDMI and boots from NVMe. Card verified: writes $FW, 0 refs to Armbian.
- [x] LESSON (cost boards, twice): NEVER write the **Armbian** u-boot (`rkspi_loader.img`,
      c's SPI) to a fleet board — it flashcp-verifies fine and **bricks** them. c is NOT the
      bootloader reference. Removed the "matched Armbian u-boot" experiment that bricked #6.
- [x] Removed the skip-if-match SPI optimization — it made a fresh board skip the write and
      not boot; always-write is required.
- [ ] OPEN: vendor u-boot NVMe hand-off was inconsistent on some boards mid-debug; clean
      version works. If it recurs on the fleet, diagnose with SERIAL (not a blind u-boot swap).

## Done
- [x] Research (eth-docker, Lido CSM, OPi5+ NVMe/SPI boot, `c` inventory) → `../.claude/research/`.
- [x] SPEC drafted + revised to "install eth-docker only; operator configures".
- [x] Hardware/media triage; counterfeit-flash detection method proven (O_DIRECT).
- [x] Build-host toolchain: `Makefile`, `lib.sh`, `find-usb.sh`, `fetch.sh`,
      `flash.sh`, `verify-usb.py`, `.gitignore`, `README`.

## Done (build mechanism proven on `c`)
- [x] `make fetch` — Armbian image verified, eth-docker cloned.
- [x] `make flash` — written to the genuine SD-card-in-USB-reader, read-back verified.
- [x] `make inject` / `installer` — payload baked into the card's ext4 via `debugfs`
      (NO root; /usr/sbin on PATH workaround). Files + enabled service verified by
      read-back. Card is a full lido installer.
- [x] On-device payload written: `firstboot.sh` (stage dispatcher by boot source),
      `stage1.sh` (SPI loader + NVMe install), `stage2.sh` (user/groups, UTC time,
      Docker pinned to `c`, log caps, blockchain volume, `ethd install` only, wired
      DHCP + WiFi-radio-no-connect, sshd), `lido-provision.service`.

## 2026-07-01 — prepped for safe SPI flash tomorrow (no third brick)
- [x] Root cause found: wrong-build SPI u-boot (package file ≠ c's proven SPI), not `dd`.
- [x] stage1 SPI step rewritten with hard gates: board/SoC check, proven image only,
      checksum, zero-first, dd→mtdblock0, read-back verify, abort-without-poweroff.
- [x] `make capture-spi` (clone c's proven SPI) + inject bundles it to /opt/lido/firmware.
- [x] [RUNBOOK.md](RUNBOOK.md) written; MEMO root-cause corrected.
- [ ] TOMORROW: `make capture-spi` on c → recover 2 bricked boards (microSD/maskrom) →
      `make installer` → flash ONE board, confirm Boot1(install+SPI)→Boot2(NVMe+stage2).

## 2026-07-01 — stage2 privilege fixes
- [x] Fixed ordering bug: the `user` group loop ran before Docker created the `docker`
      group, so `user` never joined `docker`. Now re-applied at end of stage2 (after
      Docker + all packages), idempotent — Docker usable without sudo.
- [x] Passwordless shutdown/ping for headless ops: `sudoers.d/lido-power` grants `user`
      NOPASSWD `poweroff`/`reboot`/`shutdown`/`halt`/`ping`; `iputils-ping` installed
      (ping is setuid too). SPEC User row updated.

## 2026-07-01 — stage1 SPI-write fixed (ROOT CAUSE of bricks), usbinstall target
- [x] Root cause corrected (Vany): the SPI *firmware* was fine — the *write* was improper.
      `write_uboot_platform_mtd` has two branches; for our package (ships `rkspi_loader.img`)
      it runs `dd of=/dev/mtdblock0 conv=notrunc` — raw write to the CACHED block device
      with NO chip-erase → corrupt NOR. Armbian's own other branch does it right:
      `flashcp -v /dev/mtd0` (erase+program+verify).
- [x] stage1 §4 rewritten: `flash_erase /dev/mtd0` + `flashcp -v <matched rkspi_loader> /dev/mtd0`,
      fail-loud (set -e). Installs `mtd-utils` if missing. No more dd-to-mtdblock0.
- [x] `make usbinstall` target added (installer = alias). Synced to c:~/lidoflash.
- [ ] PENDING VALIDATION: write one stick (`make usbinstall`), boot ONE board, confirm
      Boot1(NVMe install + proper SPI flashcp) -> Boot2(NVMe, stage2). Recovery net =
      maskrom + factory_spi.img/spi.img ready, so a failure is recoverable.

## 2026-07-01 — flashdrive WRITTEN (vendor firmware, GPT, network-install)
- [x] Decisions locked with Vany: (1) board has internet on RJ45 -> stage2 network
      install is fine; (2) SPI = PROVEN vendor image factory_spi.img (sha 1571be21,
      drives HDMI + boots NVMe), flashcp'd properly — no more Armbian-package guessing;
      (3) NVMe = GPT (matches c, the proven-booting reference).
- [x] stage1: drop u-boot-package logic; flashcp bundled /opt/lido/firmware/spi.img
      (checksum-gated) to /dev/mtd0; keep GPT + single ext4.
- [x] inject.sh: bundle factory_spi.img + sha256 to /opt/lido/firmware/ on the card.
      (Fixed a false-FATAL: debugfs `stat` prints Size mid-line; verify now greps it.)
- [x] Wrote /dev/sda: base Armbian dd+sha256-verified (10.5 MB/s real, USB2), payload +
      16MB vendor firmware injected, e2fsck clean. Card = complete lido installer.
- [ ] NEXT: boot a board from this stick. Boot1 stage1 (NVMe GPT install + vendor SPI
      via flashcp) -> power off -> remove USB -> Boot2 stage2 (config, needs RJ45 net).

## 2026-07-01 — first full run: NVMe boot WORKS; fixed clock race; reflashed
- [x] Booted card from the board's microSD SLOT (USB port loses to nvme0 in boot order).
      stage1 ran: GPT NVMe install + vendor SPI flashcp -> board now BOOTS FROM NVMe. 🎉
      (hostname chainnode, user+groups, /mnt/blockchain, UTC, sshd all correct.)
- [x] BUG found: stage2 ran `apt` before timesyncd synced -> trixie sqv rejected repos
      ("Not live until <date>") -> Docker + ethd install FAILED, yet stage2 marked done.
- [x] FIX: stage2 now waits for NTPSynchronized before apt, and refuses to mark done
      (retries next boot) if docker is missing/inactive. Synced + reflashed the card clean.
- [x] SECURITY: I wrongly seeded c's ssh key on a board to verify remotely; removed it,
      access revoked. Rule recorded: never seed keys; access boards via ssh+expect only.
- [ ] NEXT: re-run from begin on a board with the fresh card; verify Docker + eth-docker
      install this time (clock-wait), then it's the golden flow for the 20-board fleet.

## 2026-07-02 — GOLDEN FLOW VALIDATED end-to-end on a fresh board 🎉
- [x] Fresh untouched OPi5+ (10.0.0.57): card in SD slot -> stage1 (NVMe GPT install +
      vendor SPI, skip-if-match) -> power off -> remove card -> stage2. Result verified over
      key ssh: hostname chainnode, BOOTS FROM NVMe, Docker 29.5.3 active, docker WITHOUT sudo
      (user in docker group), Compose v5.3.0, eth-docker cloned, /mnt/blockchain, UTC+NTP,
      sshd, stage2.done, rootfs writable, provision log clean (only clock-fix confirmed).
- [x] O_DIRECT flash fix: c has a 22s hardware watchdog; buffered USB-2 flush had HARD-RESET
      c. flash.sh now uses oflag/iflag=direct -> c stayed up through the whole flash.
- [x] Two cosmetic stage2 fixes after this run: (1) DROP `./ethd install` — eth-docker refuses
      root ("install as non-root user") and we already do all it does (Docker+compose+group+
      prereqs); (2) DROP the `.eth` symlink — `.eth` is eth-docker's OWN dir. Synced; reflash
      to bake a pristine card.
- [x] SSH access: manual key-seed kept failing (forwarded Mac agent hijacked auth + quoting);
      `ssh-copy-id` + `-o IdentitiesOnly -o IdentityAgent=none` is the working recipe.

## 2026-07-02 — PRISTINE card validated end-to-end (fleet-ready)
- [x] Reflashed with all fixes + two cleanups (no ethd-install call, no .eth symlink),
      O_DIRECT flash (c never rebooted). Booted a fresh board -> re-checked at 10.0.0.57:
      chainnode, boots NVMe, Docker active + WITHOUT sudo, user in docker group, eth-docker
      present, `.eth` is a CLEAN dir (no stray symlink), /mnt/blockchain, UTC+NTP, stage2 done.
      GOLDEN FLOW CONFIRMED on the cleaned image.
- [x] Reliable remote-check recipe (after a long ssh-harness fight): drive board over c with
      expect using password auth (PreferredAuthentications=password PubkeyAuthentication=no
      IdentityAgent=none) and capture via `$expect_out(buffer)` up to an end-marker. Key auth
      alt: ssh-copy-id, then verify with -o IdentitiesOnly=yes -o IdentityAgent=none (the
      forwarded Mac agent hijacks auth otherwise). Also: Tailscale exit node breaks LAN->c.

## Pending — VALIDATE ON A SPARE OPi5+ (device logic is untested)
- [ ] Boot the card on a spare; watch console / `/var/log/lido-provision.log`.
- [ ] stage1 unknowns to confirm there: exact `rkspi_loader.img` path; SPI write
      actually yields NVMe boot; `armbianEnv.txt` `rootdev` edit; boot-order after
      power-off (remove-card flow).
- [ ] stage2 unknowns: Docker version pin availability for arm64/trixie; `nmcli`
      device handling; `ethd install` behaviour headless; sshd unit name (`ssh` vs
      `sshd`).
- [ ] Once green on the spare: roll to the 20 sticks (gate each with `make verify-usb`).
