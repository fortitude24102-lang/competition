"""Generate the frozen SVEC v1 GPU command fixture."""

import pathlib
import struct
import sys
import zlib


TIERS = (16, 32, 64, 96, 128)
FRAME_WIDTH = 960
FRAME_HEIGHT = 540
STRIDE = FRAME_WIDTH * 2
FRAMES = (0x02000000, 0x02200000)


def command(op, tag, destination, width, height, color):
    return struct.pack(
        "<BBHHHIIHHIIHH", op, 255, 0, tag, 0, 0, destination,
        width, height, 0, STRIDE, color, 0,
    )


def build():
    body = bytearray()
    tag = 0
    total_commands = 0
    for tier_index, sprites in enumerate(TIERS):
        frame = FRAMES[tier_index & 1]
        first_tag = tag
        commands = []
        commands.append(command(1, tag, frame, FRAME_WIDTH, FRAME_HEIGHT, 0x07E0))
        tag = (tag + 1) & 0xFFFF
        for index in range(sprites):
            x = (index % 16) * 56
            y = 56 + (index // 16) * 48
            commands.append(command(1, tag, frame + y * STRIDE + x * 2, 16, 16, 0xF800))
            tag = (tag + 1) & 0xFFFF
        commands.append(command(6, tag, frame, 1, 1, 0))
        tag = (tag + 1) & 0xFFFF
        expected_pixels = FRAME_WIDTH * FRAME_HEIGHT + sprites * 256
        body.extend(struct.pack("<IIHHI", sprites, len(commands), first_tag,
                                (tag - 1) & 0xFFFF, expected_pixels))
        body.extend(b"".join(commands))
        total_commands += len(commands)
    header = struct.pack("<4sHHHHIIIII", b"SVEC", 1, 32, 16, 32,
                         len(TIERS), 0x20260921, total_commands,
                         zlib.crc32(body), 0)
    return header + body


if __name__ == "__main__":
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("tb/vectors/stress_vectors.bin")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(build())
