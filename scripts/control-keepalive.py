"""Collector-only heartbeat. Board/gateway leases and qualification stay unchanged."""
import json
import sys
import threading
import time
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener


def run():
    config = json.loads(sys.stdin.readline())
    url = config['url'].rstrip('/')
    parsed = urlsplit(url)
    if (parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or not parsed.port
            or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment):
        raise ValueError('Only a loopback HTTP gateway is supported')
    body = config['body']
    if (set(body) != {'token', 'client', 'keys', 'action_sequence', 'release'}
            or not isinstance(body['token'], str) or not body['token']
            or not isinstance(body['client'], str) or not body['client']
            or body['keys'] != 0 or body['release'] is not False
            or type(body['action_sequence']) is not int or not 0 <= body['action_sequence'] <= 0xffffffff):
        raise ValueError('Only the existing neutral control owner may be kept alive')
    stopped = threading.Event()

    def stop_on_eof():
        sys.stdin.read()
        stopped.set()

    threading.Thread(target=stop_on_eof, daemon=True).start()
    request = Request(url + '/api/control', data=json.dumps(body).encode(),
                      headers={'Content-Type': 'application/json', 'Origin': url}, method='POST')
    opener = build_opener(ProxyHandler({}))
    while not stopped.is_set():
        # HTTP failure aborts; the parent also rejects any changed control session.
        started = time.monotonic()
        with opener.open(request, timeout=.20) as response:
            response.read()
        elapsed = time.monotonic() - started
        if elapsed >= .23:  # Keep margin inside the unchanged 250 ms gateway/board lease.
            raise TimeoutError('Heartbeat renewal budget exceeded')
        stopped.wait(max(0, .07-elapsed))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(run())
    except Exception as error:
        print('KEEPALIVE_FAIL,' + type(error).__name__, file=sys.stderr)
        sys.exit(1)
