#!/usr/bin/env python3
"""Preserve smaller source PNGs when iconutil re-encodes ICNS images."""

import pathlib
import struct
import sys


def preserve_pngs(icon: pathlib.Path, sources: pathlib.Path) -> None:
    representations = {
        b"ic11": ("16@2x", 32),
        b"ic12": ("32@2x", 64),
        b"ic07": ("128", 128),
        b"ic13": ("128@2x", 256),
        b"ic08": ("256", 256),
        b"ic14": ("256@2x", 512),
        b"ic09": ("512", 512),
        b"ic10": ("512@2x", 1024),
    }
    data = icon.read_bytes()
    if len(data) < 8 or data[:4] != b"icns" or struct.unpack_from(">I", data, 4)[0] != len(data):
        raise ValueError("Invalid ICNS header")
    chunks = []
    offset = 8
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("Incomplete ICNS chunk header")
        kind, length = struct.unpack_from(">4sI", data, offset)
        if length < 8 or offset + length > len(data):
            raise ValueError("Invalid ICNS chunk length")
        payload = data[offset + 8:offset + length]
        if kind in representations:
            name, size = representations[kind]
            source = (sources / f"icon-{name}.png").read_bytes()
            if (len(source) < 33 or source[:8] != b"\x89PNG\r\n\x1a\n"
                    or source[8:16] != b"\x00\x00\x00\rIHDR"
                    or struct.unpack_from(">II", source, 16) != (size, size)):
                raise ValueError(f"Invalid {size}-pixel PNG: icon-{name}.png")
            if len(source) < len(payload):
                payload = source
        chunks.append(struct.pack(">4sI", kind, len(payload) + 8) + payload)
        offset += length
    body = b"".join(chunks)
    icon.write_bytes(struct.pack(">4sI", b"icns", len(body) + 8) + body)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: preserve-icon-pngs.py /path/to/AppIcon.icns /path/to/AppIcon.appiconset")
    preserve_pngs(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
