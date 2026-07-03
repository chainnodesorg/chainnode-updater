# MEMO — lido (dev memory)

## STATUS 2026-07-02 — RELEASE CANDIDATE
Golden flow **validated on a fresh OPi5+**: card in microSD slot → stage1 (GPT NVMe install
+ **vendor** `factory_spi.img` flashcp to /dev/mtd0, always-write) → power off → remove card
→ stage2 → boots from NVMe as `chainnode` with Docker (usable w/o sudo), eth-docker checked
out, `/mnt/blockchain`, UTC+NTP, sshd. Board is a ready **platform** — operator runs
`ethd config && ethd up` (empty `docker ps` until then is expected).

**SPI u-boot — the load-bearing decision:** write ONLY the OrangePi **vendor** `factory_spi.img`
(the fleet's own u-boot; boots + HDMI, no brick). NEVER the **Armbian** u-boot (`rkspi_loader.img`
/ c's SPI) — it flashcp-verifies fine and **BRICKS** these boards (proven twice; bricked board
#6 chasing a "matched-pair like c" theory). c is NOT the bootloader reference. Also dropped a
skip-if-match optimization (made a fresh board skip the write and not boot) — always write.

**Single-use card bug (2026-07-03) — the REAL cause of "inconsistent NVMe boot":** stage1
wrote its done-marker to the CARD (STATE_DIR=/opt/lido is on the card), so after one board the
card skipped the install on every next board ("not touched nvme, powered off"). The 2nd board
never got installed — that is why it "didn't boot NVMe." I misread it as a u-boot problem and
bricked a board chasing it. FIX: done-flag now lives on each board's NVMe
(`$MP/opt/lido/stage1.done`); firstboot mounts the NVMe read-only to check it. One card → all 20.

**Never put a visibility hack in the install's stdout path (2026-07-03):** an `exec > >(tee -a
LOG > /dev/tty1)` for HDMI output raised "tee: io error", broke the pipe, SIGPIPE-killed stage1
right after partitioning → bricked boards #2/#3. Reverted to `exec >>LOG`. Any HDMI mirror must
be an ISOLATED background reader.

Other root causes fixed: improper SPI write (dd→cached mtdblock ⇒ flashcp on /dev/mtd0),
clock/apt race (NTP-wait), ethd-install-as-root (dropped, redundant), nmcli→networkd,
docker-group ordering, `.eth` mis-symlink (dropped), c's 22 s watchdog vs buffered USB flush
(O_DIRECT). PENDING: reflash the tee-removed multi-use card + prove a 2nd board installs
(blocked on c connectivity). Bricked boards #2/#3/#6 to recover via maskrom → factory_spi.img.

## 2026-06-30 — media / hardware triage

- **Reach `c`:** `c` is a plain **LAN host at `192.168.14.242`**. **Tailscale must be
  DOWN** (`tailscale down`) — bringing it up routes the default through the corporate
  exit node and breaks the direct LAN route. `c`'s `~/.ssh/config` HostName is
  commented out, so connect with `ssh -o HostName=192.168.14.242 c`.
  `vany` is in `disk` group → can read/write `/dev/sd*` raw **without sudo**
  (sudo needs a password, which I don't have). `blkid`/`file` are NOT installed
  on `c` — identify devices by raw reads (`dd`+`hexdump`) instead.
- **USB SD reader `14cd:1212`** (serial `121220160204`) on `c` works. The serial is
  the *reader's* — constant across card swaps; different reported sizes = different
  cards. The same reader/hub did **not** enumerate on the MacBook (USB tree empty).
- **Counterfeit/dead flash confirmed in this batch.** Reliable test = **O_DIRECT**
  (bypasses page cache) + offset-encoded markers across the full claimed range, then
  read back. Cached reads lie (page cache echoes the write); only O_DIRECT proves the
  media. One 30 GB card ACKs writes + `fsync` OK but **persists nothing** (even
  overwriting known non-zero data leaves it byte-identical) → effectively read-only,
  ~0 usable capacity.
- **Good media on hand:** one **genuine 59.5 GiB SD card**, full capacity + writable
  (501/501 markers verified, no aliasing). Currently `/dev/sda` via the reader on `c`;
  its prior `opi_boot`/`opi_root` image was wiped during testing (authorized).

**Decision pending:** add a **`make verify-usb`** gate (this O_DIRECT method) before
flashing any of the 20 fleet sticks — given the counterfeits seen. See [[SPEC]] §5.

## 2026-07-01 — TWO bricks, REAL root cause = WRONG FIRMWARE (not the write method)
- **Misdiagnosis to discard:** I first blamed `dd → /dev/mtdblock0` and "fixed" it with
  `flashcp`. Web research (Armbian forum, unixorn, pihobby) shows **`dd … of=/dev/mtdblock0
  conv=notrunc` IS the official method** — the write method was never the problem. Both
  boards bricked the same way regardless.
- **Real cause:** stage1 flashed the distro **package** `rkspi_loader.img` (md5
  `85b3e241…`), grabbed by a wildcard glob, which is a **different u-boot build** from
  c's actual working SPI (`eac74512…`, differ from byte 529). A mismatched/wrong-build
  SPI loader → exactly the "red LED, no display, no-boot" symptom (documented). Not zeroing
  first contributed. NOT an RK3588-vs-RK3588S issue — boards are full RK3588 OPi5+, same as
  c (see memory [[lido-boards-identical-to-c]]).
- **Fix (in stage1 now):** refuse SPI write unless `BOARD=orangepi5-plus`/`BOOT_SOC=rk3588`;
  flash ONLY the **proven image cloned from c's SPI** (`make capture-spi` → bundled at
  `/opt/lido/firmware/spi.img`, checksum-verified); zero SPI first; `dd` to `/dev/mtdblock0`;
  read-back `cmp`; abort-without-poweroff (zeroed SPI falls back to SD boot) on any doubt.
- **Recovery options:** (1) **clean microSD boot usually still works** even with bad SPI —
  try first ("nobody managed a brick that couldn't boot from SD"); if it boots, zero SPI
  (`dd if=/dev/zero of=/dev/mtdblock0 count=4096 bs=512`) or run from SD. (2) Else
  **maskrom**: `rkdeveloptool` (trixie pkg) + `rk3588_spl_loader_v1.22.114.bin` (radxa/rkbin),
  staged in `c:~/lidoflash/recover/` → `ld` → `db <loader>` → `ef` (erase) → `rd`.
  **Maskrom gotchas:** needs a real **data** USB cable (charge-only = red LED, no `2207:350b`)
  and host on a **USB-A** port (Type-C↔Type-C role-negotiates and fails).
- See [[RUNBOOK]] for tomorrow's gated, supervised flow.

## Build host
- Build workspace = `c:~/lidoflash` (`/home/vany/lidoflash`). Never damage `c`:
  use loop devices + chroot confined to that dir; never touch `c`'s NVMe/services.
