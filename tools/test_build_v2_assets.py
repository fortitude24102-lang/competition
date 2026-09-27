import pathlib
import tempfile
import unittest
import zlib

from tools.build_v2_assets import build


class AssetsTest(unittest.TestCase):
    def test_manifest_and_rgb565_sizes(self):
        source = pathlib.Path(__file__).resolve().parents[1] / "sw/efinix_gpu/assets/source"
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory)
            build(source, out)
            entries = []
            for line in (out / "manifest.csv").read_text(encoding="ascii").splitlines():
                asset_id, filename = line.split(",")
                data = (out / filename).read_bytes()
                entries.append((int(asset_id), filename, len(data), zlib.crc32(data)))
            self.assertEqual([entry[0] for entry in entries], [1, 2, 3, 4])
            self.assertEqual([entry[2] for entry in entries], [960 * 540 * 2, 64 * 80 * 2,
                                                             64 * 80 * 2, 64 * 80 * 2])
            catalog = (out / "asset_catalog.h").read_text(encoding="ascii")
            for _, _, _, crc in entries:
                self.assertIn(f"0x{crc:08x}", catalog)
            self.assertTrue((out / "preview.png").is_file())


if __name__ == "__main__":
    unittest.main()
