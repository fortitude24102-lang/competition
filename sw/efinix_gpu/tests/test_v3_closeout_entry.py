"""A missing executable must never inherit a previous test's successful exit code."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]


class CloseoutEntryTest(unittest.TestCase):
    def test_missing_node_cannot_emit_success_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            out = pathlib.Path(directory) / 'checks'
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                     str(ROOT / 'scripts/test-v3-ab-closeout.ps1'), '-Out', str(out),
                                     '-Node', str(pathlib.Path(directory) / 'missing-node.exe')],
                                    cwd=ROOT, capture_output=True, text=True, timeout=45)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((out / 'receipt.json').exists(), 'missing check cannot produce a PASS receipt')

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            sentinel = pathlib.Path(directory) / 'receipt.json'
            sentinel.write_text('old evidence')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                     str(ROOT / 'scripts/test-v3-ab-closeout.ps1'), '-Out', directory],
                                    cwd=ROOT, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(), 'old evidence')


if __name__ == '__main__':
    unittest.main(verbosity=2)
