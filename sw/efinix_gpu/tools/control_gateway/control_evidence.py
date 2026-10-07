"""Strict per-phase serial evidence. Never operates a board or infers board performance."""
import argparse
import json
import pathlib
import re


def _newer(candidate, previous):
    return 0 < ((candidate - previous) & 0xffffffff) < 0x80000000


def _phases(text):
    phases = []
    active = None
    for match in re.finditer(r'V3_CHECK_PHASE,name=(\w+),event=(BEGIN|END)', text):
        name, event = match.groups()
        if event == 'BEGIN':
            if active is not None:
                raise ValueError('nested phase markers')
            active = (name, match.end())
        else:
            if active is None or active[0] != name:
                raise ValueError('unpaired phase marker')
            phases.append(dict(name=name, start=active[1], end=match.start()))
            active = None
    if active is not None:
        raise ValueError('incomplete phase')
    return phases


def _perf(line):
    fields = {}
    for part in line.split(',')[1:]:
        name, value = part.split('=', 1)
        if name in fields:
            raise ValueError('duplicate serial field: ' + name)
        fields[name] = int(value, 16 if name == 'keys' else 10)
    if not {'mode', 'tick', 'seq', 'x', 'y', 'keys', 'age'} <= fields.keys():
        raise ValueError('incomplete V3_PERF record')
    for name in ('tick', 'seq'):
        if not -0x80000000 <= fields[name] <= 0xffffffff:
            raise ValueError('invalid modular tick/sequence')
        fields[name] &= 0xffffffff
    if not 8 <= fields['x'] <= 952 or not 80 <= fields['y'] <= 532 or not 0 <= fields['keys'] <= 255:
        raise ValueError('invalid player/key field')
    return fields


def verify_trace(text, phases=None):
    if 'V3_FAIL' in text:
        raise ValueError('candidate reported V3_FAIL')
    if phases is None:
        phases = _phases(text)
    elif not text.isascii():
        raise ValueError('offset sidecar requires the ASCII serial stream')
    if (not isinstance(phases, list) or any(not isinstance(p, dict) for p in phases)
            or [p.get('name') for p in phases] != ['RIGHT', 'UP', 'EXPIRE']):
        raise ValueError('requires ordered RIGHT, UP, EXPIRE evidence phases')
    previous_end = 0
    for phase in phases:
        start, end = phase.get('start'), phase.get('end')
        if type(start) is not int or type(end) is not int or not previous_end <= start < end <= len(text):
            raise ValueError('invalid/overlapping phase offsets')
        previous_end = end
    # Only complete records fully inside a phase qualify. Boundary fragments
    # cannot be attributed to a new key just because Capture read them later.
    matches = list(re.finditer(r'(?:^|(?<=[\r\n]))V3_PERF,[^\r\n]+(?=\r?\n|$)', text))
    result = {}
    for phase in phases:
        rows = [_perf(m.group()) for m in matches if phase['start'] <= m.start() and m.end() <= phase['end']]
        name = phase['name']
        if name == 'EXPIRE':
            if not rows:
                raise ValueError('EXPIRE: no complete samples')
            previous = result['UP']['last']
            expired = []
            for row in rows:
                if row['mode'] != 0 or not _newer(row['tick'], previous['tick']):
                    raise ValueError('EXPIRE: non-LIVE or repeated/backward tick across phases')
                released = row['keys'] == 0 and row['age'] == -1
                if expired and not released:
                    raise ValueError('EXPIRE: keys/connection reasserted after confirmed release')
                if released:
                    # nc_poll clears sequence on disconnection. Its zero is
                    # not an out-of-order connected packet; tick must advance.
                    expired.append(row)
                elif (row['keys'] not in (0, result['UP']['last']['keys'])
                      or not 0 <= row['age'] <= 250
                      or (row['seq'] != previous['seq'] and not _newer(row['seq'], previous['seq']))):
                    raise ValueError('EXPIRE: stale/unexpected keys or backward sequence during lease grace')
                previous = row
            if not expired:
                raise ValueError('EXPIRE: no LIVE zero keys with age=-1')
            result[name] = dict(samples=len(expired), total_samples=len(rows), first=expired[0], last=rows[-1])
            continue
        key = 2 if name == 'RIGHT' else 4
        rows = [r for r in rows if r['mode'] == 0 and r['keys'] == key]
        if len(rows) < 2:
            raise ValueError(name + ': at least two same-direction LIVE samples required')
        if any(not 0 <= r['age'] <= 250 for r in rows):
            raise ValueError(name + ': stale held input')
        if name == 'UP':
            previous = result['RIGHT']['last']
            if not _newer(rows[0]['tick'], previous['tick']) or not _newer(rows[0]['seq'], previous['seq']):
                raise ValueError('UP: repeated/backward tick or sequence across direction phases')
        for previous, current in zip(rows, rows[1:]):
            if not _newer(current['tick'], previous['tick']) or not _newer(current['seq'], previous['seq']):
                raise ValueError(name + ': repeated/backward tick or input sequence')
            dx, dy = current['x'] - previous['x'], current['y'] - previous['y']
            if (name == 'RIGHT' and (dx < 0 or dy != 0)) or (name == 'UP' and (dy > 0 or dx != 0)):
                raise ValueError(name + ': wrong movement direction/axis')
        dx, dy = rows[-1]['x'] - rows[0]['x'], rows[-1]['y'] - rows[0]['y']
        if (name == 'RIGHT' and dx <= 0) or (name == 'UP' and dy >= 0):
            raise ValueError(name + ': no directional movement; RESTART outside this phase does not count')
        result[name] = dict(samples=len(rows), first=rows[0], last=rows[-1], dx=dx, dy=dy)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--phases', help='ASCII offsets emitted by the board-control script')
    parser.add_argument('--out', help='new JSON result; refuses any existing file')
    args = parser.parse_args()
    try:
        if args.out and pathlib.Path(args.out).exists():
            raise FileExistsError('refusing to overwrite control evidence')
        with open(args.serial, encoding='utf-8', newline='') as serial:
            text = serial.read(4 * 1024 * 1024 + 1)
        if len(text) > 4 * 1024 * 1024:
            raise ValueError('control trace exceeds 4 MiB; use short phased evidence, not an endurance stream')
        phases = None if not args.phases else json.loads(pathlib.Path(args.phases).read_text(encoding='utf-8-sig'))
        result = verify_trace(text, phases)
        if args.out:
            with open(args.out, 'x', encoding='utf-8') as output:
                json.dump(result, output, indent=2)
                output.write('\n')
    except (OSError, ValueError) as error:
        print('FAIL control trace: ' + str(error))
        return 1
    print(json.dumps(result, indent=2))
    print('PASS per-phase movement/release evidence; not board FPS or latency qualification')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
