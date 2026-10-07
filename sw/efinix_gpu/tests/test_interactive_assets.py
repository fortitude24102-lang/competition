"""Resource bytes, epoch and cache/DDR bounds, independent of board hardware."""
import hashlib
import importlib.util
import json
import pathlib
import re
import tempfile
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[3]


class InteractiveAssetsTest(unittest.TestCase):
    def test_exact_r7_resources_and_explicit_epoch(self):
        path = ROOT / "tools/build_interactive_assets.py"
        self.assertTrue(path.exists(), "interactive resource manifest builder is missing")
        spec = importlib.util.spec_from_file_location("interactive_assets", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory)
            module.build(out, epoch=0x30001)
            manifest = json.loads((out / "resource_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["resource_epoch"], 0x30001)
            self.assertEqual(manifest["atlas_bytes"], 3104)
            self.assertLessEqual(manifest["atlas_bytes"], 4096)
            self.assertTrue(manifest["invalidate_both_buffers_before_load"])
            self.assertEqual([asset["id"] for asset in manifest["assets"]], [101, 102, 103])
            for asset, expected_bytes, address in zip(manifest["assets"], (1036800, 3104), (0x2900000, 0x2a00000)):
                data = (out / asset["file"]).read_bytes()
                self.assertEqual(data, (ROOT / "sw/efinix_gpu/assets/bullet" / asset["file"]).read_bytes())
                self.assertEqual(len(data), expected_bytes)
                self.assertEqual(asset["crc32"], f"{zlib.crc32(data):08x}")
                self.assertEqual(asset["sha256"], hashlib.sha256(data).hexdigest())
                self.assertEqual(asset["ddr_address"], address)
                self.assertLessEqual(address + len(data), 0x2b00000)
            before = (out / "resource_manifest.json").read_bytes()
            module.build(out, epoch=0x30001)
            self.assertEqual(before, (out / "resource_manifest.json").read_bytes())
            module.build(out, epoch=0x30002)
            changed = json.loads((out / "resource_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(changed["resource_epoch"], 0x30002)
            self.assertEqual(changed["assets"], manifest["assets"])
            self.assertIn("CC0-1.0", (out / "LICENSES.md").read_text(encoding="utf-8"))
            logo = manifest["assets"][2]
            image = (out / logo["file"]).read_bytes()
            self.assertEqual((logo["width"], logo["height"], logo["stride_bytes"]), (200, 70, 400))
            self.assertEqual(logo["ddr_address"], 0x02c50000)
            self.assertEqual(len(image), 28000)
            self.assertEqual(logo["crc32"], f"{zlib.crc32(image):08x}")
            self.assertEqual(logo["sha256"], hashlib.sha256(image).hexdigest())
            self.assertEqual(image, (ROOT / "sw/efinix_gpu/assets/hud/competition_logo.rgb565").read_bytes())
            self.assertNotEqual(logo["license"], "CC0-1.0")
            catalog = (ROOT / "sw/efinix_gpu/assets/hud/hud_logo_catalog.h").read_text()
            self.assertEqual(int(re.search(r"HUD_LOGO_CRC32 0x([0-9a-f]+)u", catalog)[1], 16), zlib.crc32(image))
            provenance = json.loads((ROOT / "sw/efinix_gpu/assets/hud/logo_source.json").read_text())
            original = (ROOT / "sw/efinix_gpu/assets/hud/competition_logo_source.png").read_bytes()
            self.assertEqual(provenance["source_sha256"], hashlib.sha256(original).hexdigest())
            self.assertEqual(provenance["crc32"], logo["crc32"])
            self.assertLess(abs(provenance["source_width"] / provenance["source_height"] - 200 / 70), 0.02)
            with self.assertRaises(ValueError):
                module.build(out, epoch=0)


if __name__ == "__main__":
    unittest.main()
