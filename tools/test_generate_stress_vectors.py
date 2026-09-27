import pathlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib


SCRIPT = pathlib.Path(__file__).with_name("generate_stress_vectors.py")


class StressVectorsTest(unittest.TestCase):
    def test_legal_commands_and_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "stress_vectors.bin"
            subprocess.run([sys.executable, str(SCRIPT), str(output)], check=True)
            data = output.read_bytes()
        magic, version, header, desc, command, tiers, seed, total, crc, reserved = struct.unpack_from(
            "<4sHHHHIIIII", data
        )
        self.assertEqual((magic, version, header, desc, command, tiers, seed, reserved),
                         (b"SVEC", 1, 32, 16, 32, 5, 0x20260921, 0))
        self.assertEqual(zlib.crc32(data[32:]), crc)
        offset = 32
        seen = 0
        for tier_index, expected_sprites in enumerate((16, 32, 64, 96, 128)):
            frame = (0x02000000, 0x02200000)[tier_index & 1]
            sprites, count, first, last, expected_pixels = struct.unpack_from("<IIHHI", data, offset)
            offset += 16
            self.assertEqual((sprites, count), (expected_sprites, sprites + 2))
            pixels = 0
            for index in range(count):
                op, alpha, flags, tag, zero, src, dst, width, height, src_stride, dst_stride, color, key = struct.unpack_from(
                    "<BBHHHIIHHIIHH", data, offset
                )
                offset += 32
                self.assertEqual(tag, (first + index) & 0xFFFF)
                self.assertEqual((alpha, flags, zero), (255, 0, 0))
                self.assertGreaterEqual(dst, frame)
                self.assertLessEqual(dst + (height - 1) * dst_stride + width * 2,
                                     frame + 960 * 540 * 2)
                self.assertGreater(width, 0)
                self.assertGreater(height, 0)
                self.assertEqual(dst_stride, 1920)
                if op == 1:
                    pixels += width * height
                else:
                    self.assertEqual(op, 6)
            self.assertEqual(last, (first + count - 1) & 0xFFFF)
            self.assertEqual(expected_pixels, pixels)
            seen += count
        self.assertEqual((seen, offset), (total, len(data)))


if __name__ == "__main__":
    unittest.main()
