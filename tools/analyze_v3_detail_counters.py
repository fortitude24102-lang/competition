"""Decode ordinary 960x540 DetailProbe endpoints with the HUD72 background Copy."""
import argparse
import json
from pathlib import Path

COUNTERS = ('cycles', 'pixels', 'read', 'write', 'stalls', 'cache', 'render_grants', 'scanout_grants')

def analyze(text):
    starts, summaries, stops, endpoints, order = [], [], [], {}, []
    for line in text.splitlines():
        if not line.startswith(('V3_PROBE_START,', 'V3_PROBE,', 'V3_COUNTERS,', 'V3_PROBE_STOP,')):
            continue
        parts = [part.split('=', 1) for part in line.split(',')[1:]]
        values = dict(parts)
        if len(values) != len(parts):
            raise ValueError('Duplicate field in diagnostic record')
        if line.startswith('V3_PROBE_START,'):
            starts.append(values)
            order.append('start')
        elif line.startswith('V3_PROBE,'):
            summaries.append(values)
            order.append('summary')
        elif line.startswith('V3_PROBE_STOP,'):
            stops.append(values)
            order.append('stop')
        else:
            phase = values['phase']
            if phase not in ('begin', 'end') or phase in endpoints:
                raise ValueError('Missing or duplicate counter endpoint')
            decoded = {}
            for name in COUNTERS:
                low, high = int(values[name + '_lo'], 16), int(values[name + '_hi'], 16)
                if not (0 <= low <= 0xffffffff and 0 <= high <= 0xffffffff):
                    raise ValueError('Counter half exceeds32 bits')
                decoded[name] = (high << 32) | low
            endpoints[phase] = decoded
            order.append(phase)
    if (len(starts) != 1 or len(summaries) != 1 or len(stops) != 1 or
            set(stops[0]) != {'result'} or int(stops[0]['result']) != 0 or
            order != ['begin', 'start', 'end', 'summary', 'stop']):
        raise ValueError('Expected one complete diagnostic capture')
    samples, warm = int(starts[0]['samples']), int(starts[0]['warm'])
    if samples <= 0 or warm != 30 or int(summaries[0]['frames']) != samples:
        raise ValueError('Probe sample count mismatch')
    delta = {name: endpoints['end'][name] - endpoints['begin'][name] for name in COUNTERS}
    if any(value < 0 for value in delta.values()):
        raise ValueError('Counters reset or captures were mixed')
    frames = samples + warm
    background_bytes = 960 * (540 - 72) * 2 * frames
    if delta['read'] < background_bytes or delta['write'] < background_bytes:
        raise ValueError('Counter traffic is below the required background Copy payload')
    return dict(counter_scope='GPU interface delivered read bytes and enabled write-strobe bytes; not DDR PHY traffic',
                counter_frames_including_warmup=frames, scored_frames=samples, core_hz=100_000_000,
                counters=delta, gpu_busy_us_per_counter_frame=delta['cycles'] / frames / 100,
                gpu_read_bytes_per_counter_frame=delta['read'] / frames,
                gpu_write_strobe_bytes_per_counter_frame=delta['write'] / frames,
                gpu_cache_bytes_per_counter_frame=delta['cache'] / frames,
                gpu_stalled_cycles_per_counter_frame=delta['stalls'] / frames,
                note='GPU active time overlaps CPU work; channel waits and phases must not be added blindly')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(args.capture.read_text(encoding='utf-8-sig')), indent=2))
