"""Catch lost history, fictitious freshness, unsafe output/HTTP and mixed snapshots."""
import csv
import importlib.util
import json
import pathlib
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.dont_write_bytecode = True
TOOL = pathlib.Path(__file__).resolve().parents[1] / 'tools' / 'control_gateway'
sys.path.insert(0, str(TOOL))
spec = importlib.util.spec_from_file_location('capture', TOOL / 'capture.py')
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def status(sequence=1, age=0, simulated=False, flags=0x7f0001):
    words = list(range(27))
    words[0], words[1], words[5], words[6], words[21] = 20261007, 0x30001, 6010, 280, flags
    words[15:18] = [0, 0, 0]
    return dict(simulated=simulated, stale=age >= 500, age_ms=age, owned=False,
                acknowledged=False, dropped_packets=0,
                telemetry=dict(session=7, sequence=sequence, words=words))


class CaptureTest(unittest.TestCase):
    def test_streams_all_history_and_preserves_raw_invalid_words(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = pathlib.Path(directory) / 'long'
            with capture.CaptureLog(prefix) as log:
                for i in range(650):
                    log.add(status(i, flags=1 << 16), i * 200, '2026-10-07T00:00:00Z')
                log.add(status(649, 700, flags=1 << 16), 130500, '2026-10-07T00:02:10Z')
                self.assertEqual(log.stats['snapshots'], 650)
                self.assertEqual(log.stats['stale_polls'], 1)
            with prefix.with_suffix('.csv').open(newline='') as f:
                rows = list(csv.DictReader(f))
            self.assertEqual(len(rows), 650, 'long capture must not inherit browser 600-row truncation')
            self.assertEqual(rows[0]['cpu_full_frame_fps_x100'], '280', 'invalid raw CPU is retained, not fabricated zero')
            self.assertEqual(rows[0]['status_flags'], '65536')
            self.assertEqual(len(prefix.with_suffix('.jsonl').read_text().splitlines()), 651)
            summary = json.loads(prefix.with_suffix('.summary.json').read_text())
            self.assertEqual(summary['qualification'], 'capture_only_not_board_acceptance')
            self.assertEqual(summary['invalid_error_group_snapshots'], 650)

    def test_gaps_errors_reset_simulated_and_torn_duplicate(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = pathlib.Path(directory) / 'stress'
            with capture.CaptureLog(prefix) as log:
                log.add(status(1, simulated=True), 0, 't0')
                sample = status(4, 10, simulated=True)
                sample['telemetry']['words'][15:18] = [1, 2, 3]
                log.add(sample, 200, 't1')
                self.assertEqual(log.stats['observed_sequence_gaps'], 2)
                self.assertEqual(log.stats['nonzero_underflow_windows'], 1)
                self.assertEqual(log.stats['nonzero_gpu_error_windows'], 1)
                self.assertEqual(log.stats['nonzero_missed_windows'], 1)
                self.assertEqual(log.stats['simulated_polls'], 2)
                torn = status(4)
                with self.assertRaises(ValueError):
                    log.add(torn, 300, 't2')
                reset = status(1)
                reset['telemetry']['session'] = 8
                log.add(reset, 400, 't3')
                self.assertEqual(log.stats['sequence_discontinuities'], 1)
                log.error('HTTP disconnected', 600, 't4')
                self.assertEqual(log.stats['errors'], 1)

    def test_exclusive_outputs_leave_old_evidence_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = pathlib.Path(directory) / 'run'
            old = prefix.with_suffix('.summary.json')
            old.write_text('original', encoding='ascii')
            with self.assertRaises(FileExistsError):
                with capture.CaptureLog(prefix):
                    self.fail('must refuse existing output')
            self.assertEqual(old.read_text(), 'original')
            self.assertFalse(prefix.with_suffix('.csv').exists())

    def test_invalid_fields_rejected_without_csv_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            with capture.CaptureLog(pathlib.Path(directory) / 'bad') as log:
                for value in (-1, 0x100000000, True):
                    view = status()
                    view['telemetry']['words'][5] = value
                    with self.assertRaises(ValueError):
                        log.add(view, 0, 't')
                view = status()
                view['telemetry']['words'].pop()
                with self.assertRaises(ValueError):
                    log.add(view, 0, 't')
                self.assertEqual(log.stats['snapshots'], 0)

    def test_real_http_read_only_reconnect_and_no_redirect_or_remote_urls(self):
        requests = []

        class Handler(BaseHTTPRequestHandler):
            count = 0

            def do_GET(self):
                requests.append(self.path)
                Handler.count += 1
                if Handler.count == 1:
                    self.send_error(503)
                else:
                    body = json.dumps(status(Handler.count, simulated=True)).encode()
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

            def do_POST(self):
                raise AssertionError('capture must never acquire or change control')

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                url = 'http://127.0.0.1:' + str(server.server_port)
                result = capture.collect(url, pathlib.Path(directory) / 'http', .35, .1)
                self.assertGreaterEqual(result['snapshots'], 1)
                self.assertEqual(result['errors'], 1)
                self.assertTrue(all(path == '/api/status' for path in requests))
                self.assertGreaterEqual(result['simulated_polls'], 1)
            for url in ('http://example.com', 'http://localhost:8765', 'https://127.0.0.1',
                        'http://127.0.0.1:8765@evil.test', 'http://127.0.0.1:8765/other'):
                with self.assertRaises(ValueError):
                    capture.validate_url(url)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_redirect_and_oversize_response_rejected(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.server.large:
                    body = b'x' * 65537
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                else:
                    self.send_response(302)
                    self.send_header('Location', 'http://example.com/')
                    self.end_headers()

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.large = False
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = 'http://127.0.0.1:' + str(server.server_port)
            with self.assertRaises(Exception):
                capture.read_status(url)
            server.large = True
            with self.assertRaises(ValueError):
                capture.read_status(url)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_receipt_timestamp_is_after_slow_http_reply(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                time.sleep(.12)
                body = json.dumps(status()).encode()
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                prefix = pathlib.Path(directory) / 'receipt'
                capture.collect('http://127.0.0.1:' + str(server.server_port), prefix, .15, .1)
                first = json.loads(prefix.with_suffix('.jsonl').read_text().splitlines()[0])
                self.assertGreaterEqual(first['elapsed_ms'], 100, 'receipt cannot precede the response')
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main(verbosity=2)
