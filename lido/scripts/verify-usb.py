#!/usr/bin/env python3
"""DESTRUCTIVE counterfeit-flash test.

Write offset-encoded markers across the full claimed capacity using O_DIRECT, then
read them back and verify. WHY O_DIRECT: a normal cached read echoes our own
just-written buffer from the page cache and so HIDES fake/dead flash; only direct I/O
proves the medium actually retained the bytes. Each marker encodes its own LBA, so a
counterfeit reveals itself as either lost markers (read back as something without our
magic) or aliased markers (decode to a different offset) above its real capacity.

Usage: verify-usb.py /dev/sdX     (exit 0 = genuine, 1 = fake/faulty/guard-fail)
"""
import os
import sys
import mmap
import struct

BS = 4096
MAGIC = b"FAKECHK\x00"            # 8 bytes, followed by an 8-byte little-endian offset


def die(msg):
    sys.exit("verify-usb: FATAL: " + msg)


def main():
    if len(sys.argv) != 2:
        die("usage: verify-usb.py /dev/sdX")
    dev = sys.argv[1]
    name = os.path.basename(dev)

    # Paranoid guards — mirror find-usb.sh so this can never chew a system disk.
    if name.startswith(("nvme", "mmcblk", "md", "dm-", "loop", "ram")):
        die("refusing non-USB-style device " + dev)
    try:
        if open("/sys/block/%s/removable" % name).read().strip() != "1":
            die(dev + " is not removable")
    except OSError:
        die("cannot read removable flag for " + dev)

    fd = os.open(dev, os.O_RDWR | os.O_DIRECT)
    size = os.lseek(fd, 0, os.SEEK_END)
    if not (1 * 1024**3 < size < 256 * 1024**3):
        die("unexpected size %d" % size)
    print("verify-usb: %s size=%d (%.2f GiB) O_DIRECT" % (dev, size, size / 1024**3))

    def buf(data=None):
        m = mmap.mmap(-1, BS)        # anonymous mmap is page-aligned -> O_DIRECT-safe
        if data is not None:
            m[:] = data
        return m

    def marker(off):
        rec = MAGIC + struct.pack("<Q", off)
        return rec * (BS // len(rec))

    def decode(m):
        b = bytes(m[:16])
        return struct.unpack("<Q", b[8:16])[0] if b[:8] == MAGIC else None

    maxblk = size // BS - 1
    N = 500
    offs = sorted({(i * maxblk // N) * BS for i in range(N + 1)} | {0, maxblk * BS})

    wbufs = {o: buf(marker(o)) for o in offs}
    for o in offs:
        os.pwritev(fd, [wbufs[o]], o)
    os.fsync(fd)
    os.close(fd)
    print("verify-usb: wrote %d markers, fsync OK" % len(offs))

    fd = os.open(dev, os.O_RDONLY | os.O_DIRECT)
    rb = buf()
    good, lost, alias = [], [], []
    for o in offs:
        os.preadv(fd, [rb], o)
        d = decode(rb)
        if d == o:
            good.append(o)
        elif d is None:
            lost.append(o)
        else:
            alias.append((o, d))
    os.close(fd)

    last_good = max(good) if good else -1
    print("verify-usb: good %d/%d  lost %d  aliased %d"
          % (len(good), len(offs), len(lost), len(alias)))
    print("verify-usb: highest verified %.3f GiB" % (last_good / 1024**3))

    if good and len(good) == len(offs):
        print("verify-usb: VERDICT GENUINE ~%.1f GiB" % (size / 1024**3))
        return 0
    if lost:
        print("verify-usb: first lost at %.3f GiB" % (min(lost) / 1024**3))
    for o, d in alias[:6]:
        print("verify-usb: alias %.3f -> %.3f GiB" % (o / 1024**3, d / 1024**3))
    print("verify-usb: VERDICT FAKE/FAULTY — real usable ~%.2f GiB of %.1f GiB claimed"
          % ((last_good + BS) / 1024**3, size / 1024**3))
    return 1


if __name__ == "__main__":
    sys.exit(main())
