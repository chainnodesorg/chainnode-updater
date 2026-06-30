# MEMO — lido (dev memory)

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

## Build host
- Build workspace = `c:~/lidoflash` (`/home/vany/lidoflash`). Never damage `c`:
  use loop devices + chroot confined to that dir; never touch `c`'s NVMe/services.
