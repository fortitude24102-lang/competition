"""SIMULATED protocol ACK/echo peer. No game logic or performance measurement."""
import argparse
import socket
import threading
import time
import protocol as p


class FakeBoard:
    def __init__(self, bind=('127.0.0.1', 8091), gateway=('127.0.0.1', 8090), game_menu=False, performance=False):
        self.gateway = (socket.gethostbyname(gateway[0]), gateway[1])
        self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp.bind(bind); self.udp.settimeout(.01)
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.thread = None
        self.session = self.sequence = self.hello_sequence = self.keys = self.action = 0
        self.last_input = 0.0
        self.retired = []
        self.drops = self.snapshot = 0
        self.game_menu=game_menu;self.menu=True;self.count=0;self.last_game=None
        self.performance_capable=performance;self.performance=False

    def _expire(self, now):
        if self.session and now - self.last_input >= .25:
            self.retired.append(self.session); self.retired = self.retired[-4:]
            self.session = self.keys = self.action = 0

    def telemetry_words(self):
        with self.lock:
            words = [0] * 27
            words[0] = 0x53494d31  # "SIM1", never a firmware performance result.
            words[2] = self.sequence  # Explicit input sequence echo, no simulated game tick.
            words[19] = self.drops & 0xffffffff
            words[20] = 0xffffffff if not self.session else min(0xffffffff, int((time.monotonic() - self.last_input) * 1000))
            words[21] = (1 << 21) | ((1 << 4) if self.session else 0)
            if self.game_menu:
                words[3]=self.count if not self.menu else 0
                words[21]|=(1<<11)|(1<<14)|((1<<10)|(1<<8) if self.menu else 1)
                if self.performance_capable: words[21]|=1<<12
                if self.performance: words[21]|=1<<13
            return tuple(words)

    def start(self):
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        next_snapshot = 0.0
        while not self.stop.is_set():
            now = time.monotonic()
            with self.lock: self._expire(now)
            try:
                data, sender = self.udp.recvfrom(2048)
                if sender != self.gateway: raise ValueError('fixed peer only')
                packet = p.decode(data)
                ack = None
                with self.lock:
                    now = time.monotonic(); self._expire(now)
                    if packet.kind == p.HELLO and packet.session not in self.retired:
                        if not self.session:
                            self.session, self.sequence, self.hello_sequence = packet.session, packet.sequence, packet.sequence
                            self.keys = self.action = 0; self.last_input = now
                            self.last_game=None
                            ack = p.encode(p.ACK, self.session, self.hello_sequence, [1, 0, 0])
                        elif packet.session == self.session and packet.sequence == self.hello_sequence:
                            ack = p.encode(p.ACK, self.session, self.hello_sequence, [1, 0, 0])
                        else: self.drops += 1
                    elif packet.kind == p.KEYS and self.session and packet.session == self.session and p.newer(packet.sequence, self.sequence):
                        self.sequence = packet.sequence
                        self.keys, self.action = packet.words[:2]
                        self.last_input = now
                    elif (packet.kind==p.GAME and self.game_menu and self.session and
                          packet.session==self.session and p.newer(packet.sequence,self.sequence)):
                        op,level,request=packet.words
                        previous=self.last_game
                        if previous and request==previous[0] and (op,level)!=previous[1:3]: self.drops+=1
                        elif previous and request!=previous[0] and not p.newer(request,previous[0]): self.drops+=1
                        else:
                            self.sequence=packet.sequence;self.keys=0;self.last_input=now
                            if not previous or request!=previous[0]:
                                result=2 if op==p.GAME_PERFORMANCE and not self.performance_capable else (
                                    1 if op in (p.GAME_START,p.GAME_PERFORMANCE) and not self.menu else 0)
                                if not result:
                                    self.menu=op==p.GAME_MENU
                                    self.count=p.LEVEL_COUNTS[level-1] if op==p.GAME_START else 0
                                    self.performance=op==p.GAME_PERFORMANCE
                                    if self.performance:self.count=64
                                self.last_game=(request,op,level,result,self.snapshot)
                            ack=p.encode(p.GAME_ACK,self.session,packet.sequence,
                                [request,self.last_game[3],self.last_game[4]])
                    else: self.drops += 1
                if ack: self.udp.sendto(ack, self.gateway)
            except socket.timeout:
                pass
            except (ValueError, OSError):
                with self.lock: self.drops += 1
            now = time.monotonic()
            if now >= next_snapshot:
                words = self.telemetry_words()
                with self.lock:
                    self.snapshot = (self.snapshot + 1) & 0xffffffff
                    snapshot, session = self.snapshot, self.session
                try: self.udp.sendto(p.encode(p.TELEMETRY, session, snapshot, words), self.gateway)
                except OSError: pass
                if session and self.performance:
                    # Protocol-only fixture: never invent a measured FPS or a verified best.
                    with self.lock:self.snapshot=(self.snapshot+1)&0xffffffff;snapshot=self.snapshot
                    try:self.udp.sendto(p.encode(p.PERFORMANCE,session,snapshot,[64,0,1]),self.gateway)
                    except OSError:pass
                next_snapshot = now + .2

    def close(self):
        self.stop.set()
        if self.thread: self.thread.join(timeout=1)
        self.udp.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8091)
    parser.add_argument('--gateway', default='127.0.0.1')
    parser.add_argument('--gateway-port', type=int, default=8090)
    parser.add_argument('--game-menu',action='store_true',help='simulate only menu protocol, never gameplay or FPS')
    parser.add_argument('--performance',action='store_true',help='protocol-only WARM status; zero FPS and zero best')
    args = parser.parse_args()
    board = FakeBoard((args.bind, args.port), (args.gateway, args.gateway_port),args.game_menu,args.performance)
    print('SIMULATED ACK/ECHO PEER — NO BOARD PERFORMANCE / NO GAME LOGIC', flush=True)
    print('Listening %s:%s; fixed gateway %s:%s' % (*board.udp.getsockname(), *board.gateway), flush=True)
    board.start()
    try:
        while not board.stop.wait(.5): pass
    except KeyboardInterrupt: pass
    finally: board.close()


if __name__ == '__main__':
    main()
