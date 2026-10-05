"""V3 contracts exercised with real loopback UDP/HTTP; no board required."""
import http.client
import importlib.util
import json
import pathlib
import socket
import struct
import sys
import threading
import time
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[3]
TOOLS = ROOT / 'sw/efinix_gpu/tools/control_gateway'
sys.path.insert(0, str(TOOLS))


def wire(kind, session=7, sequence=9, words=None):
    words = words if words is not None else ([0] * 27 if kind == 128 else [0] * 3)
    size = 128 if kind == 128 else 32
    body = struct.pack('>4sBBHII', b'AGT1' if size == 128 else b'AGC1',
                       1, kind, size, session, sequence)
    body += struct.pack('>' + 'I' * len(words), *words)
    return body + struct.pack('>I', zlib.crc32(body))


class ProtocolTest(unittest.TestCase):
    def test_deliverable_exists(self):
        self.assertIsNotNone(importlib.util.find_spec('protocol'), 'fixed packet codec missing')

    def test_wire_and_bad_packets(self):
        import protocol as p
        for kind, words in [(1, [0, 0, 0]), (2, [255, 0xffffffff, 0]),
                            (3, [1, 0, 0]), (128, list(range(27)))]:
            expected = wire(kind, words=words)
            self.assertEqual(p.encode(kind, 7, 9, words), expected)
            self.assertEqual(p.decode(expected).words, tuple(words))
            for bad in [expected[:-1], expected + b'\0', expected[:4] + b'\2' + expected[5:],
                        expected[:-1] + bytes([expected[-1] ^ 1])]:
                with self.assertRaises(ValueError):
                    p.decode(bad)
        for kind, words in [(1, [1, 0, 0]), (2, [256, 0, 0]), (2, [0, 0, 1]),
                            (3, [0, 0, 0]), (4, [0, 0, 0])]:
            with self.assertRaises(ValueError):
                p.decode(wire(kind, words=words))
        self.assertTrue(p.newer(0, 0xffffffff))
        self.assertFalse(p.newer(0x80000000, 0))
        self.assertFalse(p.newer(4, 4))

    def test_fixed_cross_language_vectors(self):
        import protocol as p
        vectors = json.loads((ROOT / 'tb/vectors/v3_control_packets.json').read_text())
        for v in vectors['packets']:
            self.assertEqual(p.encode(v['type'], v['session'], v['sequence'], v['words']).hex(), v['hex'])


