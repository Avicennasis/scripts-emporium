#!/usr/bin/env python3
"""
Read-only triage of a raw block device or disk image.

Answers the question you have when a second-hand drive lands on the bench:
is this thing already sanitised, is it full-disk encrypted, or is it still
carrying somebody's data?

Byte-frequency entropy is the discriminator:
  ~8.00 bits/byte uniform  -> random overwrite OR encrypted (indistinguishable
                              by entropy alone; look for FDE headers instead)
  <7.5 with structure      -> real data (compressed media still runs high, but
                              filesystem metadata leaves readable strings)

It hexdumps sector 0, tests the 0x55AA MBR signature, scans the head of the
device for BitLocker / LUKS / PGP-WDE / SafeBoot / NTFS / GPT magic, samples
entropy at evenly spaced points, and hunts for readable filesystem strings
across many more.

Nothing is ever written. The device is opened O_RDONLY and only pread() is
used. Reading a raw block device normally needs root.

Two refusals are enforced before the device is opened at all:
  * /dev/sda (and its partitions) -- almost always the system disk
  * any device with a mounted partition, including through LVM/dm/md

Usage:
    entropy_id.py /dev/sdX [options]
    entropy_id.py disk-image.img [options]

Exit status: 0 report produced, 2 refused or unusable target.
"""
from __future__ import annotations

import argparse
import math
import os
import re
import stat
import sys
from collections import Counter
from typing import NoReturn

BLOCK = 1024 * 1024
MBR_SIGNATURE = b"\x55\xaa"
MBR_SIGNATURE_OFFSET = 510
SECTOR = 512

# Kernel names of whole disks this tool will never read, however it is spelled
# on the command line. Mirrors the guard in Simmons-Systems-Rescue
# bin/build-*-usb.sh.
REFUSED_DISKS = {"sda"}

FDE_SIGS = {
    b"-FVE-FS-": "BitLocker",
    b"LUKS\xba\xbe": "LUKS",
    b"\xeb\x58\x90-FVE": "BitLocker (boot)",
    b"PGPGUARD": "PGP WDE",
    b"SafeBoot": "McAfee SafeBoot / Endpoint Encryption",
    b"CHKDSK": "NTFS artifact",
    b"NTFS    ": "NTFS boot sector",
    b"EFI PART": "GPT header",
}

STRING_PATTERN = re.compile(rb"[\x20-\x7e]{16,}")
INTERESTING_PATTERN = re.compile(
    rb"(?i)(\.doc|\.xls|\.pdf|\.jpg|\.exe|\.dll|Users|Windows|Documents|"
    rb"Program Files|@|http|Corp|Inc\.|home/|/etc/|\.txt|\.zip)")


# --------------------------------------------------------------------------
# Safety guards -- all of this runs before the device is opened
# --------------------------------------------------------------------------

def _sysfs_name(path: str) -> str | None:
    """Kernel block-device name for path, or None if it is not a block dev."""
    st = os.stat(path)
    if not stat.S_ISBLK(st.st_mode):
        return None
    dev = f"{os.major(st.st_rdev)}:{os.minor(st.st_rdev)}"
    link = f"/sys/dev/block/{dev}"
    if not os.path.exists(link):
        return None
    return os.path.basename(os.path.realpath(link))


def _whole_disk(name: str) -> str:
    """Kernel name of the whole disk behind a possibly-partition name."""
    if os.path.exists(f"/sys/class/block/{name}/partition"):
        return os.path.basename(
            os.path.dirname(os.path.realpath(f"/sys/class/block/{name}")))
    return name


def _device_tree(name: str) -> dict[str, str]:
    """Map 'major:minor' -> kernel name for a device, its partitions, and
    everything stacked on top of them (dm / LVM / md), recursively."""
    found: dict[str, str] = {}
    queue = [name]
    while queue:
        current = queue.pop()
        base = f"/sys/class/block/{current}"
        if not os.path.isdir(base):
            continue
        try:
            with open(f"{base}/dev", encoding="ascii") as fh:
                devno = fh.read().strip()
        except OSError:
            continue
        if devno in found:
            continue
        found[devno] = current
        for entry in sorted(os.listdir(base)):
            # Partitions are the only child dirs that carry their own 'dev'.
            if os.path.isfile(f"{base}/{entry}/dev"):
                queue.append(entry)
        holders = f"{base}/holders"
        if os.path.isdir(holders):
            queue.extend(os.listdir(holders))
    return found


