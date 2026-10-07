"""Read-only local gateway capture. Evidence collection is NOT board qualification."""
import argparse
from contextlib import ExitStack
import csv
from datetime import datetime, timezone
import json
import math
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

import protocol as p


def validate_url(url):
    parts = urllib.parse.urlsplit(url)
    if (parts.scheme != 'http' or parts.hostname != '127.0.0.1' or parts.username
            or parts.password or parts.path not in ('', '/') or parts.query or parts.fragment):
        raise ValueError('HTTP must point only to the local 127.0.0.1 gateway root')
    port = parts.port or 80
    if not 1 <= port <= 65535:
        raise ValueError('invalid HTTP port')
    return 'http://127.0.0.1:' + str(port)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def read_status(url):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(validate_url(url) + '/api/status', headers={'Accept': 'application/json'})
    with opener.open(request, timeout=.5) as response:
        raw = response.read(65537)
    if len(raw) > 65536:
        raise ValueError('status response exceeds 64 KiB')
    return json.loads(raw)


def _u32(value):
    return type(value) is int and 0 <= value <= 0xffffffff


def _packet(view):
    if (not isinstance(view, dict) or type(view.get('simulated')) is not bool
            or type(view.get('stale')) is not bool):
        raise ValueError('invalid gateway status/simulation label')
    age = view.get('age_ms')
    if age is not None and (type(age) is not int or age < 0):
        raise ValueError('invalid snapshot age')
    packet = view.get('telemetry')
    if packet is None:
        if age is not None:
            raise ValueError('snapshot age without telemetry')
        return None
    if (not isinstance(packet, dict) or age is None or not _u32(packet.get('session'))
            or not _u32(packet.get('sequence')) or not isinstance(packet.get('words'), list)
            or len(packet['words']) != 27 or not all(_u32(w) for w in packet['words'])
            or packet['words'][21] & ~p.STATUS_ALLOWED):
        raise ValueError('invalid complete 27-word snapshot')
    return packet


class CaptureLog:
    """Stream files while keeping only counters and one immutable snapshot in RAM."""
    def __init__(self, prefix):
        self.paths = [pathlib.Path(str(prefix) + suffix) for suffix in ('.csv', '.jsonl', '.summary.json')]
        self.last = None
        self.stack = ExitStack()
        self.metadata = {}
        self.stats = dict(polls=0, status_records=0, snapshots=0, stale_polls=0, errors=0,
                          simulated_polls=0, observed_sequence_gaps=0, sequence_discontinuities=0,
                          invalid_error_group_snapshots=0, nonzero_underflow_windows=0,
                          nonzero_gpu_error_windows=0, nonzero_missed_windows=0, maximum_snapshot_age_ms=0)

    def __enter__(self):
        for path in self.paths:
            if path.exists():
                raise FileExistsError('refusing to overwrite evidence: ' + str(path))
        self.paths[0].parent.mkdir(parents=True, exist_ok=True)
        try:
            self.files = [self.stack.enter_context(path.open('x', encoding='utf-8', newline='')) for path in self.paths]
        except BaseException:
            self.stack.close()
            raise
        self.csv = csv.writer(self.files[0])
        self.csv.writerow(['elapsed_ms', 'received_utc', 'simulated', 'snapshot_age_ms', 'session', 'snapshot_id', *p.FIELDS])
        self.files[0].flush()
        return self

    def _event(self, event):
        self.files[1].write(json.dumps(event, ensure_ascii=False, separators=(',', ':')) + '\n')
        self.files[1].flush()

    def add(self, view, elapsed_ms, received_utc):
        packet = _packet(view)
        current = None if packet is None else (packet['session'], packet['sequence'], tuple(packet['words']))
        if (current is not None and self.last is not None and current[:2] == self.last[:2]
                and current[2][0] == self.last[2][0] and current[2] != self.last[2]):
            raise ValueError('same snapshot identity with changed words')
        self._event(dict(kind='status', elapsed_ms=elapsed_ms, received_utc=received_utc, status=view))
        self.stats['polls'] += 1
        self.stats['status_records'] += 1
        self.stats['simulated_polls'] += int(view['simulated'])
        self.stats['stale_polls'] += int(view['stale'] or packet is None or view['age_ms'] >= 500)
        if packet is None:
            return
        self.stats['maximum_snapshot_age_ms'] = max(self.stats['maximum_snapshot_age_ms'], view['age_ms'])
        if current == self.last:
            return
        if self.last is not None:
            delta = (current[1] - self.last[1]) & 0xffffffff
            if current[2][0] != self.last[2][0] or not 0 < delta < 0x80000000:
                self.stats['sequence_discontinuities'] += 1
            else:
                self.stats['observed_sequence_gaps'] += delta - 1
        self.last = current
        self.csv.writerow([elapsed_ms, received_utc, int(view['simulated']), view['age_ms'],
                           packet['session'], packet['sequence'], *packet['words']])
        self.files[0].flush()
        self.stats['snapshots'] += 1
        if not packet['words'][21] & (1 << 20):
            self.stats['invalid_error_group_snapshots'] += 1
        else:
            for index, name in ((15, 'nonzero_underflow_windows'), (16, 'nonzero_gpu_error_windows'),
                                (17, 'nonzero_missed_windows')):
                self.stats[name] += int(packet['words'][index] != 0)

    def error(self, reason, elapsed_ms, received_utc):
        self._event(dict(kind='error', elapsed_ms=elapsed_ms, received_utc=received_utc, error=str(reason)[:200]))
        self.stats['polls'] += 1
        self.stats['errors'] += 1

    def __exit__(self, error_type, error, traceback):
        try:
            summary = dict(self.stats, **self.metadata, qualification='capture_only_not_board_acceptance',
                           aborted=error_type is not None)
            json.dump(summary, self.files[2], indent=2)
            self.files[2].write('\n')
        finally:
            self.stack.close()


def collect(url, prefix, duration=1800, interval=.2):
    url = validate_url(url)
    if (isinstance(duration, bool) or isinstance(interval, bool) or not math.isfinite(duration)
            or not math.isfinite(interval) or not 0 < duration <= 86400 or not .1 <= interval <= 5):
        raise ValueError('duration must be >0..86400s; interval 0.1..5s')
    start = time.monotonic()
    with CaptureLog(prefix) as log:
        log.metadata = dict(url=url, requested_seconds=duration, interval_seconds=interval)
        while time.monotonic() - start < duration:
            try:
                view = read_status(url)
                log.add(view, round((time.monotonic() - start) * 1000), datetime.now(timezone.utc).isoformat())
            except (OSError, ValueError, urllib.error.URLError) as error:
                log.error(type(error).__name__ + ': ' + str(error),
                          round((time.monotonic() - start) * 1000), datetime.now(timezone.utc).isoformat())
            remaining = duration - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(min(interval, remaining))
        log.metadata['elapsed_ms'] = round((time.monotonic() - start) * 1000)
        return dict(log.stats, **log.metadata, qualification='capture_only_not_board_acceptance')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:8765')
    parser.add_argument('--out', required=True, help='new evidence prefix; never overwrites any of its three files')
    parser.add_argument('--seconds', type=float, default=1800)
    parser.add_argument('--interval', type=float, default=.2)
    args = parser.parse_args()
    try:
        result = collect(args.url, args.out, args.seconds, args.interval)
    except KeyboardInterrupt:
        print('Capture interrupted; partial evidence retained, not qualification.')
        return 130
    except (OSError, ValueError) as error:
        print('Capture failed: ' + str(error))
        return 2
    print(json.dumps(result, indent=2))
    return 1 if result['errors'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
