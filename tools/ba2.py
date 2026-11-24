"""Read, list, extract and pack Fallout 76 general (GNRL) BA2 archives.

Usage:
  python -I tools/ba2.py list    <archive.ba2>
  python -I tools/ba2.py extract <archive.ba2> <outdir> [name-filter ...]
  python -I tools/ba2.py pack    <archive.ba2> <archive-path>=<source-file> ...

Archive paths use the game's form, for example Interface\\PriceScout.swf.
Packed files are stored uncompressed, which the game accepts.
"""

import os
import struct
import sys
import zlib

BACKSLASH = "\\"
RECORD = struct.Struct("<I4sIIQIII")  # name hash, ext, dir hash, flags, offset, packed, size, align
HEADER = struct.Struct("<4sI4sIQ")  # magic, version, type, file count, name table offset
FLAGS = 0x00100100
ALIGN = 0xBAADF00D


def _crc_table():
    table = []
    for i in range(256):
        c = i
        for _ in range(8):
            c = (c >> 1) ^ 0xEDB88320 if c & 1 else c >> 1
        table.append(c)
    return table


CRC_TABLE = _crc_table()


def bs_crc32(text):
    """Bethesda's BA2 hash: reflected CRC-32 with no initial or final XOR."""
    c = 0
    for b in text.encode("utf-8"):
        c = CRC_TABLE[(c ^ b) & 0xFF] ^ (c >> 8)
    return c


def hashes(archive_path):
    """Return (name hash, ext bytes, dir hash) the way the game looks files up."""
    path = archive_path.replace("/", BACKSLASH).lower()
    directory, _, filename = path.rpartition(BACKSLASH)
    stem, dot, ext = filename.rpartition(".")
    if not dot:
        stem, ext = filename, ""
    ext_bytes = ext.encode("ascii")[:4].ljust(4, b"\0")
    return bs_crc32(stem), ext_bytes, bs_crc32(directory)


def read(archive):
    with open(archive, "rb") as f:
        magic, version, kind, count, name_offset = HEADER.unpack(f.read(HEADER.size))
        if magic != b"BTDX" or kind != b"GNRL":
            raise SystemExit(f"{archive}: not a general BA2 ({magic!r} {kind!r})")
        f.seek(HEADER.size + (8 if version in (2, 3) else 0) + (4 if version == 3 else 0))
        records = [RECORD.unpack(f.read(RECORD.size)) for _ in range(count)]
        f.seek(name_offset)
        names = []
        for _ in range(count):
            (length,) = struct.unpack("<H", f.read(2))
            names.append(f.read(length).decode("utf-8"))
        entries = []
        for name, rec in zip(names, records):
            f.seek(rec[4])
            data = f.read(rec[5] or rec[6])
            if rec[5]:
                data = zlib.decompress(data)
            entries.append((name, rec, data))
        return version, entries


def pack(archive, files):
    """files: list of (archive path, bytes)."""
    count = len(files)
    data_offset = HEADER.size + RECORD.size * count
    records, blobs, offset = [], [], data_offset
    for path, data in files:
        name_hash, ext, dir_hash = hashes(path)
        records.append(RECORD.pack(name_hash, ext, dir_hash, FLAGS, offset, 0, len(data), ALIGN))
        blobs.append(data)
        offset += len(data)
    names = b"".join(struct.pack("<H", len(p.encode())) + p.encode() for p, _ in files)
    with open(archive, "wb") as f:
        f.write(HEADER.pack(b"BTDX", 1, b"GNRL", count, offset))
        f.writelines(records)
        f.writelines(blobs)
        f.write(names)


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    command, archive, rest = argv[0], argv[1], argv[2:]
    if command == "list":
        version, entries = read(archive)
        print(f"{archive}: version {version}, {len(entries)} files")
        for name, rec, data in entries:
            expected = hashes(name)
            ok = (rec[0], rec[1], rec[2]) == expected
            print(f"  {name}  {len(data)} bytes  hashes {'ok' if ok else 'MISMATCH'}")
    elif command == "extract":
        _, entries = read(archive)
        out, filters = rest[0], [x.lower() for x in rest[1:]]
        for name, _, data in entries:
            if filters and not any(x in name.lower() for x in filters):
                continue
            target = os.path.join(out, *name.replace(BACKSLASH, "/").split("/"))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as f:
                f.write(data)
            print(name, len(data))
    elif command == "pack":
        files = []
        for spec in rest:
            path, _, source = spec.partition("=")
            with open(source, "rb") as f:
                files.append((path, f.read()))
        pack(archive, files)
        print(f"wrote {archive} ({len(files)} files)")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
