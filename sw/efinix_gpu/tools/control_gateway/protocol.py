"""Fixed V3 network-byte-order AGC1 / AGT1 contract (standard library only)."""
from dataclasses import dataclass
import struct
import zlib

HELLO, KEYS, ACK, GAME, GAME_ACK, TELEMETRY = 1, 2, 3, 4, 5, 0x80
GAME_START, GAME_MENU = 1, 2
STATUS_ALLOWED = 0x007f0fff
FIELDS = (
    'firmware_build_id', 'resource_epoch', 'simulation_tick', 'requested_sprites',
    'visible_sprites', 'gpu_full_frame_fps_x100', 'cpu_full_frame_fps_x100',
    'pre_present_us', 'gpu_busy_us', 'command_build_us', 'submit_blocked_us',
    'background_copy_us', 'render_read_bytes', 'render_write_bytes',
    'texture_cache_bytes', 'scanout_underflow_delta', 'gpu_error_delta',
    'missed_vblank_delta', 'asset_retry_delta', 'control_drop_delta', 'input_age_ms',
    'status_flags', 'p95_work_us', 'present_wait_us', 'alpha_commands',
    'alpha_pixels', 'key_commands')
VALID_BITS = {5: 16, 6: 17, 7: 16, 8: 16, 9: 18, 10: 18, 11: 18,
              12: 19, 13: 19, 14: 19, 15: 20, 16: 20, 17: 20,
              18: 21, 19: 21, 20: 21, 22: 16, 23: 16, 24: 22, 25: 22, 26: 22}


@dataclass(frozen=True)
class Packet:
    kind: int
    session: int
    sequence: int
    words: tuple


def newer(candidate, previous):
    return 0 < ((candidate - previous) & 0xffffffff) < 0x80000000


def _validate(kind, session, words):
    if kind == TELEMETRY:
        if len(words) != 27 or words[21] & ~STATUS_ALLOWED:
            raise ValueError('telemetry fields/reserved status flags')
    elif kind not in (HELLO, KEYS, ACK, GAME, GAME_ACK) or len(words) != 3 or session == 0:
        raise ValueError('control type/length/session')
    elif kind == HELLO and any(words):
        raise ValueError('HELLO reserved words')
    elif kind == KEYS and (words[0] & ~255 or words[2]):
        raise ValueError('KEYS reserved bits')
    elif kind == ACK and tuple(words) != (1, 0, 0):
        raise ValueError('ACK must accept HELLO')
    elif kind == GAME and (not words[2] or not (
            words[0] == GAME_START and 1 <= words[1] <= 4 or
            words[0] == GAME_MENU and words[1] == 0)):
        raise ValueError('GAME opcode/level/request')
    elif kind == GAME_ACK and (not words[0] or words[1] > 2):
        raise ValueError('GAME_ACK request/result')


def encode(kind, session, sequence, words):
    words = tuple(words)
    if any(type(v) is not int or not 0 <= v <= 0xffffffff for v in (session, sequence, *words)):
        raise ValueError('u32 range')
    _validate(kind, session, words)
    size = 128 if kind == TELEMETRY else 32
    body = struct.pack('>4sBBHII', b'AGT1' if size == 128 else b'AGC1', 1, kind,
                       size, session, sequence) + struct.pack('>' + 'I' * len(words), *words)
    return body + struct.pack('>I', zlib.crc32(body))


def decode(data):
    if len(data) not in (32, 128):
        raise ValueError('packet length')
    magic, version, kind, length, session, sequence = struct.unpack_from('>4sBBHII', data)
    if version != 1 or length != len(data) or magic != (b'AGT1' if len(data) == 128 else b'AGC1'):
        raise ValueError('header')
    if (kind == TELEMETRY) != (len(data) == 128):
        raise ValueError('type length')
    if zlib.crc32(data[:-4]) != struct.unpack_from('>I', data, len(data) - 4)[0]:
        raise ValueError('CRC32')
    words = struct.unpack_from('>' + 'I' * ((len(data) - 20) // 4), data, 16)
    _validate(kind, session, words)
    return Packet(kind, session, sequence, words)


def display_words(words):
    flags = words[21]
    return {name: (value if i not in VALID_BITS or flags & (1 << VALID_BITS[i]) else None)
            for i, (name, value) in enumerate(zip(FIELDS, words))}
