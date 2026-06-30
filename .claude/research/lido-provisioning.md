# Research — Lido chainnode provisioning (verified ground truth)

Date gathered: 2026-06-30. Verify volatile items (client versions, MEV relay list,
Armbian release, eth-docker repo path) at build time.

## 1. Target hardware — Orange Pi 5 Plus (the fleet: 20× identical)

Surveyed on the reference box `c` (192.168.14.242, reachable only over Tailscale +
the home LAN). `c` is a **production box that must not be damaged** — used only as a
reference and as the build host.

- SoC: Rockchip **RK3588**, arm64. 8 cores: 4× Cortex-A76 @2.35 GHz + 4× A55 @1.8 GHz.
- RAM: **31 GiB**. zram swap 15.5 GiB.
- Storage: **4 TB NVMe** (Kingston SNV2S4000G) — single `ext4` root partition
  (`/dev/nvme0n1p1`), 219 GB used / 3.2 TB free at survey time.
- SPI flash: **`/dev/mtdblock0`, 16 MiB, MTD name "loader"** (`/proc/mtd` → `mtd0
  "loader"`). This is where the NVMe-boot u-boot must be written.
- Network IFs: `wlP2p33s0` (WiFi, up, the only active link on `c`); wired
  `enP4p65s0`, `enP3p49s0` (down on `c`). Predictable `enP*`/`wlP*` names.

## 2. OS / runtime on `c`

- Armbian **26.5.1 trixie** (Debian 13), `armbian-release`: BOARD=orangepi5-plus,
  BOARDFAMILY=rockchip-rk3588, LINUXFAMILY=rk35xx.
- Kernel **6.1.115-vendor-rk35xx** (vendor kernel).
- Boot: `/boot/armbianEnv.txt` + `boot.scr` + extlinux-style; `rootdev=UUID=…`,
  `fdtfile=rockchip/rk3588-orangepi-5-plus.dtb`, `usbstoragequirks=…`.
- Provisioning tools present: **`armbian-install`, `nand-sata-install`,
  `armbian-config`** (all in `/usr/bin`).
- Time sync: **`systemd-timesyncd` active** (chrony/ntpd inactive). "Armbian NTP
  infrastructure" == systemd-timesyncd.
- Tools present: `jq`, `mc`, `make`, `gmake`, `gcc`.
- Internet egress works (github 200, eth-docker site 200).

### Exact Docker packages on `c` (must match on the fleet)
```
containerd.io          2.2.4-1~debian.13~trixie
docker-buildx-plugin   0.34.1-1~debian.13~trixie
docker-ce              5:29.5.3-1~debian.13~trixie
docker-ce-cli          5:29.5.3-1~debian.13~trixie
docker-compose-plugin  5.1.4-1~debian.13~trixie
```
Installed from Docker's official apt repo. `docker compose` (v2 plugin) → reports
`Docker Compose version v5.1.4`. Docker root `/var/lib/docker` (on the NVMe root).

### Groups for `vany` on `c` (replicate for the `user` account)
```
tty disk dialout sudo audio operator video plugdev games users
systemd-journal input render netdev docker
```

## 3. eth-docker

Sources: <https://ethdocker.com/> (canonical; `eth-docker.net` 301→`ethdocker.com`),
Lido CSM guide <https://docs.lido.fi/run-on-lido/csm/node-setup/advanced/eth-docker/>.

- Repo: `github.com/eth-educators/eth-docker` (Lido docs reference
  `github.com/ethstaker/eth-docker` — an alias; **verify exact path at build time**).
- Stated requirements: **32–64 GiB RAM, 4–8 cores, 4 TB SSD** — our box fits exactly.
- Runs on Linux/macOS, x64 / **ARM** / RISC-V. arm64 supported.
- Install: `git clone … && cd eth-docker && ./ethd install` (installs docker + deps),
  then `ethd config` (a **TUI that only writes `.env`**), then `ethd up`.
- Other `ethd` commands: `up`, `down`, `restart`, `logs`, `update`, `keys import`.
- Start-on-boot / clean-stop: handled by docker compose `restart: unless-stopped`
  + the `docker.service` lifecycle. **No custom systemd unit needed.**
- `.env` drives everything; `COMPOSE_FILE` is a `:`-separated list of client compose
  files, e.g. `geth.yml:lighthouse.yml:mev-boost.yml`. Config can be **pre-baked**
  by writing `.env` directly — the TUI is just a generator.
- Supported clients (any EL × any CL):
  - EL: Geth, Nethermind, Besu, Reth, Erigon, Ethrex, Nimbus-EL.
  - CL: Lighthouse, Prysm, Teku, Nimbus, Lodestar, Grandine.
- Images pulled from client teams' official docker hub / ghcr images (some build
  from source). Pre-`docker save` + `docker load` is viable to avoid 20× pulls.

## 4. Lido CSM (Community Staking Module)

Sources: Lido docs (above), operatorportal.lido.fi, dvt-homestaker.stakesaurus.com.

- CSM = permissionless Lido staking module; community operators run validators with
  a reduced ETH bond. eth-docker `ethd config` has a node-type "**CSM node**".
- **Fee recipient is a FIXED constant for all mainnet CSM operators** = Lido
  Execution Layer Rewards Vault **`0x388C818CA8B9251b393131C08a736A67ccB19297`**.
  Sending EL rewards elsewhere is treated as theft and penalized.
- **MEV-Boost is mandatory.** Only relays from the **Lido CSM vetted list** may be
  used (must include ≥1 "must use some"). `builder-boost-factor=100`. Optional
  min-bid (community max ~0.07). **The vetted relay list is volatile — fetch the
  current set at build time from the CSM Operator Portal.**
- Validator keys: mainnet keys are generated **offline** and imported per box later
  (`ethd keys import`). The image therefore ships **keyless** — a syncing,
  CSM-ready node awaiting key import.

## 5. Orange Pi 5 Plus — boot from NVMe (no SD card)

Sources: Armbian forum threads, jamesachambers.com SSD-boot guide.

- RK3588 maskrom can't boot NVMe directly; the 16 MiB SPI flash holds a u-boot that
  enables NVMe (and USB3) boot.
- Standard path: boot Armbian from removable media → `armbian-install` →
  "**Boot from SPI**" writes updated u-boot to SPI flash → then NVMe boots with no
  SD/USB present.
- ⚠️ Community reports the `armbian-install` SPI path is **occasionally flaky** on
  specific kernel/Armbian versions. Plan a manual fallback (write the board's
  `rkspi_loader.img` directly to `/dev/mtdblock0`). **Must be validated on a spare
  device — cannot be tested on `c`.**
- Pitfall: UUID conflicts when two Armbian installs (USB + NVMe) are present —
  clear/relabel as needed.

## 6. Open verification items (do on the spare test box, later)
- u-boot→SPI write actually yields NVMe boot on this exact Armbian/kernel.
- Boot-order behavior with USB still inserted (drives the power-off-then-remove
  decision in the lifecycle).
- Exact `.env` produced by `ethd config` for {mainnet, CSM node, Geth, Lighthouse,
  MEV-boost, all vetted relays} — capture once, then template it.
- Current Lido CSM mainnet vetted MEV relay URLs.
