"""Archive generated offline evidence; never modify board/release artifacts."""
import gzip
import hashlib
import json
import pathlib
import shutil
import re


def parse_render(text):
    host = re.search(r'PASS bullet pixels: .*representative visible=(\d+) commands=(\d+) pixels=(\d+) CRC=([0-9a-f]{8})', text)
    rtl = re.search(r'PASS bullet RTL: (\d+) pixels COPY=(\d+) KEY=(\d+) ALPHA=(\d+) FILL=(\d+) stalls=(\d+)', text)
    previews = re.findall(r'PASS preview512: tick=(\d+) visible=(\d+) commands=(\d+) CRC=([0-9a-f]{8})', text)
    if not host or not rtl or host[3] != rtl[1] or [int(p[0]) for p in previews] != [0, 90, 180]:
        raise ValueError('missing or inconsistent successful host/RTL/512 preview evidence')
    return {'frame_crc32': host[4], 'rtl_pixel_operations': int(rtl[1]),
            'representative_visible_bullets': int(host[1]),
            'representative_scene_commands': int(host[2]),
            'rtl_operations': dict(zip(('COPY', 'KEY', 'ALPHA', 'FILL', 'stalls'), map(int, rtl.groups()[1:]))),
            'previews_512': [dict(tick=int(t), visible=int(v), commands=int(c), crc32=crc)
                             for t, v, c, crc in previews]}


def collect():
    source = pathlib.Path("generated/verification/bullet-demo")
    target = pathlib.Path("docs/efinix_2d_gpu/evidence/bullet-demo-r4")
    metrics = parse_render((source / 'final-render.log').read_text(encoding='utf-8-sig'))
    target.mkdir(parents=True, exist_ok=True)
    for name in ("preview.png", "preview512_000.png", "preview512_090.png", "preview512_180.png", "final-render.log", "final-regression.log",
                 "final-firmware-bullet.log", "final-firmware-legacy.log"):
        shutil.copyfile(source / name, target / name)
    (target / "bullet_pixels.vcd.gz").write_bytes(gzip.compress(
        (source / "bullet_pixels.vcd").read_bytes(), mtime=0))
    hashes = {}
    for path in sorted(target.iterdir()):
        if path.name != "manifest.json":
            hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    for mode in ("bullet", "legacy"):
        for extension in ("elf", "bin", "hex"):
            path = source / f"firmware-{mode}" / f"gpu_demo.{extension}"
            hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    manifest = {"scope": "offline host and pixel-pipe RTL only, not board performance",
                "hardware_base": "a82f3dd", **metrics,
                "native_tests_are_sanitized": False, "sha256": hashes}
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print("Archived bullet-demo preview, compressed waveform, logs and hashes")


if __name__ == "__main__":
    collect()
