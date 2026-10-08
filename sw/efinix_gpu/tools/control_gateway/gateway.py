"""Local V3 keyboard bridge; never executes game or rendering logic."""
import argparse
import hmac
import json
import pathlib
import re
import secrets
import select
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import protocol as p

LEASE = .250
STALE = .500
WEB = pathlib.Path(__file__).resolve().parent / 'web'


class GatewayState:
    """One latest input, one latest snapshot; protected independently of HTTP writes."""
    def __init__(self, simulated=False):
        self.lock = threading.RLock()
        self.owner = None
        self.session = self.sequence = self.hello_sequence = 0
        self.keys = self.action = 0
        self.heartbeat = 0.0
        self.acknowledged = False
        self.last_send = self.last_hello = float('-inf')
        self.ack_time = 0.0
        self.hello_sent = False
        self.hello_ready = float('-inf')
        self.clear_pending = None
        self.telemetry = None
        self.telemetry_rebase_session = 0
        self.retired_builds = []
        self.telemetry_time = 0.0
        self.drops = 0
        self.simulated = simulated
        self.game_request = None
        self.last_keys = float('-inf')

    def _cancel_game(self):
        g=self.game_request
        if g and g['state'] in ('pending','await_snapshot'): g['state']='unknown'

    def _game_timeout(self, now):
        g=self.game_request
        if g and now-g['created'] >= 2: self._cancel_game()

    def _confirm_game(self):
        g=self.game_request; t=self.telemetry
        if (g and g['state']=='await_snapshot' and t and t.session==g['session']
                and p.newer(t.sequence,g['snapshot_floor'])): g['state']='applied'

    def game(self, client, opcode, level, request_id, now=None):
        now=time.monotonic() if now is None else now
        if (opcode not in ('start','menu') or type(level) is not int or
                type(request_id) is not int or not 1<=request_id<=0xffffffff or
                not (opcode=='start' and 1<=level<=4 or opcode=='menu' and level==0)): return 400
        with self.lock:
            self._expire(now);self._game_timeout(now)
            if self.owner!=client: return 409
            t=self.telemetry
            if not self.acknowledged or t is None or now-self.telemetry_time>=STALE or not t.words[21]&(1<<11): return 503
            g=self.game_request
            if g and g['session']==self.session and g['request_id']==request_id:
                return 202 if (g['opcode'],g['level'])==(opcode,level) else 409
            if g and g['state'] in ('pending','await_snapshot'): return 409
            if g and g['session']==self.session and not p.newer(request_id,g['request_id']): return 409
            self.keys=0
            self.game_request=dict(request_id=request_id,opcode=opcode,level=level,state='pending',
                result=None,snapshot_floor=None,session=self.session,created=now,
                last_attempt=float('-inf'),sequences=[])
            return 202

    def _sequence(self):
        self.sequence = (self.sequence + 1) & 0xffffffff
        return self.sequence

    def _begin_session(self):
        self._cancel_game()
        previous = self.session
        while self.session == previous or self.session == 0:
            self.session = secrets.randbits(32)
        self.sequence = secrets.randbits(32)
        self.hello_sequence = self._sequence()
        self.acknowledged = self.hello_sent = False
        self.telemetry_rebase_session = 0

    def _release(self):
        self._cancel_game()
        if self.owner:
            self.clear_pending = p.encode(p.KEYS, self.session, self._sequence(), [0, self.action, 0])
        self.owner = None
        self.keys = self.action = 0
        self.acknowledged = False
        self.telemetry_rebase_session = 0

    def _expire(self, now):
        self._game_timeout(now)
        if self.owner and now - self.heartbeat >= LEASE:
            self._release()

    def control(self, client, keys, action_sequence, release=False, now=None):
        now = time.monotonic() if now is None else now
        with self.lock:
            self._expire(now)
            if self.owner and self.owner != client:
                return 409
            if release:
                if self.owner == client:
                    self._release()
                return 200
            if self.owner is None:
                self.owner = client
                self._begin_session()
                self.hello_ready = now
            self.keys, self.action, self.heartbeat = keys, action_sequence, now
            if self.game_request and self.game_request['state'] in ('pending','await_snapshot'): self.keys=0
            return 200

    def next_packet(self, now=None):
        now = time.monotonic() if now is None else now
        with self.lock:
            self._expire(now)
            if now - self.last_send < 1 / 60:
                return None
            if self.clear_pending is not None:
                packet, self.clear_pending = self.clear_pending, None
            elif not self.owner:
                return None
            else:
                # Lack of fresh board evidence requires a renewed explicit ACK.
                evidence = max(self.ack_time, self.telemetry_time)
                if self.acknowledged and now - evidence >= STALE:
                    self.clear_pending = p.encode(p.KEYS, self.session, self._sequence(), [0, self.action, 0])
                    self._begin_session()
                    # Allow the old board lease to expire after its final clear.
                    self.hello_ready = now + LEASE
                    packet, self.clear_pending = self.clear_pending, None
                    self.last_send = now
                    return packet
                if not self.acknowledged:
                    if now - self.last_hello < .5 or now < self.hello_ready:
                        return None
                    if self.hello_sent:
                        # A 500 ms retry outlives the board's 250 ms lease: expired sessions cannot be reused.
                        self._begin_session()
                    self.last_hello = now
                    self.hello_sent = True
                    packet = p.encode(p.HELLO, self.session, self.hello_sequence, [0, 0, 0])
                else:
                    g=self.game_request
                    # Reserve a zero KEYS heartbeat at least every 100 ms.
                    if g and g['state']=='pending' and now-g['last_attempt']>=.05 and now-self.last_keys<.1:
                        seq=self._sequence();g['last_attempt']=now;g['sequences'].append(seq)
                        g['sequences']=g['sequences'][-40:]
                        packet=p.encode(p.GAME,self.session,seq,[p.GAME_START if g['opcode']=='start' else p.GAME_MENU,g['level'],g['request_id']])
                    else:
                        packet = p.encode(p.KEYS, self.session, self._sequence(), [self.keys, self.action, 0])
                        self.last_keys=now
            self.last_send = now
            return packet

    def receive(self, data, now=None):
        now = time.monotonic() if now is None else now
        try:
            packet = p.decode(data)
        except ValueError:
            with self.lock: self.drops += 1
            return False
        with self.lock:
            self._expire(now)
            if packet.kind == p.ACK:
                if (self.owner and self.hello_sent and not self.acknowledged
                        and now - self.last_hello < LEASE and packet.session == self.session
                        and packet.sequence == self.hello_sequence):
                    self.acknowledged = True
                    self.ack_time = now
                    # A fresh session ACK after stale telemetry is evidence for a reboot.
                    # It permits only that new session's first active snapshot to reset the baseline.
                    if self.telemetry is not None and now - self.telemetry_time >= STALE:
                        self.telemetry_rebase_session = self.session
                    return True
            elif packet.kind == p.GAME_ACK:
                g=self.game_request
                if (g and g['state']=='pending' and self.owner and self.acknowledged
                        and packet.session==self.session==g['session']
                        and packet.sequence in g['sequences'] and packet.words[0]==g['request_id']):
                    g['result'],g['snapshot_floor']=packet.words[1:]
                    g['state']='await_snapshot' if g['result']==0 else 'rejected'
                    self._confirm_game()
                    return True
            elif packet.kind == p.TELEMETRY:
                old = self.telemetry
                if packet.words[0] in self.retired_builds:
                    self.drops += 1
                    return False
                # Only display observer (session 0) or the current control session.
                if packet.session not in (0, self.session):
                    self.drops += 1
                    return False
                # nc_device snapshot_id is global across resource/control-session changes.
                # Observer packets must pass the same ordering check as active packets.
                same_build = old is not None and packet.words[0] == old.words[0]
                reset_baseline = (old is not None and self.acknowledged
                                  and packet.session == self.telemetry_rebase_session != 0
                                  and packet.session != old.session and packet.words[21] & (1 << 4))
                if same_build and not reset_baseline and not p.newer(packet.sequence, old.sequence):
                    self.drops += 1
                    return False
                if old is not None and packet.words[0] != old.words[0]:
                    self.retired_builds.append(old.words[0])
                    self.retired_builds = self.retired_builds[-4:]
                self.telemetry, self.telemetry_time = packet, now
                self._confirm_game()
                if packet.session == self.telemetry_rebase_session:
                    self.telemetry_rebase_session = 0
                if self.owner and self.acknowledged and (packet.session == 0 or not packet.words[21] & (1 << 4)):
                    self._begin_session()
                    self.hello_ready = now
                return True
            self.drops += 1
            return False

    def view(self, now=None):
        now = time.monotonic() if now is None else now
        with self.lock:
            self._expire(now)
            t = self.telemetry
            age = None if t is None else max(0, round((now - self.telemetry_time) * 1000))
            g=self.game_request
            return dict(game=None if g is None else {k:g[k] for k in ('request_id','opcode','level','state','result','snapshot_floor')},
                        simulated=self.simulated, owned=self.owner is not None,
                        acknowledged=self.acknowledged, session=self.session,
                        input_age_ms=None if not self.owner else max(0, round((now - self.heartbeat) * 1000)),
                        stale=t is None or now - self.telemetry_time >= STALE,
                        age_ms=age, dropped_packets=self.drops,
                        telemetry=None if t is None else dict(session=t.session, sequence=t.sequence,
                            words=list(t.words), raw=dict(zip(p.FIELDS, t.words)),
                            display=p.display_words(t.words)))


class BoundedHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False
    def __init__(self, address, handler):
        self.slots = threading.BoundedSemaphore(16)
        self.sse_slots = threading.BoundedSemaphore(8)
        super().__init__(address, handler)

    def process_request(self, request, address):
        if not self.slots.acquire(False):
            self.shutdown_request(request)
            return
        try:
            request.settimeout(.5)
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try: super().process_request_thread(request, address)
        finally: self.slots.release()


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    @property
    def app(self):
        return self.server.app

    def reply(self, status, data):
        body = json.dumps(data, separators=(',', ':')).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def valid_host(self):
        return self.headers.get('Host') == self.app.authority

    def do_GET(self):
        if not self.valid_host():
            return self.reply(403, {'error': 'local host required'})
        if self.path == '/api/bootstrap':
            return self.reply(200, dict(token=self.app.token, simulated=self.app.state.simulated))
        if self.path == '/api/status':
            return self.reply(200, self.app.state.view())
        if self.path == '/api/events':
            return self.events()
        files = {'/': ('index.html', 'text/html; charset=utf-8'),
                 '/dashboard.js': ('dashboard.js', 'text/javascript; charset=utf-8'),
                 '/styles.css': ('styles.css', 'text/css; charset=utf-8')}
        if self.path not in files:
            return self.reply(404, {'error': 'not found'})
        name, mime = files[self.path]
        body = (WEB / name).read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers(); self.wfile.write(body)

    def events(self):
        if not self.server.sse_slots.acquire(False):
            return self.reply(503, {'error': 'too many telemetry viewers'})
        try:
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Connection', 'close')
            self.end_headers()
            while not self.app.stop.is_set():
                body = json.dumps(self.app.state.view(), separators=(',', ':')).encode()
                # Never hold the state lock across a slow network write.
                self.wfile.write(b'data: ' + body + b'\n\n'); self.wfile.flush()
                self.app.stop.wait(.2)
        except (OSError, TimeoutError):
            pass
        finally:
            self.close_connection = True
            self.server.sse_slots.release()

    def do_POST(self):
        if not self.valid_host() or self.headers.get('Origin') != 'http://' + self.app.authority:
            return self.reply(403, {'error': 'same origin required'})
        if self.path not in ('/api/control','/api/game'):
            return self.reply(404, {'error': 'not found'})
        length = self.headers.get('Content-Length', '')
        if self.headers.get('Transfer-Encoding') or not length.isdecimal():
            return self.reply(400, {'error': 'bounded Content-Length required'})
        if int(length) > 1024:
            return self.reply(413, {'error': 'JSON exceeds 1024 bytes'})
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
            return self.reply(415, {'error': 'JSON required'})
        try:
            obj = json.loads(self.rfile.read(int(length)))
            if not isinstance(obj, dict): raise ValueError()
            token = obj.get('token')
            if (not isinstance(token, str) or not re.fullmatch('[0-9a-f]{64}', token)
                    or not hmac.compare_digest(token, self.app.token)):
                return self.reply(403, {'error': 'token required'})
            client=obj.get('client')
            if not isinstance(client, str) or not re.fullmatch('[0-9a-f]{32}', client): raise ValueError()
            if self.path=='/api/game':
                if set(obj)!={'token','client','opcode','level','request_id'}: raise ValueError()
                status=self.app.state.game(client,obj['opcode'],obj['level'],obj['request_id'])
                return self.reply(status,dict(accepted=status==202,game=self.app.state.view()['game']))
            if set(obj) != {'token', 'client', 'keys', 'action_sequence', 'release'}: raise ValueError()
            client, keys, action, release = (obj[k] for k in ('client', 'keys', 'action_sequence', 'release'))
            if not isinstance(client, str) or not re.fullmatch('[0-9a-f]{32}', client): raise ValueError()
            if type(keys) is not int or not 0 <= keys <= 255: raise ValueError()
            if type(action) is not int or not 0 <= action <= 0xffffffff: raise ValueError()
            if type(release) is not bool or (release and keys): raise ValueError()
        except (ValueError, OSError):
            return self.reply(400, {'error': 'invalid control JSON'})
        status = self.app.state.control(client, keys, action, release)
        self.reply(status, {'accepted': status == 200, 'error': None if status == 200 else 'another browser owns control'})


