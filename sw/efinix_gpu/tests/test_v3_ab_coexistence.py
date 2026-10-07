"""Real PC resource UDP + control UDP/HTTP + observer capture, explicitly simulated peer."""
import csv
import json
import os
import pathlib
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
import zlib

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'sw/efinix_gpu/tools/control_gateway'))
from gateway import Gateway
from fake_board import FakeBoard


class CoexistenceTest(unittest.TestCase):
    def test_three_services_and_documented_capture_entry(self):
        program = pathlib.Path(os.environ['V3_ASSET_SERVER']).resolve()
        self.assertTrue(program.is_file())
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(('127.0.0.1', 0))
            resource_port = probe.getsockname()[1]
        fake = FakeBoard(('127.0.0.1', 0), ('127.0.0.1', 1))
        gateway = Gateway(fake.udp.getsockname(), ('127.0.0.1', 0), 0, True)
        fake.gateway = gateway.udp.getsockname()
        catalog = ROOT / 'sw/efinix_gpu/assets/interactive'
        server = subprocess.Popen([str(program), str(catalog / 'manifest.csv'), str(resource_port)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        stop = threading.Event()
        failures = []
        control_thread = None

        def control():
            try:
                while not stop.is_set():
                    payload = json.dumps(dict(token=gateway.token, client='a' * 32, keys=2,
                                              action_sequence=0, release=False)).encode()
                    request = urllib.request.Request('http://' + gateway.authority + '/api/control', payload,
                                                     {'Content-Type': 'application/json', 'Origin': 'http://' + gateway.authority})
                    with urllib.request.urlopen(request, timeout=.5) as response:
                        self.assertEqual(response.status, 200)
                    stop.wait(.033)
            except BaseException as error:
                failures.append(error)

        try:
            fake.start()
            gateway.start()
            time.sleep(.25)
            self.assertEqual(fake.session, 0, 'no browser must not acquire control')
            self.assertIsNone(gateway.state.owner)
            control_thread = threading.Thread(target=control, daemon=True)
            control_thread.start()
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                client.settimeout(.3)
                for record in (catalog / 'manifest.csv').read_text().splitlines():
                    asset_id, filename = record.split(',')
                    expected = (catalog / filename).read_bytes()
                    received = bytearray()
                    for sequence, offset in enumerate(range(0, len(expected), 1024)):
                        size = min(1024, len(expected) - offset)
                        request = struct.pack('>IHHIIIHHII', 0x41535354, 1, 1, 17,
                                              int(asset_id), offset, size, 0, sequence, 0)
                        for _ in range(5):
                            client.sendto(request, ('127.0.0.1', resource_port))
                            try:
                                data, _ = client.recvfrom(1500)
                                break
                            except (socket.timeout, ConnectionResetError):
                                self.assertIsNone(server.poll())
                        else:
                            self.fail('resource timeout while control active')
                        header = struct.unpack_from('>IHHIIIHHII', data)
                        self.assertEqual(header[2:7], (2, 17, int(asset_id), offset, size))
                        self.assertEqual(header[8], sequence)
                        self.assertEqual(header[9], zlib.crc32(data[32:]))
                        received.extend(data[32:])
                    self.assertEqual(received, expected)
            with tempfile.TemporaryDirectory() as directory:
                prefix = pathlib.Path(directory) / 'documented'
                result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                         str(ROOT / 'scripts/capture-v3-telemetry.ps1'), '-Out', str(prefix),
                                         '-Url', 'http://' + gateway.authority, '-Seconds', '1', '-Interval', '.1'],
                                        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        timeout=10, text=True)
                self.assertEqual(result.returncode, 0, result.stdout)
                with prefix.with_suffix('.csv').open(newline='') as f:
                    rows = list(csv.DictReader(f))
                self.assertGreaterEqual(len(rows), 3)
                self.assertTrue(all(row['simulated'] == '1' for row in rows))
                self.assertTrue(all(int(row['status_flags']) & (1 << 21) for row in rows))
                self.assertTrue(gateway.state.acknowledged)
                self.assertEqual(fake.keys, 2)
            stop.set()
            control_thread.join(timeout=2)
            time.sleep(.32)
            self.assertIsNone(gateway.state.owner)
            self.assertEqual(fake.keys, 0)
            self.assertEqual(failures, [])
        finally:
            stop.set()
            if control_thread:
                control_thread.join(timeout=2)
            gateway.close()
            fake.close()
            server.terminate()
            server.wait(timeout=2)


if __name__ == '__main__':
    unittest.main(verbosity=2)