def _mounts_for(devnos: dict[str, str]) -> list[tuple[str, str]]:
    """[(kernel name, mount point)] for anything in devnos that is mounted."""
    hits = []
    with open("/proc/self/mountinfo", encoding="utf-8") as fh:
        for line in fh:
            fields = line.split()
            if len(fields) > 4 and fields[2] in devnos:
                hits.append((devnos[fields[2]], fields[4]))
    return hits


def refuse(message: str) -> NoReturn:
    """Print a refusal and exit 2. Never returns."""
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(2)


def check_target(path: str) -> None:
    """Refuse the system disk and anything with a mounted partition."""
    if not os.path.exists(path):
        refuse(f"{path} does not exist")

    name = _sysfs_name(path)
    if name is None:
        if stat.S_ISREG(os.stat(path).st_mode):
            return  # plain disk image: no partitions of ours to be mounted
        refuse(f"{path} is neither a block device nor a regular file")

    disk = _whole_disk(name)
    if disk in REFUSED_DISKS:
        where = "" if name == disk else f" (part of /dev/{disk})"
        refuse(f"refusing to read {path}{where} -- almost always your "
               f"system disk")

    mounted = _mounts_for(_device_tree(disk))
    if mounted:
        detail = ", ".join(f"/dev/{n} on {mp}" for n, mp in sorted(mounted))
        refuse(f"refusing to read {path}: /dev/{disk} is in use -- {detail}")


# --------------------------------------------------------------------------
# Analysis
# --------------------------------------------------------------------------

def pread_full(fd: int, size: int, offset: int) -> bytes:
    buf = b""
    while len(buf) < size:
        chunk = os.pread(fd, size - len(buf), offset + len(buf))
        if not chunk:
            break
        buf += chunk
    return buf


def entropy(buf: bytes) -> float:
    if not buf:
        return 0.0
    counts = Counter(buf)
    n = len(buf)
    return -sum((c / n) * math.log2(c / n) for c in counts.values())


def report_first_sector(fd: int, rows: int) -> None:
    print("=" * 60)
    print("FIRST SECTOR (would hold MBR / FDE header)")
    print("=" * 60)
    head = pread_full(fd, SECTOR, 0)
    for row in range(0, min(rows * 16, len(head)), 16):
        chunk = head[row:row + 16]
        hexs = " ".join(f"{b:02x}" for b in chunk)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        print(f"  {row:04x}  {hexs:<47}  |{asc}|")
    mbr_sig = head[MBR_SIGNATURE_OFFSET:MBR_SIGNATURE_OFFSET + 2]
    present = "PRESENT" if mbr_sig == MBR_SIGNATURE else "absent"
    print(f"\n  MBR boot signature (0x55AA at {MBR_SIGNATURE_OFFSET}): "
          f"{mbr_sig.hex()} -> {present}")
    print(f"  first-sector entropy: {entropy(head):.3f} bits/byte")


def report_signatures(fd: int, window_mib: int) -> None:
    print("\n" + "=" * 60)
    print(f"KNOWN SIGNATURE SCAN (first {window_mib} MiB)")
    print("=" * 60)
    probe = pread_full(fd, window_mib * 1024 * 1024, 0)
    found = []
    for sig, name in FDE_SIGS.items():
        idx = probe.find(sig)
        if idx != -1:
            found.append(f"  FOUND {name!r} at offset {idx:,}")
    print("\n".join(found) if found
          else "  no known FDE/filesystem signature found")