class Gateway:
    def __init__(self, peer, udp_bind=('0.0.0.0', 8090), http_port=8765, simulated=False):
        self.peer = (socket.gethostbyname(peer[0]), peer[1])
        self.state = GatewayState(simulated)
        self.token = secrets.token_hex(32)
        self.stop = threading.Event()
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.bind(udp_bind); self.udp.setblocking(False)
        try:
            self.http = BoundedHTTPServer(('127.0.0.1', http_port), Handler)
        except Exception:
            self.udp.close(); raise
        self.http.app = self
        self.authority = '127.0.0.1:' + str(self.http.server_port)
        self.threads = []

    def start(self):
        for target in (self.run_udp, self.http.serve_forever):
            thread = threading.Thread(target=target, daemon=True)
            thread.start(); self.threads.append(thread)

    def run_udp(self):
        while not self.stop.is_set():
            try:
                readable, _, _ = select.select([self.udp], [], [], .003)
            except (OSError, ValueError):
                with self.state.lock: self.state.drops += 1
                if self.udp.fileno() < 0:
                    self.stop.set()
                    break
                if self.stop.wait(.01): break
                continue
            if readable:
                for _ in range(32):
                    try: data, sender = self.udp.recvfrom(2048)
                    except BlockingIOError: break
                    except OSError:
                        # Windows delivers peer ICMP-unreachable as recvfrom WinError 10054.
                        # The board may be absent/reset; keep the input lease and retry loop alive.
                        with self.state.lock: self.state.drops += 1
                        break
                    if sender == self.peer:
                        self.state.receive(data)
                    else:
                        with self.state.lock: self.state.drops += 1
            packet = self.state.next_packet()
            if packet:
                try: self.udp.sendto(packet, self.peer)
                except OSError:
                    with self.state.lock: self.state.drops += 1

    def close(self):
        with self.state.lock: self.state._release()
        # Preserve the send-rate bound for the final zero packet too.
        self.stop.wait(1 / 60)
        packet = self.state.next_packet()
        if packet:
            try: self.udp.sendto(packet, self.peer)
            except OSError: pass
        self.stop.set()
        if self.threads: self.http.shutdown()
        for thread in self.threads: thread.join(timeout=1)
        self.http.server_close(); self.udp.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board', required=True, help='fixed board IPv4/address')
    parser.add_argument('--board-port', type=int, default=8090)
    parser.add_argument('--udp-bind', default='0.0.0.0')
    parser.add_argument('--udp-port', type=int, default=8090)
    parser.add_argument('--http-port', type=int, default=8765)
    parser.add_argument('--simulated', action='store_true', help='label an explicitly simulated peer')
    args = parser.parse_args()
    app = Gateway((args.board, args.board_port), (args.udp_bind, args.udp_port), args.http_port, args.simulated)
    app.start()
    print(('SIMULATED / NOT BOARD MEASUREMENT — ' if args.simulated else '') + 'http://' + app.authority, flush=True)
    print('Fixed UDP peer %s:%s; Ctrl+C stops and clears control.' % app.peer, flush=True)
    try:
        while not app.stop.wait(.5): pass
    except KeyboardInterrupt: pass
    finally: app.close()


if __name__ == '__main__':
    main()
