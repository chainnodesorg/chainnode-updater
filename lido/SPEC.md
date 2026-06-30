# SPEC — `lido`: USB provisioning flasher for the chainnode fleet

Status: **design, awaiting approval**. Date: 2026-06-30.
Research ground truth: [`.claude/research/lido-provisioning.md`](../.claude/research/lido-provisioning.md).

## 1. Goal

Produce a **single bootable USB-flash image** (`.img`) that, written to a USB stick
and booted on a *fresh, assembled* Orange Pi 5 Plus, turns the box into a clean
Armbian node with **eth-docker installed (but unconfigured)**, Docker ready, and a
**large blockchain data volume on NVMe** — booting from its own 4 TB NVMe with no SD
card. The same image provisions all **20 identical** boxes.

**Scope:** we provision the *platform* only. We do **not** bake any client choice or
node config — no `.env`, no client images, no CSM/MEV/fee-recipient/keys. The
**operator chooses the software himself** afterward (`ethd config` → `ethd up`),
pointing data at the prepared blockchain volume.

End state of a provisioned box: boots from NVMe over wired DHCP, hostname
`chainnode`; Docker running; eth-docker checked out and `./ethd install` completed;
a big NVMe volume reserved for chain data; ready for the operator to configure.

## 2. Fixed decisions

| Topic | Decision |
|---|---|
| Fleet | 20× Orange Pi 5 Plus (RK3588, 32 GiB, 4 TB NVMe), already assembled |
| Deliverable | One flashable `.img`; operator writes it to USB sticks |
| Build host | `c`, in **`~/lidoflash`** (`/home/vany/lidoflash`). **Never damage `c`.** |
| Base OS | Latest stable **Armbian Orange Pi 5 Plus** (trixie, vendor kernel), via `make` |
| Boot target | NVMe; u-boot written to **SPI flash** (`/dev/mtdblock0`). No SD cards. |
| NVMe layout | Single span **ext4** root over the full 4 TB |
| Docker | Exact versions from `c` (docker-ce 5:29.5.3, containerd.io 2.2.4, buildx 0.34.1, compose-plugin 5.1.4, trixie) from Docker's apt repo |
| Extra pkgs | net-tools (+ net utils), make/gmake, jq, mc |
| Node stack | eth-docker (**latest**, unpinned) **installed only** — `./ethd install` done; **no** client choice, `.env`, or `ethd up`. Operator configures later. |
| Node config | **None baked.** Box is CSM-capable; operator runs `ethd config` to pick clients/CSM/MEV/keys. (Reference values in research doc.) |
| Blockchain volume | **One big dedicated volume on NVMe** for chain data; eth-docker data dir points here |
| User | `user` / `password`; groups = same as `vany` on `c` (sudo, docker, operator, …) |
| SSH | sshd enabled, password auth on; verify `ssh localhost` works. No seeded keys. |
| WiFi | radio initialized, **no** saved connection |
| Wired | both NICs → DHCP (NetworkManager, Armbian default) |
| Time | `systemd-timesyncd`, **UTC** |
| Logs | rotation on 3 layers (journald cap, docker json-file max-size/file, logrotate) |
| Artifacts | big files (Armbian image, eth-docker checkout) fetched by `make`, **never committed** |

## 3. Architecture

### 3.1 The USB image
A bootable Armbian Orange Pi 5 Plus system (the "installer / live env") plus a
**payload** carried on the stick:
- the latest Armbian rootfs image to write to NVMe,
- the eth-docker checkout (unconfigured — no `.env`, no client images),
- our config (network, sshd, timesyncd, logrotate) and the provisioning scripts.

### 3.2 Three-boot lifecycle
- **Boot 1 — from USB (stage 1, destructive):** auto-run by a first-boot systemd
  oneshot. Writes u-boot to SPI flash; wipes + GPT + single ext4 over the NVMe;
  installs the latest Armbian to NVMe; copies the payload onto NVMe; installs the
  stage-2 oneshot into the NVMe rootfs; sets hostname/user via chroot. Then
  **powers off and prints "remove USB, power on"** (recommended over a straight
  reboot — with the USB still inserted the board may re-boot the USB; power-off
  removes that ambiguity on an assembly line). *Open: confirm boot order on the
  spare box; if NVMe is reliably preferred we can switch to auto-reboot.*