def report_entropy(fd: int, nblocks: int, samples: int) -> None:
    print("\n" + "=" * 60)
    print(f"ENTROPY ACROSS DISK ({samples} evenly spaced "
          f"{BLOCK // (1024 * 1024)}MiB samples)")
    print("=" * 60)
    ents = []
    for i in range(samples):
        blk = int(nblocks * (i + 0.5) / samples)
        buf = pread_full(fd, BLOCK, blk * BLOCK)
        if len(buf) != BLOCK:
            continue
        e = entropy(buf)
        ents.append(e)
        pct = 100.0 * blk / nblocks
        print(f"  {pct:5.1f}% (blk {blk:>7,}) entropy {e:.4f} bits/byte")
    if ents:
        print(f"\n  mean {sum(ents) / len(ents):.4f}, "
              f"min {min(ents):.4f}, max {max(ents):.4f}")


def report_strings(fd: int, nblocks: int, blocks: int, max_hits: int) -> None:
    print("\n" + "=" * 60)
    print(f"READABLE-STRING SEARCH ({blocks} spread samples, "
          f"filesystem-ish words)")
    print("=" * 60)
    hits = 0
    for i in range(blocks):
        blk = int(nblocks * (i + 0.5) / blocks)
        buf = pread_full(fd, BLOCK, blk * BLOCK)
        if len(buf) != BLOCK:
            continue
        for m in STRING_PATTERN.findall(buf):
            if INTERESTING_PATTERN.search(m):
                s = m.decode("ascii", "ignore").strip()
                print(f"  [{100.0 * blk / nblocks:5.1f}%] {s[:100]}")
                hits += 1
                if hits >= max_hits:
                    break
        if hits >= max_hits:
            break
    if hits >= max_hits:
        print(f"  ... stopped at {max_hits} hits (--max-strings)")
    if not hits:
        print("  NONE -- no filenames, paths, or document extensions anywhere.")
        print("  Real filesystem data essentially always leaks such strings.")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read-only triage of a raw block device or disk image: "
                    "already wiped, encrypted, or still holding data?",
        epilog="Never writes. Refuses /dev/sda and any device with a mounted "
               "partition.")
    parser.add_argument("device",
                        help="block device (/dev/sdX) or disk image file")
    parser.add_argument("--signature-window", type=int, default=32,
                        metavar="MIB",
                        help="size in MiB of the head region scanned for "
                             "FDE/filesystem magic (default: 32)")
    parser.add_argument("--samples", type=int, default=10, metavar="N",
                        help="number of evenly spaced entropy samples "
                             "(default: 10)")
    parser.add_argument("--string-blocks", type=int, default=40, metavar="N",
                        help="number of spread blocks searched for readable "
                             "strings (default: 40)")
    parser.add_argument("--max-strings", type=int, default=25, metavar="N",
                        help="stop after this many readable-string hits "
                             "(default: 25)")
    parser.add_argument("--hexdump-rows", type=int, default=8, metavar="N",
                        help=f"16-byte rows of sector 0 to hexdump, max "
                             f"{SECTOR // 16} (default: 8)")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    for name, value in (("--signature-window", args.signature_window),
                        ("--samples", args.samples),
                        ("--string-blocks", args.string_blocks),
                        ("--max-strings", args.max_strings),
                        ("--hexdump-rows", args.hexdump_rows)):
        if value < 1:
            refuse(f"{name} must be >= 1")
    if args.hexdump_rows > SECTOR // 16:
        refuse(f"--hexdump-rows must be <= {SECTOR // 16} (one sector)")

    check_target(args.device)

    try:
        fd = os.open(args.device, os.O_RDONLY)
    except OSError as exc:
        print(f"ERROR: cannot open {args.device} read-only: {exc}",
              file=sys.stderr)
        return 2

    try:
        size = os.lseek(fd, 0, os.SEEK_END)
        nblocks = size // BLOCK
        print(f"target: {args.device}  size: {size:,} bytes "
              f"({nblocks:,} x {BLOCK // (1024 * 1024)}MiB blocks)")

        report_first_sector(fd, args.hexdump_rows)
        report_signatures(fd, args.signature_window)
        if nblocks < 1:
            print(f"\n  target is smaller than one {BLOCK // (1024 * 1024)}MiB "
                  f"block; skipping entropy and string sampling")
        else:
            report_entropy(fd, nblocks, args.samples)
            report_strings(fd, nblocks, args.string_blocks, args.max_strings)
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
