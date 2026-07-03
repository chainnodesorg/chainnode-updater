# Chainnode — operator guide (setup & login)

This is the short guide for setting up an **Orange Pi 5 Plus** board with the `lido`
installer card and logging into the finished node. No keyboard needed on the board —
you only insert/remove the card.

---

## 1. Provision a board (hands-off, ~10–15 min)

**You need:** the installer **microSD card**, the assembled OPi5+, an **Ethernet cable
with internet** into either RJ45 port, and power. A monitor on **HDMI** is optional but
handy (it shows progress and the board's IP).

1. **Insert the card into the board's microSD (TF) slot** — *not* a USB port. (SD boots
   ahead of the NVMe; a USB stick would not.)
2. **Power on.** *Phase 1* runs automatically: it installs the OS to the NVMe and writes
   the bootloader, then **powers the board off by itself** (a few minutes). If it seems to
   power-cycle instead of staying off, that's fine — just do the next step.
3. **Remove the card**, then **power on again.** *Phase 2* runs automatically: it installs
   Docker, checks out eth-docker, configures the system, then finishes. This needs the
   **internet on RJ45** and takes several minutes.
4. Done when the HDMI console shows the login banner with the board's **IP address** (or
   the message `### STAGE2 complete — node ready.`).

The board now boots entirely from its **NVMe**; the card is only for the one-time install
and can be reused on the next board.

---

## 2. Find the board's IP

- **On the HDMI monitor:** the IP is printed on screen above the `chainnode login:` prompt.
- **Without a monitor:** check your router/DHCP server's client list for hostname
  **`chainnode`**.

---

## 3. Log in

- **Over the network:**
  ```
  ssh user@<board-ip>
  ```
- **On the console (HDMI + keyboard):** log in at the `chainnode login:` prompt.

**Credentials:** user **`user`**, password **`password`**.

> **Change the password immediately** (`passwd`), and before adding any validator keys —
> the default is for first login only.

You can run `docker` without `sudo` (the user is in the `docker` group). `sudo` works too,
and `poweroff` / `reboot` / `ping` need no password.

---

## 4. Start the Ethereum node

The board ships as a **ready platform**: Docker is running and **eth-docker is installed
but not started**, so no node is running yet.

> **`docker ps` shows nothing — that is expected.** No containers exist until you start
> the node. (If `docker ps` *errored* instead of showing an empty list, Docker would be
> down — but it isn't.)

To choose your clients and start syncing:
```
cd ~/eth-docker
./ethd config     # pick execution + consensus clients, network, fee recipient, MEV;
                  # point the data directory at /mnt/blockchain
./ethd up         # start the stack
docker ps         # now you'll see the running containers
```
For a **Lido CSM** validator, select CSM in `ethd config`, then import your validator keys
per the eth-docker docs. Chain data lives on the big NVMe volume at **`/mnt/blockchain`**.

---

## What's on the box

- Hostname **`chainnode`**, boots from the 4 TB **NVMe**, time in **UTC** (NTP synced).
- **Docker** + **docker compose**, **eth-docker** checked out at `~/eth-docker`.
- Big chain-data volume at **`/mnt/blockchain`**.
- Both wired ports on DHCP; Wi‑Fi radio on but not connected; sshd on.
- Logs are size-capped (Docker + journald) so they can't fill the disk.
