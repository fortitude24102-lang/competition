import importlib.util
from pathlib import Path
import unittest

source = Path(__file__).resolve().parents[3] / 'tools/analyze_v3_detail_counters.py'
spec = importlib.util.spec_from_file_location('detail_counters', source)
detail = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detail)

def capture(empty_traffic=False):
    initial = 0x1fffffff0
    def endpoint(phase, multiplier):
        fields = ['V3_COUNTERS', 'phase=' + phase]
        for name in detail.COUNTERS:
            increment = 126000000 if name == 'cycles' else 630000000 if name in ('read', 'write') else 2520
            if empty_traffic and name in ('read', 'write'):
                increment = 0
            value = initial + multiplier * increment
            fields += [f'{name}_lo={value & 0xffffffff:x}', f'{name}_hi={value >> 32:x}']
        return ','.join(fields)
    return '\n'.join([endpoint('begin', 0), 'V3_PROBE_START,warm=30,samples=600,log_windows=1',
                      endpoint('end', 1), 'V3_PROBE,target=1024,frames=600', 'V3_PROBE_STOP,result=0'])

class DetailCountersTest(unittest.TestCase):
    def test_64bit_endpoints_and_warm_frames_are_included(self):
        result = detail.analyze(capture())
        self.assertEqual(result['counters']['cycles'], 126000000)
        self.assertEqual(result['counter_frames_including_warmup'], 630)
        self.assertEqual(result['scored_frames'], 600)
        self.assertEqual(result['gpu_busy_us_per_counter_frame'], 2000)
        self.assertEqual(result['gpu_read_bytes_per_counter_frame'], 1000000)

    def test_rejects_zero_traffic_instead_of_treating_invalid_counters_as_real(self):
        with self.assertRaisesRegex(ValueError, 'background Copy'):
            detail.analyze(capture(empty_traffic=True))

    def test_rejects_duplicate_or_missing_endpoints_and_short_capture(self):
        text = capture()
        for bad in (text + '\n' + text.splitlines()[0], text.replace('phase=end', 'phase=unknown'),
                    text.replace('frames=600', 'frames=599'), text.replace('V3_PROBE_STOP,result=0', '')):
            with self.assertRaises(ValueError):
                detail.analyze(bad)

    def test_rejects_counter_halves_larger_than32_bits(self):
        with self.assertRaises(ValueError):
            detail.analyze(capture().replace('cycles_lo=fffffff0', 'cycles_lo=1fffffff0'))

    def test_rejects_failed_duplicate_or_reversed_completion(self):
        text = capture()
        for bad in (text.replace('result=0', 'result=01'), text + '\nV3_PROBE_STOP,result=1',
                    '\n'.join(reversed(text.splitlines()))):
            with self.assertRaises(ValueError):
                detail.analyze(bad)

    def test_rejects_warmup_from_a_different_firmware_contract(self):
        with self.assertRaises(ValueError):
            detail.analyze(capture().replace('warm=30', 'warm=0'))

if __name__ == '__main__':
    unittest.main()
