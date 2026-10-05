"""Resource bytes, epoch and cache/DDR bounds, independent of board hardware."""
import hashlib
import importlib.util
import json
import pathlib
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
            with self.assertRaises(ValueError):
                module.build(out, epoch=0)


if __name__ == "__main__":
    unittest.main()
