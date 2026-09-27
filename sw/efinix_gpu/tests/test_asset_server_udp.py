import pathlib
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib


class AssetServerUdpTest(unittest.TestCase):
    def test_repository_resources_full_crc(self):
        assets = pathlib.Path(os.environ["ASSET_SERVER_TEST_DIRECTORY"]) if "ASSET_SERVER_TEST_DIRECTORY" in os.environ else pathlib.Path(__file__).resolve().parents[1] / "assets" / "v2"
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        server = subprocess.Popen([str(PROGRAM), str(assets / "manifest.csv"), str(port)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                client.settimeout(0.3)
                for record in (assets / "manifest.csv").read_text().splitlines():
                    if not record or record.startswith("#"):
                        continue
                    asset_id, filename = record.split(",")
                    expected = (assets / filename).read_bytes()
                    received = bytearray()
                    for sequence, offset in enumerate(range(0, len(expected), 1024)):
                        length = min(1024, len(expected) - offset)
                        request = struct.pack(">IHHIIIHHII", 0x41535354, 1, 1, 47,
                                              int(asset_id), offset, length, 0, sequence, 0)
                        for _ in range(30):
                            try:
                                client.sendto(request, ("127.0.0.1", port))
                                response, _ = client.recvfrom(1500)
                                break
                            except (socket.timeout, ConnectionResetError):
                                self.assertIsNone(server.poll())
                                time.sleep(0.01)
                        else:
                            self.fail("repository resource GET timed out")
                        h = struct.unpack_from(">IHHIIIHHII", response)
                        self.assertEqual(h[2:7], (2, 47, int(asset_id), offset, length))
                        self.assertEqual(h[7], int(offset + length == len(expected)))
                        self.assertEqual(h[8], sequence)
                        self.assertEqual(h[9], zlib.crc32(response[32:]))
                        self.assertEqual(len(response), 32 + length)
                        received.extend(response[32:])
                    self.assertEqual(received, expected)
                    self.assertEqual(zlib.crc32(received), zlib.crc32(expected))
        finally:
            server.terminate()
            server.wait(timeout=2)

    def test_reads_file_and_replies_only_to_get(self):
        program = PROGRAM
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            payload = bytes(range(256)) * 5
            (root / "scene.pkg").write_bytes(payload)
            (root / "manifest.csv").write_text("7,scene.pkg\n", encoding="ascii")
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                client.bind(("127.0.0.1", 0))
                client.settimeout(0.3)
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as port_probe:
                    port_probe.bind(("127.0.0.1", 0))
                    port = port_probe.getsockname()[1]
                server = subprocess.Popen([str(program), str(root / "manifest.csv"), str(port)],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    request = struct.pack(">IHHII IHHII", 0x41535354, 1, 1, 23, 7,
                                          0, 1024, 0, 0, 0)
                    for _ in range(30):
                        try:
                            client.sendto(request, ("127.0.0.1", port))
                            response, _ = client.recvfrom(1500)
                            break
                        except (socket.timeout, ConnectionResetError):
                            self.assertIsNone(server.poll(), "server exited before replying")
                            time.sleep(0.01)
                    else:
                        self.fail("server did not answer GET")
                    self.assertEqual(len(response), 1056)
                    self.assertEqual(struct.unpack_from(">H", response, 6)[0], 2)
                    self.assertEqual(struct.unpack_from(">I", response, 28)[0], zlib.crc32(payload[:1024]))
                    self.assertEqual(response[32:], payload[:1024])
                    final = struct.pack(">IHHII IHHII", 0x41535354, 1, 1, 23, 7,
                                        1024, 256, 0, 1, 0)
                    client.sendto(final, ("127.0.0.1", port))
                    response, _ = client.recvfrom(1500)
                    self.assertEqual(struct.unpack_from(">H", response, 22)[0], 1)
                    self.assertEqual(response[32:], payload[1024:])
                finally:
                    server.terminate()
                    server.wait(timeout=2)


if __name__ == "__main__":
    PROGRAM = pathlib.Path(sys.argv[1]).resolve()
    sys.argv.pop(1)
    unittest.main()