- **Boot 2 — from NVMe (stage 2, configuration):** auto-run oneshot. `apt update`;
  install Docker (pinned to `c`'s versions) + extra packages (net-tools, make/gmake,
  jq, mc); create the big blockchain volume on NVMe; check out eth-docker + run
  `./ethd install`; configure network (2× wired DHCP, WiFi radio up no-connect),
  sshd, timesyncd/UTC, log rotation. **No `ethd up`** — left unconfigured for the
  operator. Then **disables itself** so it never runs again.
- **Boot 3+ — from NVMe (normal):** clean working system; Docker running; eth-docker
  installed but idle until the operator runs `ethd config` && `ethd up`. Once
  configured, it auto-starts on boot via `restart: unless-stopped`.

### 3.3 Build flow (on `c`, in `~/lidoflash`)
`make` rsyncs `lido/` → `c:~/lidoflash`, then runs targets there (loopback mounts +
chroot need root; confined to `~/lidoflash` and loop devices — **no writes to `c`'s
system disk or services**). Indicative targets:
- `make fetch` — download + verify the Armbian image; clone the eth-docker repo.
- `make payload` — assemble the payload tree.
- `make image` — build the bootable USB `.img` (base Armbian + first-boot stage-1 +
  payload).
- `make flash` — **auto-select the first inserted USB drive** and write the `.img`
  to it, then read-back verify. **USB-safety is paranoid and mandatory** — refuses to
  write unless the chosen device passes *every* check (ALL must hold), else aborts:
  - `lsblk -dno TRAN` == `usb`, **and**
  - `/sys/block/<dev>/removable` == `1`, **and**
  - `readlink -f /sys/block/<dev>` path contains `/usb`, **and**
  - `udevadm info` reports `ID_BUS=usb`, **and**
  - name does **not** match `nvme*`/`mmcblk*`, **and**
  - device is **not** the mounted root/holder of `/` (cross-check vs `findmnt /`).

  If zero USB devices match → abort with a clear message. If more than one matches →
  pick the first by stable order and **print which device** before writing. Never
  falls back to a non-USB disk. (`c`'s NVMe can therefore never be a target.)
- `make verify-usb` — O_DIRECT offset-encoded capacity/writability test (catches the
  counterfeit flash seen in this batch); run before trusting any stick. See MEMO.
- `make clean` — remove build artifacts in `~/lidoflash`.
- (`fetch`/`payload`/`image` artifacts are git-ignored.)

## 4. Repo layout (`lido/`)
```
lido/
  SPEC.md   PROG.md   MEMO.md   TODO.md
  Makefile
  scripts/   stage1.sh  stage2.sh  verify-usb  (helpers)
  config/    network, logrotate, sshd, timesyncd (no eth-docker .env — unconfigured)
  .gitignore (ignore fetched artifacts; build happens in c:~/lidoflash)
```

## 5. Risks / open items
- **Untestable-on-`c`:** SPI-flash write, NVMe wipe, and boot-order behavior must be
  validated on a spare box (later). Until then stage-1 is "flash once and pray."
- **`armbian-install` SPI flakiness** on some kernels → keep a manual
  `rkspi_loader.img → /dev/mtdblock0` fallback.
- **Security:** `user`/`password` + password SSH is dangerous if the box ever faces
  the internet — especially once the operator adds validator keys. Accepted for now;
  recommend hardening before keys land.
- **Volatile inputs:** Armbian release, Docker versions, and the eth-docker repo path
  — re-verify at build time.
- **Operator hand-off:** node config (clients/CSM/MEV/fee-recipient/keys) is out of
  scope here and is the operator's responsibility via `ethd config`. Research doc
  retains the CSM reference values if needed.
- **Not damaging `c`:** the build uses loop devices + chroot under `~/lidoflash`
  only; must avoid touching `c`'s root, docker, or services.
