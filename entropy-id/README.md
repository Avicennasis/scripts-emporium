# Entropy ID

![Python](https://img.shields.io/badge/language-python-blue) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

Read-only triage of a raw block device or disk image. Answers the question you
have when a second-hand drive lands on the bench: **is this thing already
sanitised, is it full-disk encrypted, or is it still carrying somebody's data?**

Nothing is ever written. The target is opened `O_RDONLY` and only `pread()` is
used.

## How it decides

Byte-frequency entropy is the discriminator:

| Observation | Reading |
|-------------|---------|
| ~8.00 bits/byte, uniform across the disk | Random overwrite **or** full-disk encryption — entropy alone cannot tell these apart, so look at the signature scan |
| Below ~7.5 with structure, plus readable strings | Real data still present |
| Near 0.0 | Zero-filled |

Compressed media (JPEG, video, archives) also runs high, which is why the
readable-string search matters: real filesystem metadata essentially always
leaks filenames, paths, and document extensions somewhere.

The report has four parts:

1. **First sector** hexdump, the `0x55AA` MBR boot signature test, and that
   sector's entropy.
2. **Known signature scan** over the head of the device for BitLocker
   (`-FVE-FS-`), LUKS, PGP WDE, McAfee SafeBoot, NTFS, and GPT magic.
3. **Entropy across the disk** at evenly spaced 1 MiB samples, with mean/min/max.
4. **Readable-string search** across many more spread samples, printing only
   strings that look like filenames, paths, URLs, or document extensions.

## Safety

Reading the wrong raw device is the entire hazard of a tool like this, so two
refusals are enforced **before the device is opened at all** (exit status 2):

- **`/dev/sda`, and any partition of it** — almost always the system disk. Same
  guard as `bin/build-*-usb.sh` in Simmons-Systems-Rescue.
- **Any device with a mounted partition**, including mounts reached through
  LVM / device-mapper / md. The device's partitions and everything stacked on
  top of them are resolved through sysfs and matched against
  `/proc/self/mountinfo`.

There is deliberately no `--force`.

## Requirements

- Python 3.9+ — standard library only, no third-party packages
- Linux (uses `/sys/class/block` and `/proc/self/mountinfo`)
- Root, or another way to read the raw device — reading `/dev/sdX` normally
  needs it. Disk **image files** work unprivileged.

## Usage

```bash
sudo ./entropy_id.py /dev/sdX [OPTIONS]
./entropy_id.py disk-image.img [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h`, `--help` | Show help message and exit | - |
| `--signature-window MIB` | Size in MiB of the head region scanned for FDE/filesystem magic | `32` |
| `--samples N` | Number of evenly spaced 1 MiB entropy samples | `10` |
| `--string-blocks N` | Number of spread blocks searched for readable strings | `40` |
| `--max-strings N` | Stop after this many readable-string hits | `25` |
| `--hexdump-rows N` | 16-byte rows of sector 0 to hexdump (max 32) | `8` |

### Exit status

| Code | Meaning |
|------|---------|
| `0` | Report produced |
| `2` | Refused, or the target does not exist / cannot be opened / bad arguments |

### Examples

**Triage a second-hand drive:**

```bash
sudo ./entropy_id.py /dev/sdc
```

**Quick look — fewer samples, shorter string hunt:**

```bash
sudo ./entropy_id.py /dev/sdc --samples 4 --string-blocks 8 --max-strings 5
```

**Deeper signature hunt on a drive whose header may be offset:**

```bash
sudo ./entropy_id.py /dev/sdc --signature-window 128
```

**Inspect an image file, no root needed:**

```bash
./entropy_id.py recovered.img
```

### Sample output

A 128 MiB image overwritten with random data — the "already sanitised or
encrypted" signature:

```
  MBR boot signature (0x55AA at 510): 8dfe -> absent
  first-sector entropy: 7.623 bits/byte
...
    7.8% (blk      10) entropy 7.9998 bits/byte
   25.0% (blk      32) entropy 7.9998 bits/byte
...
  mean 7.9998, min 7.9998, max 7.9998
...
  NONE -- no filenames, paths, or document extensions anywhere.
  Real filesystem data essentially always leaks such strings.
```

The same size image still holding a filesystem:

```
  MBR boot signature (0x55AA at 510): 55aa -> PRESENT
  first-sector entropy: 0.249 bits/byte
...
  FOUND 'NTFS boot sector' at offset 3
...
  mean 0.0042, min 0.0042, max 0.0042
...
  [ 12.5%] Users/jdoe/Documents/annual_report_2019.pdf
  [ 12.5%] Program Files/SomeVendor/updater.exe
```

## Credits

**Author:** Léon "Avic" Simmons — [GitHub](https://github.com/Avicennasis)
