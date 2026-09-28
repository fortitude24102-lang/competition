# Original 2D bullet-demo assets

These procedural RGB565 shapes/grid are independently authored for this project.
No 100KBBH models, shaders, fonts, textures or source code are redistributed.
100KBBH (https://github.com/EterDelta/100KBBH, MIT) is a gameplay/visual reference,
not the runtime engine. This candidate is not an exact visual port.

Generate from repository root: `python tools/build_bullet_assets.py`.
The generator uses only Python's standard library. Do not replace assets/v2/.

| ID | File | Bytes | DDR destination |
|---|---|---:|---|
| 101 | background.rgb565 | 1,036,800 | 0x02900000 |
| 102 | atlas.rgb565 | 1,184 | 0x02a00000 |

Atlas: three 8x8 RGB565 ColorKey sprites (offsets 0/128/256), one 16x16
player marker (offset 384), one 12x12 global-alpha emitter tile (offset 896).
ColorKey is 0xf81f. Files are little-endian; CRCs are generated in
bullet_asset_catalog.h and checked by the existing RISC-V resource client.
Local fallback is generated separately at 0x02b00000/0x02c00000, so late network
DMA writes cannot corrupt it even when abort cleanup times out.

Run the existing Windows resource server with this directory's manifest.csv
for bullet firmware, or assets/v2/manifest.csv for legacy firmware. Mismatched
manifests lead to bounded failure and explicitly labeled local fallback, not
a successful Ethernet acceptance result.