class StateTest(unittest.TestCase):
    def state(self):
        from gateway import GatewayState
        return GatewayState()

    def test_ack_gate_ownership_lease_and_rate(self):
        s = self.state()
        a, b = 'a' * 32, 'b' * 32
        self.assertEqual(s.control(a, 1, 0, now=0), 200)
        hello = s.next_packet(0)
        import protocol as p
        h = p.decode(hello)
        self.assertEqual(h.kind, 1)
        self.assertNotEqual(h.session, 0)
        self.assertEqual(s.control(b, 2, 0, now=.1), 409)
        self.assertIsNone(s.next_packet(.1))
        s.receive(wire(3, h.session, h.sequence + 1, [1, 0, 0]), .1)
        self.assertIsNone(s.next_packet(.12))
        s.receive(wire(3, h.session, h.sequence, [1, 0, 0]), .12)
        self.assertEqual(p.decode(s.next_packet(.13)).words[0], 1)
        self.assertIsNone(s.next_packet(.131))
        self.assertEqual(p.decode(s.next_packet(.251)).words[0], 0)
        self.assertIsNone(s.next_packet(.5))
        self.assertEqual(s.control(b, 4, 0, now=.6), 200)
        new = p.decode(s.next_packet(.6))
        self.assertNotEqual(new.session, h.session)
        s.receive(wire(3, h.session, h.sequence, [1, 0, 0]), .61)
        self.assertIsNone(s.next_packet(.62))

    def test_snapshot_crc_order_wrap_stale_and_reset(self):
        s = self.state()
        words = list(range(27))
        words[21] = (1 << 16) | (1 << 21)
        self.assertTrue(s.receive(wire(128, 0, 0xffffffff, words), 1))
        self.assertFalse(s.receive(wire(128, 0, 0xffffffff, [0] * 27), 1.1))
        self.assertFalse(s.receive(wire(128, 0, 0xfffffffe, [0] * 27), 1.1))
        corrupt = bytearray(wire(128, 0, 0, words)); corrupt[20] ^= 1
        self.assertFalse(s.receive(bytes(corrupt), 1.2))
        view = s.view(1.2)
        self.assertEqual(view['telemetry']['words'], words)
        self.assertIsNone(view['telemetry']['display']['cpu_full_frame_fps_x100'])
        self.assertEqual(view['telemetry']['display']['gpu_full_frame_fps_x100'], 5)
        self.assertFalse(view['stale'])
        self.assertTrue(s.view(1.501)['stale'])
        self.assertTrue(s.receive(wire(128, 0, 0, words), 1.3))
        # A change of firmware identity is an explicit reset epoch.
        words[0] = 99
        self.assertTrue(s.receive(wire(128, 0, 0, words), 1.4))

    def test_retry_and_reset_use_new_session_and_reject_delayed_ack(self):
        import protocol as p
        s = self.state(); client = 'a' * 32
        s.control(client, 4, 0, now=0)
        first = p.decode(s.next_packet(0))
        s.control(client, 4, 0, now=.2)
        self.assertFalse(s.receive(wire(3, first.session, first.sequence, [1, 0, 0]), .26))
        s.control(client, 4, 0, now=.4)
        second = p.decode(s.next_packet(.5))
        self.assertNotEqual(second.session, first.session)
        self.assertTrue(s.receive(wire(3, second.session, second.sequence, [1, 0, 0]), .51))
        self.assertEqual(p.decode(s.next_packet(.52)).words[0], 4)
        reset = [0] * 27
        self.assertTrue(s.receive(wire(128, 0, 0, reset), .53))
        self.assertFalse(s.view(.53)['acknowledged'])
        s.control(client, 4, 0, now=.6); s.control(client, 4, 0, now=.8)
        s.control(client, 4, 0, now=.95)
        third = p.decode(s.next_packet(1.0))
        self.assertEqual(third.kind, 1)
        self.assertNotEqual(third.session, second.session)
        self.assertFalse(s.receive(wire(3, second.session, second.sequence, [1, 0, 0]), 1.01))

    def test_delayed_retired_firmware_and_resource_do_not_roll_back_snapshot(self):
        s = self.state()
        first = [0] * 27; first[0] = 1; first[1] = 5
        self.assertTrue(s.receive(wire(128, 0, 10, first), 0))
        same = first.copy(); same[1] = 6
        self.assertFalse(s.receive(wire(128, 0, 9, same), .1))
        reboot = first.copy(); reboot[0] = 2
        self.assertTrue(s.receive(wire(128, 0, 0, reboot), .2))
        self.assertFalse(s.receive(wire(128, 0, 11, first), .3))

    def test_bound_total_udp_rate_hello_rate_and_latest_input(self):
        import protocol as p
        s = self.state(); client = 'a' * 32
        self.assertIsNone(s.next_packet(0))
        sent = []
        for millisecond in range(1201):
            now = millisecond / 1000
            s.control(client, millisecond & 255, millisecond, now=now)
            packet = s.next_packet(now)
            if packet: sent.append((now, p.decode(packet)))
        self.assertLessEqual(len(sent), 3)
        self.assertTrue(all(b[0]-a[0] >= .5 for a,b in zip(sent,sent[1:])))
        last = sent[-1][1]
        self.assertTrue(s.receive(wire(3,last.session,last.sequence,[1,0,0]),1.21))
        keys = []
        for millisecond in range(1210,2210):
            now = millisecond / 1000
            s.control(client, millisecond & 255, millisecond, now=now)
            if millisecond % 100 == 0:
                words=[0]*27; words[21]=16
                s.receive(wire(128,s.session,millisecond,words),now)
            packet=s.next_packet(now)
            if packet:
                decoded=p.decode(packet); keys.append((now,decoded))
                self.assertEqual(decoded.words[0],millisecond & 255)
        self.assertLessEqual(len(keys),60)
        self.assertTrue(all(b[0]-a[0] >= 1/60 for a,b in zip(keys,keys[1:])))

    def test_release_competitor_cannot_clear_owner(self):
        s = self.state(); s.control('a'*32,1,0,now=0)
        self.assertEqual(s.control('b'*32,0,0,release=True,now=.1),409)
        self.assertEqual(s.keys,1)
        self.assertEqual(s.control('a'*32,0,0,release=True,now=.1),200)
        self.assertFalse(s.view(.1)['owned'])

    def test_global_snapshot_sequence_rejects_delayed_observer_without_ack_loss(self):
        import protocol as p
        s=self.state(); client='a'*32
        s.control(client,1,0,now=0); hello=p.decode(s.next_packet(0))
        self.assertTrue(s.receive(wire(3,hello.session,hello.sequence,[1,0,0]),.01))
        active=[0]*27;active[0]=7;active[21]=16
        self.assertTrue(s.receive(wire(128,hello.session,100,active),.02))
        observer=active.copy();observer[21]=0
        self.assertFalse(s.receive(wire(128,0,99,observer),.03))
        self.assertFalse(s.receive(wire(128,0,100,observer),.04))
        view=s.view(.04)
        self.assertEqual(view['telemetry']['sequence'],100)
        self.assertEqual(view['telemetry']['session'],hello.session)
        self.assertTrue(view['acknowledged'])
        self.assertEqual(view['session'],hello.session)
        self.assertEqual(view['age_ms'],20)
        # The board's genuinely newer observer state does revoke the old handshake.
        self.assertTrue(s.receive(wire(128,0,101,observer),.05))
        self.assertEqual(s.view(.05)['telemetry']['sequence'],101)
        self.assertFalse(s.view(.05)['acknowledged'])
        self.assertNotEqual(s.session,hello.session)

    def test_global_sequence_wrap_across_control_observer_boundary(self):
        import protocol as p
        s=self.state();s.control('a'*32,1,0,now=0);hello=p.decode(s.next_packet(0))
        s.receive(wire(3,hello.session,hello.sequence,[1,0,0]),.01)
        active=[0]*27;active[0]=7;active[21]=16
        self.assertTrue(s.receive(wire(128,hello.session,0xffffffff,active),.02))
        observer=active.copy();observer[21]=0
        self.assertTrue(s.receive(wire(128,0,0,observer),.03))
        self.assertEqual(s.view(.03)['telemetry']['sequence'],0)

    def test_stale_then_fresh_ack_allows_one_new_session_reset_baseline(self):
        import protocol as p
        s=self.state();client='a'*32
        s.control(client,1,0,now=0);first=p.decode(s.next_packet(0))
        s.receive(wire(3,first.session,first.sequence,[1,0,0]),.01)
        active=[0]*27;active[0]=7;active[21]=16
        self.assertTrue(s.receive(wire(128,first.session,100,active),.02))
        reset=active.copy();reset[21]=0
        self.assertFalse(s.receive(wire(128,0,0,reset),.03))
        # Same-build observer reset is ambiguous; recover after stale evidence.
        for now in [.2,.4,.53]:s.control(client,1,0,now=now)
        self.assertEqual(p.decode(s.next_packet(.53)).words[0],0)
        for now in [.7,.8]:s.control(client,1,0,now=now)
        fresh=p.decode(s.next_packet(.8));self.assertEqual(fresh.kind,1)
        self.assertNotEqual(fresh.session,first.session)
        self.assertFalse(s.receive(wire(3,first.session,first.sequence,[1,0,0]),.81))
        self.assertTrue(s.receive(wire(3,fresh.session,fresh.sequence,[1,0,0]),.81))
        self.assertTrue(s.receive(wire(128,fresh.session,1,active),.82))
        self.assertEqual(s.view(.82)['telemetry']['sequence'],1)
        self.assertTrue(s.view(.82)['acknowledged'])
        self.assertFalse(s.receive(wire(128,0,0,reset),.83))
        self.assertTrue(s.view(.83)['acknowledged'])
        self.assertFalse(s.receive(wire(128,fresh.session,0,active),.84))
        self.assertTrue(s.receive(wire(128,fresh.session,2,active),.85))

    def test_quick_browser_reclaim_cannot_reset_global_snapshot_sequence(self):
        import protocol as p
        s=self.state();s.control('a'*32,1,0,now=0);first=p.decode(s.next_packet(0))
        s.receive(wire(3,first.session,first.sequence,[1,0,0]),.01)
        active=[0]*27;active[0]=7;active[21]=16
        self.assertTrue(s.receive(wire(128,first.session,100,active),.02))
        # A new tab gets a new session, but the still-running device has the same snapshot counter.
        s.control('a'*32,0,0,release=True,now=.4)
        self.assertEqual(p.decode(s.next_packet(.4)).words[0],0)
        s.control('b'*32,1,0,now=.5);fresh=p.decode(s.next_packet(.5))
        self.assertTrue(s.receive(wire(3,fresh.session,fresh.sequence,[1,0,0]),.51))
        self.assertFalse(s.receive(wire(128,fresh.session,99,active),.515))
        self.assertTrue(s.view(.515)['acknowledged'])
        self.assertEqual(s.view(.515)['telemetry']['sequence'],100)
        self.assertTrue(s.receive(wire(128,fresh.session,101,active),.516))


