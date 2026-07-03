# Post-mortem — the lost day: bricking OPi5+ boards chasing NVMe boot

Date: 2026-07-01. Written after ~1 workday, ~5 bricked boards, and still no NVMe boot.
This is the honest analysis of *why*, and the rules to never repeat it.

## What we were trying to do
Make an Orange Pi 5 Plus boot Armbian from its NVMe (no SD), by writing u-boot to
the 16 MB SPI NOR, then installing the OS to NVMe. Every attempt "bricked" the board
(no HDMI, no boot).

## What actually went wrong (root causes)

1. **We flashed SPI blind and destructively, over and over, with no recovery net and
   no visibility.** That is the core failure. Each brick cost hours because we couldn't
   see *why*, and we only figured out maskrom recovery late.

2. **We judged boot success/failure by HDMI — which was lying to us the whole time.**
   Three independent reasons HDMI showed nothing on a board that may have been fine:
   - the minimal/server image's console is on **serial**, not HDMI;
   - **Armbian's u-boot shows no boot logo** (the factory *OrangePi* u-boot does — that's
     the logo we saw on fresh boards);
   - the OPi5+ has **three HDMI ports and one is an INPUT** (bottom) — a monitor on the
     wrong port shows nothing regardless.
   We treated "dark HDMI" as "bricked." Most of the wasted day flows from this.

3. **We never got a UART serial console.** It is THE tool for RK3588 boot debugging and
   would have told us in 30 seconds where boot stopped. We guessed for hours instead.

4. **We used the WRONG reference for the bootloader.** `c` runs **Armbian** u-boot
   (`2017.09-armbian`, no HDMI logo); the fleet ships **OrangePi vendor** u-boot
   (`2017.09-orangepi`, shows logo + drives HDMI). We cloned c's SPI onto boards that
   needed the OrangePi image. We only discovered this at the very end by dumping a
   **working fleet board's** SPI (`factory_spi.img`) — which we should have done FIRST.

5. **We assumed "identical hardware" ⇒ "identical bootloader/software."** It doesn't:
   c was set up differently. The right reference is a fresh, working **fleet** unit.

6. **We changed several variables at once** (image source, write method dd-vs-flashcp,
   u-boot version) so we could never isolate the cause. Each "fix" was an unproven
   hypothesis presented with too much confidence, and each sent us down a wrong path
   (dd-vs-flashcp, wrong-storage, DDR-blob, coupling…), some of which were red herrings.

7. **Verification was unreliable.** The `stage1` read-back read `/dev/mtdblock0` (cached
   block layer), which can echo the page cache rather than the real NOR — so "verified
   OK" meant little. The trustworthy read is over maskrom (`rl`) or O_DIRECT.

8. **Physical gotchas ate huge time, discovered late by RTFM:** counterfeit USB flash
   (writes vanish); the OPi5+ has **two USB-C ports** (data port next to MASKROM button;
   power on the *other* DC-IN) so maskrom only enumerates when wired right, via a
   **USB-A** host path (C↔C often fails); charge-only cables.

## The technical truth we ended with (RK3588 / OPi5+)
- BootROM **cannot boot NVMe directly** → u-boot MUST live in SPI (or SD/eMMC). Boot order
  checks **SPINOR first, then eMMC, then SD**. Empty SPI ⇒ falls through to SD.
- Boot stages at fixed offsets: **idbloader/SPL @ sector 64 (0x8000)**, **u-boot proper
  @ 0x800000**. Mixed/stale stages across SPI+NVMe hang at the SPL→U-Boot handoff.
- **maskrom is an unbrickable recovery** over USB (`rkdeveloptool`): `db` loader → `ef`
  erase / `wl 0 <img>` write / `rl` read. Needs the two-USB-C-port + USB-A-host setup.
- The **board-matched u-boot** matters: use the fleet's **OrangePi vendor** image
  (`factory_spi.img`, captured from a working board), not c's Armbian one.
- Reading `/dev/mtdblock0` is **cached** — verify via maskrom `rl` read-back.

## Rules to avoid this next time (the protocol)
0. **READ THE PROPER DOCUMENTATION *BEFORE* ACTING — not after failing.** Every single
   fact that would have saved the day was documented and we found it *late*, by RTFM-ing
   only after bricking: the board has **two USB-C ports** (data vs DC-IN power), **three
   HDMI ports incl. an INPUT**, a defined **boot order** (SPINOR→eMMC→SD), and it ships the
   **OrangePi vendor** u-boot. Read the board's manual + the tool's man page + the recovery
   docs up front. If unsure, RTFM before you touch anything — especially before anything
   destructive.
1. **Recovery net FIRST.** Before ANY destructive/irreversible op (SPI write, flash),
   prove the recovery path works. For RK3588: confirm maskrom + `rkdeveloptool` + a
   known-good image on hand. Then a brick is a 1-minute fix, not a disaster.
2. **Visibility FIRST.** Get a **UART serial console** before debugging SBC boot. Never
   diagnose boot state from HDMI alone (server console=serial; u-boot logo varies; OPi5+
   has an HDMI-IN port). Confirm boot via serial *or* the network (DHCP lease + ssh).
3. **Golden reference FIRST.** Dump a **known-working unit's** SPI/config and use THAT as
   the image. Never assume another machine is a valid reference — verify it runs the same
   bootloader/version.
4. **One variable at a time, verify each**, with a trustworthy check (maskrom read-back,
   not cached mtdblock).
5. **RTFM the board's hardware quirks before touching it** (ports, buttons, boot order).
6. **Stop and reassess after the 2nd failure** instead of trying a 3rd/4th/5th unproven
   fix. Escalate to "get the right tool" (serial, reference dump) rather than more blind
   attempts. (We should have stopped after brick #2.)

## Where we are now / next steps to actually boot NVMe
- We have the **correct golden image**: `factory_spi.img` (OrangePi vendor u-boot, boots +
  HDMI), captured from a working board via maskrom.
- Recover bricked boards: maskrom → `ef` → `wl 0 factory_spi.img` → `rd` → should boot + HDMI.
- Then NVMe: with the correct SPI u-boot in place, install a matched OS to NVMe (or clone a
  working board's NVMe). Validate boot via **serial/network**, not HDMI.
- Get a UART adapter and a couple of sacrificial boards designated for testing before
  touching the other units.
