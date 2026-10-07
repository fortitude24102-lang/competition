"""A restart/global coordinate change must not masquerade as RIGHT/UP movement."""
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
TOOL = pathlib.Path(__file__).resolve().parents[1] / 'tools/control_gateway/control_evidence.py'
spec = importlib.util.spec_from_file_location('control_evidence', TOOL)
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


def perf(tick, seq, x, y, keys, age=0, mode=0):
    return f'V3_PERF,mode={mode},tick={tick},seq={seq},x={x},y={y},visible=60,fps_x10=601,keys={keys:08x},age={age}\r\n'


def trace(right=None, up=None, expire=None):
    # Restart itself changes x/y BEFORE tested phases; it earns no movement evidence.
    text = perf(1, 5, 100, 100, 64) + perf(2, 6, 480, 480, 64)
    blocks = dict(RIGHT=right or [perf(30, 10, 500, 480, 2), perf(60, 20, 620, 480, 2)],
                  UP=up or [perf(90, 30, 620, 440, 4), perf(120, 40, 620, 320, 4)],
                  EXPIRE=expire or [perf(150, 0, 620, 320, 0, -1)])
    for name, lines in blocks.items():
        text += f'V3_CHECK_PHASE,name={name},event=BEGIN\r\n'
        text += ''.join(lines)
        text += f'V3_CHECK_PHASE,name={name},event=END\r\n'
    return text


