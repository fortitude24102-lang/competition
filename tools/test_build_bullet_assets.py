import importlib.util
import pathlib
import tempfile
import unittest
import zlib


class BulletAssetsTest(unittest.TestCase):
    def test_original_assets_have_exact_shape_key_and_crc(self):
        path = pathlib.Path(__file__).with_name("build_bullet_assets.py")
        self.assertTrue(path.exists(), "bullet asset generator is missing")
        spec = importlib.util.spec_from_file_location("bullet_assets", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp)
            module.build(out)
            bg = (out / "background.rgb565").read_bytes()
            atlas = (out / "atlas.rgb565").read_bytes()
            self.assertEqual(len(bg), 1036800)
            self.assertEqual(len(atlas), 1184)
            self.assertEqual(atlas[:2], b"\x1f\xf8")  # Transparent corner.
            self.assertEqual(atlas[2*(3*8+3):2*(3*8+3)+2], b"\xff\xff")
            # Radius squared 34 is the outermost opaque ring on this 8x8 lattice.
            self.assertEqual(atlas[2*(2*8+1):2*(2*8+1)+2], b"\x08\x42")
            self.assertEqual((out / "manifest.csv").read_text(),
                             "101,background.rgb565\n102,atlas.rgb565\n")
            catalog = (out / "bullet_asset_catalog.h").read_text()
            self.assertIn(f"0x{zlib.crc32(bg):08x}u", catalog)
            self.assertIn(f"0x{zlib.crc32(atlas):08x}u", catalog)
            before = bg, atlas
            module.build(out)
            self.assertEqual(before, ((out / "background.rgb565").read_bytes(),
                                      (out / "atlas.rgb565").read_bytes()))


if __name__ == "__main__":
    unittest.main()