class LoopbackTest(unittest.TestCase):
    def setUp(self):
        from gateway import Gateway
        self.peer = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.peer.bind(('127.0.0.1', 0)); self.peer.settimeout(.6)
        self.gateway = Gateway(peer=self.peer.getsockname(), udp_bind=('127.0.0.1', 0), http_port=0)
        self.gateway.start()
        self.port = self.gateway.http.server_port
        self.origin = 'http://127.0.0.1:' + str(self.port)
        self.token = self.request('GET', '/api/bootstrap')[1]['token']

    def tearDown(self):
        self.gateway.close(); self.peer.close()

    def request(self, method, path, payload=None, origin=True, raw=None):
        c = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        headers = {'Content-Type': 'application/json'}
        if origin: headers['Origin'] = self.origin if origin is True else origin
        body = raw if raw is not None else json.dumps(payload) if payload is not None else None
        c.request(method, path, body, headers)
        r = c.getresponse(); data = r.read(); status = r.status; c.close()
        return status, json.loads(data) if data else {}

    def post(self, keys=1, client='a' * 32, **kwargs):
        return self.request('POST', '/api/control', dict(token=self.token, client=client,
                            keys=keys, action_sequence=0, release=False), **kwargs)

    def test_http_validation_static_whitelist_and_udp_peer(self):
        for origin in [False, 'http://evil.invalid']:
            self.assertEqual(self.post(origin=origin)[0], 403)
        self.assertEqual(self.request('POST', '/api/control', raw='x' * 1025)[0], 413)
        self.assertEqual(self.request('POST', '/api/control', {'token': 'bad'})[0], 403)
        self.assertEqual(self.post(keys=256)[0], 400)
        self.assertEqual(self.post(keys=True)[0], 400)
        self.assertEqual(self.request('POST', '/api/control', {'token': '\u00e9'})[0],403)
        self.assertEqual(self.request('POST', '/api/control', raw='{')[0],400)
        for path in ['/../README.md', '/README.md', '/web/', '/?file=README.md']:
            self.assertEqual(self.request('GET', path)[0], 404)
        self.assertEqual(self.post()[0], 200)
        hello, addr = self.peer.recvfrom(256)
        import protocol as p
        h = p.decode(hello)
        stranger = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try: stranger.sendto(wire(3, h.session, h.sequence, [1, 0, 0]), addr)
        finally: stranger.close()
        time.sleep(.04)
        self.assertFalse(self.gateway.state.view()['acknowledged'])
        self.peer.sendto(wire(3, h.session, h.sequence, [1, 0, 0]), addr)
        packet, _ = self.peer.recvfrom(256)
        self.assertEqual(p.decode(packet).words[0], 1)
        time.sleep(.3)
        packets = [packet]
        self.peer.settimeout(.05)
        try:
            while True: packets.append(self.peer.recvfrom(256)[0])
        except socket.timeout: pass
        self.assertEqual(p.decode(packets[-1]).words[0], 0)
        self.assertFalse(self.gateway.state.view()['owned'])

    def test_slow_sse_and_flood_do_not_block_atomic_udp(self):
        slow = socket.create_connection(('127.0.0.1', self.port), timeout=2)
        slow.sendall(('GET /api/events HTTP/1.1\r\nHost: 127.0.0.1:' + str(self.port) + '\r\n\r\n').encode())
        try:
            addr = self.gateway.udp.getsockname()
            for sequence in range(250):
                words = [sequence] * 27; words[0] = 123; words[21] = 0x7f0000
                self.peer.sendto(wire(128, 0, sequence, words), addr)
                if sequence % 20 == 0: time.sleep(.003)
            final = [777] * 27; final[0] = 123; final[21] = 0x7f0000
            self.peer.sendto(wire(128, 0, 300, final), addr)
            end = time.monotonic() + 1
            while time.monotonic() < end:
                v = self.request('GET', '/api/status')[1]
                if v.get('telemetry', {}).get('sequence') == 300: break
                time.sleep(.01)
            self.assertEqual(v['telemetry']['words'], final)
            self.assertEqual(self.post()[0], 200)
            self.assertEqual(self.post(client='b' * 32)[0], 409)
            self.assertEqual(len(self.gateway.state.view()['telemetry']['words']), 27)
        finally: slow.close()

    def test_udp_flood_cannot_extend_browser_lease(self):
        import protocol as p
        self.assertEqual(self.post(keys=16)[0],200)
        hello,addr=self.peer.recvfrom(256); hello=p.decode(hello)
        self.peer.sendto(wire(3,hello.session,hello.sequence,[1,0,0]),addr)
        self.assertEqual(p.decode(self.peer.recvfrom(256)[0]).words[0],16)
        stop=threading.Event()
        def flood():
            sequence=0
            while not stop.is_set():
                words=[0]*27; words[21]=16; sequence+=1
                self.peer.sendto(wire(128,hello.session,sequence,words),addr)
                self.peer.sendto(b'corrupt',addr)
        thread=threading.Thread(target=flood,daemon=True);thread.start()
        started=time.monotonic(); cleared=False
        try:
            while time.monotonic()-started<.5:
                packet=p.decode(self.peer.recvfrom(256)[0])
                if packet.kind==2 and packet.words[0]==0:
                    cleared=True;break
            self.assertTrue(cleared,'flood must not prevent deadline zero clear')
            self.assertLess(time.monotonic()-started,.4)
            self.assertFalse(self.gateway.state.view()['owned'])
        finally:
            stop.set();thread.join(timeout=1)

    def test_missing_peer_icmp_does_not_kill_reconnect(self):
        addr=self.peer.getsockname();self.peer.close()
        self.assertEqual(self.post()[0],200)
        for _ in range(6):
            time.sleep(.1);self.assertEqual(self.post()[0],200)
        self.assertTrue(self.gateway.threads[0].is_alive(),'unreachable board must not kill UDP worker')
        self.peer=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.peer.bind(addr);self.peer.settimeout(.8)
        import protocol as p
        stop=threading.Event()
        def heartbeat():
            while not stop.wait(.1): self.post()
        thread=threading.Thread(target=heartbeat,daemon=True);thread.start()
        try:
            hello,source=self.peer.recvfrom(256);hello=p.decode(hello)
            self.assertEqual(hello.kind,1)
            self.peer.sendto(wire(3,hello.session,hello.sequence,[1,0,0]),source)
            self.assertEqual(p.decode(self.peer.recvfrom(256)[0]).words[0],1)
        finally:stop.set();thread.join(timeout=1)

    def test_udp_shutdown_race_does_not_raise_worker_exception(self):
        errors=[];prior=threading.excepthook
        threading.excepthook=lambda args: errors.append(args.exc_value)
        try:
            self.gateway.udp.close()
            time.sleep(.025)
            self.gateway.close()
            self.assertEqual(errors,[])
        finally:
            threading.excepthook=prior
        # tearDown can safely close an already closed gateway.


