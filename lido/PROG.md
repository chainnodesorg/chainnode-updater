# PROG — lido programming rules

- **Runs on `c`** (Linux). Shell is Bash with `set -euo pipefail`; source `lib.sh`
  for `log`/`warn`/`die`/`need`. Every script is executable and self-contained.
- **Fail loud.** Unexpected or unimplemented paths `die` (or `exit 1`) — never
  silently log-and-continue. `make image`/`payload` fail until validated on a spare.
- **USB safety is sacred.** Any destructive device op (`flash`, `verify-usb`) selects
  its target ONLY via `find-usb.sh`, which requires ALL of: `TRAN=usb`,
  `removable=1`, sysfs `/usb` path, udev `ID_BUS=usb`, not root, not `nvme*`/`mmcblk*`.
  Re-assert the key invariants immediately before writing. Never accept a device path
  argument that bypasses this gate.
- **No large artifacts in git.** Images / client checkouts are fetched by `make` into
  `build/` (gitignored). Pin versions to match `c` where it matters; allow env
  overrides instead of editing scripts.
- **`c` is production — never damage it.** Confine writes to `build/` and the selected
  USB device; never touch `c`'s NVMe, Docker, or services.
- Comments explain *why*; keep each script one clear purpose.