class ControlEvidenceTest(unittest.TestCase):
    def test_actual_direction_and_release(self):
        result = evidence.verify_trace(trace())
        self.assertEqual(result['RIGHT']['dx'], 120)
        self.assertEqual(result['UP']['dy'], -120)
        self.assertEqual(result['EXPIRE']['samples'], 1)

    def test_restart_only_movement_is_not_a_pass(self):
        text = trace(right=[perf(30, 10, 480, 480, 2), perf(60, 20, 480, 480, 2)],
                     up=[perf(90, 30, 480, 480, 4), perf(120, 40, 480, 480, 4)])
        with self.assertRaises(ValueError):
            evidence.verify_trace(text)

    def test_wrong_direction_and_wrong_axis_rejected(self):
        for last in (perf(60, 20, 480, 480, 2), perf(60, 20, 620, 470, 2)):
            with self.assertRaises(ValueError):
                evidence.verify_trace(trace(right=[perf(30, 10, 500, 480, 2), last]))

    def test_repeated_or_backward_tick_and_sequence_rejected(self):
        for tick, seq in ((30, 20), (29, 20), (60, 10), (60, 9)):
            with self.assertRaises(ValueError):
                evidence.verify_trace(trace(right=[perf(30, 10, 500, 480, 2), perf(tick, seq, 620, 480, 2)]))

    def test_wrap_is_newer_and_unsigned_signed_serial_are_supported(self):
        text = trace(right=[perf(-2, -2, 500, 480, 2), perf(0, 0, 620, 480, 2)])
        self.assertEqual(evidence.verify_trace(text)['RIGHT']['dx'], 120)

    def test_stale_keys_replay_mode_or_one_sample_not_direction_evidence(self):
        for lines in ([perf(30, 10, 500, 480, 2)],
                      [perf(30, 10, 500, 480, 2, 251), perf(60, 20, 620, 480, 2, 251)],
                      [perf(30, 10, 500, 480, 2, mode=1), perf(60, 20, 620, 480, 2, mode=1)]):
            with self.assertRaises(ValueError):
                evidence.verify_trace(trace(right=lines))

    def test_missing_phase_or_missing_expiry_or_v3_failure_rejected(self):
        for text in (trace().replace('name=UP', 'name=OTHER'), trace(expire=[perf(150, 40, 620, 320, 0, 10)]),
                     trace() + 'V3_FAIL,result=-2\n'):
            with self.assertRaises(ValueError):
                evidence.verify_trace(text)

    def test_sidecar_offsets_preserve_crlf_and_cli_never_overwrites(self):
        text = ''.join([perf(30, 10, 500, 480, 2), perf(60, 20, 620, 480, 2),
                        perf(90, 30, 620, 440, 4), perf(120, 40, 620, 320, 4), perf(150, 0, 620, 320, 0, -1)])
        lengths = [len(perf(30, 10, 500, 480, 2) + perf(60, 20, 620, 480, 2)),
                   len(perf(90, 30, 620, 440, 4) + perf(120, 40, 620, 320, 4))]
        phases = [dict(name='RIGHT', start=0, end=lengths[0]),
                  dict(name='UP', start=lengths[0], end=sum(lengths)),
                  dict(name='EXPIRE', start=sum(lengths), end=len(text))]
        self.assertEqual(evidence.verify_trace(text, phases)['UP']['dy'], -120)
        with tempfile.TemporaryDirectory() as directory:
            serial = pathlib.Path(directory) / 'serial.log'
            phase_file = pathlib.Path(directory) / 'phases.json'
            out = pathlib.Path(directory) / 'check.json'
            serial.write_bytes(text.encode('ascii'))
            phase_file.write_text(json.dumps(phases))
            args = [sys.executable, str(TOOL), '--serial', str(serial), '--phases', str(phase_file), '--out', str(out)]
            result = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(out.read_text())['UP']['dy'], -120)
            original = out.read_bytes()
            result = subprocess.run(args, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(out.read_bytes(), original)

    def test_bad_or_overlapping_offsets_and_duplicate_fields_rejected(self):
        for phases in ([dict(name='RIGHT', start=-1, end=10)],
                       [dict(name='RIGHT', start=0, end=100), dict(name='UP', start=90, end=120)],
                       [dict(name='RIGHT', start=False, end=10)]):
            with self.assertRaises(ValueError):
                evidence.verify_trace(trace(), phases)
        with self.assertRaises(ValueError):
            evidence.verify_trace(trace().replace('keys=00000002', 'keys=00000002,keys=00000004'))

    def test_extra_non_object_phase_is_rejected_cleanly(self):
        text = trace()
        phases = evidence._phases(text)
        phases.insert(1, None)
        with self.assertRaises(ValueError):
            evidence.verify_trace(text, phases)

    def test_release_cannot_hide_subsequent_reasserted_keys(self):
        with self.assertRaises(ValueError):
            evidence.verify_trace(trace(expire=[perf(150, 0, 620, 320, 0, -1),
                                                 perf(180, 41, 620, 200, 4)]))

    def test_old_expiry_cannot_follow_newer_up_phase(self):
        with self.assertRaises(ValueError):
            evidence.verify_trace(trace(expire=[perf(1, 0, 620, 320, 0, -1)]))

    def test_grace_then_continuous_release_accepts_driver_sequence_reset(self):
        result = evidence.verify_trace(trace(expire=[perf(130, 41, 620, 280, 4, 200),
                                                     perf(150, 0, 620, 280, 0, -1),
                                                     perf(180, 0, 620, 280, 0, -1)]))
        self.assertEqual(result['EXPIRE']['samples'], 2)
        self.assertEqual(result['EXPIRE']['last']['tick'], 180)

    def test_release_rejects_stale_grace_or_backward_input_sequence(self):
        for row in (perf(130, 41, 620, 280, 4, 251), perf(130, 39, 620, 280, 4, 20)):
            with self.assertRaises(ValueError):
                evidence.verify_trace(trace(expire=[row, perf(150, 0, 620, 280, 0, -1)]))

    def test_direction_phase_chronology_cannot_restart(self):
        with self.assertRaises(ValueError):
            evidence.verify_trace(trace(up=[perf(1, 30, 620, 440, 4), perf(2, 40, 620, 320, 4)]))


if __name__ == '__main__':
    unittest.main(verbosity=2)