class SimulatedPeerTest(unittest.TestCase):
    def test_simulated_peer_only_ack_echo_and_lease_clear(self):
        self.assertIsNotNone(importlib.util.find_spec('fake_board'), 'explicit fake board missing')
        from fake_board import FakeBoard
        import protocol as p
        peer = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        peer.bind(('127.0.0.1', 0)); peer.settimeout(.6)
        fake = FakeBoard(('127.0.0.1', 0), peer.getsockname())
        fake.start()
        try:
            addr = fake.udp.getsockname()
            peer.sendto(wire(1, 17, 99), addr)
            end = time.monotonic() + .5; ack = None
            while time.monotonic() < end:
                packet = p.decode(peer.recvfrom(256)[0])
                if packet.kind == 3: ack = packet; break
            self.assertEqual((ack.session, ack.sequence, ack.words), (17, 99, (1, 0, 0)))
            peer.sendto(wire(2, 17, 100, [16, 4, 0]), addr)
            end = time.monotonic() + .2
            while time.monotonic() < end and fake.keys != 16: time.sleep(.005)
            self.assertEqual(fake.keys, 16)
            time.sleep(.28)
            self.assertEqual(fake.keys, 0)
            self.assertEqual(fake.session, 0)
            # Retired session cannot be resurrected by delayed HELLO/KEYS.
            peer.sendto(wire(1, 17, 99), addr); peer.sendto(wire(2, 17, 101, [16, 4, 0]), addr)
            time.sleep(.03); self.assertEqual(fake.keys, 0)
            self.assertEqual(fake.telemetry_words()[5:7], (0, 0))
            self.assertEqual(fake.telemetry_words()[21], 1 << 21)
        finally:
            fake.close(); peer.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
