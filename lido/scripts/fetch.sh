#!/usr/bin/env bash
# Fetch the build inputs into $BUILD (gitignored): the Armbian Orange Pi 5 Plus image
# (checksum-verified, decompressed) and a fresh eth-docker checkout. Prints the path
# of the decompressed .img on the last stdout line so callers can chain into flash.
#
# Defaults pin the image that matches `c` (Armbian 26.5.1 / vendor 6.1.115); override
# via env (ARMBIAN_IMG / ARMBIAN_BASE / ETHD_REPO) without editing the script.
source "$(dirname "$0")/lib.sh"
need curl; need xz; need git; need sha256sum

BUILD=${BUILD:-build}
ARMBIAN_BASE=${ARMBIAN_BASE:-https://dl.armbian.com/orangepi5-plus/archive}
ARMBIAN_IMG=${ARMBIAN_IMG:-Armbian_26.5.1_Orangepi5-plus_trixie_vendor_6.1.115_minimal.img.xz}
ETHD_REPO=${ETHD_REPO:-https://github.com/eth-educators/eth-docker.git}

mkdir -p "$BUILD"
xz_path="$BUILD/$ARMBIAN_IMG"

if [ ! -f "$xz_path" ]; then
    log "downloading $ARMBIAN_IMG"
    curl -fL --retry 3 -o "$xz_path" "$ARMBIAN_BASE/$ARMBIAN_IMG"
else
    log "image already present: $xz_path"
fi

log "verifying checksum"
curl -fL --retry 3 -o "$xz_path.sha" "$ARMBIAN_BASE/$ARMBIAN_IMG.sha"
( cd "$BUILD" && sha256sum -c "$ARMBIAN_IMG.sha" ) || die "checksum verification FAILED"

img="${xz_path%.xz}"
if [ ! -f "$img" ]; then
    log "decompressing"
    xz -dk -T0 "$xz_path"
fi
[ -f "$img" ] || die "decompressed image missing: $img"

if [ ! -d "$BUILD/eth-docker/.git" ]; then
    log "cloning eth-docker ($ETHD_REPO)"
    git clone --depth 1 "$ETHD_REPO" "$BUILD/eth-docker"
else
    log "updating eth-docker"
    git -C "$BUILD/eth-docker" pull --ff-only || warn "eth-docker update skipped (offline?)"
fi

log "fetch complete"
echo "$img"
