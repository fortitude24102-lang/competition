"""Real loopback HTTP checks; only the test collector gets a separate heartbeat."""
import json
import pathlib
import subprocess
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HELPER = pathlib.Path(__file__).resolve().parents[3] / 'scripts' / 'control-keepalive.py'


class KeepaliveTest(unittest.TestCase):
    def setUp(self):
        self.posts = []
        self.arrived = threading.Event()
        self.status = 200
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                owner.posts.append((time.monotonic(), self.path, body, self.headers['Origin']))
                self.send_response(owner.status)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'{}')
                owner.arrived.set()

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:%d' % self.server.server_port
        self.child = None

    def tearDown(self):
        if self.child:
            if not self.child.stdin.closed:
                self.child.stdin.close()
            try:
                self.child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.child.kill()
                self.child.wait()
            self.child.stdout.close()
            self.child.stderr.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def start(self, url=None):
        self.child = subprocess.Popen([sys.executable, '-u', str(HELPER)], stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.body = dict(token='test-token', client='test-client', keys=0, action_sequence=2, release=False)
        self.child.stdin.write(json.dumps(dict(url=url or self.url, body=self.body)) + '\n')
        self.child.stdin.flush()

    def test_heartbeat_survives_a_busy_collector_and_stops_on_eof(self):
        self.start()
        self.assertTrue(self.arrived.wait(2), 'missing keepalive HTTP request')
        time.sleep(.48)  # The collector does no heartbeat work for > the 250ms lease.
        self.child.stdin.close()
        self.assertEqual(self.child.wait(timeout=2), 0)
        self.assertGreaterEqual(len(self.posts), 5)
        self.assertLess(max(b[0]-a[0] for a, b in zip(self.posts, self.posts[1:])), .23)
        for _, path, body, origin in self.posts:
            self.assertEqual((path, body, origin), ('/api/control', self.body, self.url))
        count = len(self.posts)
        time.sleep(.15)
        self.assertEqual(len(self.posts), count)

    def test_denial_aborts_instead_of_renewing_a_different_owner(self):
        self.status = 409
        self.start()
        self.assertEqual(self.child.wait(timeout=2), 1)
        self.assertEqual(len(self.posts), 1)

    def test_remote_destination_is_rejected_before_any_request(self):
        self.start('http://192.0.2.1:8765')
        self.assertEqual(self.child.wait(timeout=2), 1)
        self.assertEqual(self.posts, [])


if __name__ == '__main__':
    unittest.main()
