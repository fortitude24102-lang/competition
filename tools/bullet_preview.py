"""Encode a freshly rendered RGB565 frame as PNG, without imaging packages."""
import argparse
import pathlib
import struct
import zlib


def encode(data):
    if len(data) != 960*540*2:
        raise ValueError("expected one complete 960x540 RGB565 framebuffer")
    raw = bytearray()
    for y in range(540):
        raw.append(0)
        for x in range(960):
            p = struct.unpack_from("<H", data, 2*(y*960+x))[0]
            r, g, b = p >> 11, (p >> 5) & 63, p & 31
            raw.extend(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)))

    def chunk(kind, content):
        return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind+content))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 960, 540, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("output")
    args = parser.parse_args()
    pathlib.Path(args.output).write_bytes(encode(pathlib.Path(args.source).read_bytes()))
