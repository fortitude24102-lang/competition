# Final row-handoff optimization — short qualification

User requested this be the final optimization round, adopt only measured benefit, and skip long endurance. Adopted independently implemented final-W/next-row and final-output/next-start handoffs; no further optimization search is authorized by this result.

| Same720-frame ordinary1024 workload | Mean work µs | Maximum µs | Deadline/late/underflow/error |
|---|---:|---:|---|
| A1 accepted hardware |8703|13607|0/0/0/0|
| B1 candidate |8656|12063|0/0/0/0|
| A2 accepted hardware |8702|10772|0/0/0/0|
| B2 candidate |8657|12122|0/0/0/0|

Repeated means8702.5→8656.5µs,0.529% lower. All cohorts visible1006..1016,Alpha130..131,FPS60.1,identical neutral replay seal600/256/9836/`a7bd652f`. Same short probe firmware on both BITs. This proves a small short-window improvement, not long-term endurance or a global hardware limit.

Selected BIT `D:/efinity_builds/key_row_handoff_20261026_r1/outflow/efinix_2d_gpu.bit`, SHA256 `c9c55d8a022e9fa226aa6168185743af67c1a83470bc7f1709c89bbd1f09e94f`; control BIT SHA256 `a98148a59541161874a5f8685c5338b3742b6e553c4ba2d3718f3d25a7c98436`. Generated source SHA256 `c9558846cdfcb7a0c38fea880f550365e24331ccb72a0ef38aba8b4b226716c7`;18 feature selections retained,70 RTL/38 Scala sources. XLR54234 (315 lower),RAM186,DSP38,core setup+0.492ns/hold+0.026ns,16 strictly positive timing relationships. Routed mailbox1488 data+2req+2ack checked. Five controller inputs retain expected pins,3.3V pullups,two-stage synchronizers and external-to-first-stage-only exception.

Seven new and79 related real RTL tests passed. Candidate Copy/Key phase diagnostics and24 Alpha oracle cases returned result0/hardware0. Fresh read-only review found no blocking correctness issue. The original physical wrapper stopped with exit1 because Efinity rewrote root `sw_version`2025.2.288.3.8→2026.1.132. Separate qualification audited exactly that difference, all other canonical settings and169 raw inputs unchanged; negative tamper cases passed. It does not relabel the original failure.

The first600-frame attempt ended with argument failure because incremental replay sealing had not finished; hardware error0. Retained that capture and restored accepted normal MENU. Increased the short window to720 rather than skipping the seal. The A/B wrapper finally restored A981+87EF and verified six game tiers; the selected C9C5 was subsequently loaded with the independent comparison-display firmware, whose record is separate.

The elastic-ready idea was informed by [verilog-axi axi_register_wr](https://github.com/alexforencich/verilog-axi/blob/master/rtl/axi_register_wr.v); no external RTL or dependency was imported. `evidence.zip` contains frozen source/RTL identities, tests, failed attempts, raw board captures, physical reports and input audits. Git-LF baseline snapshot is excluded; the physical-byte baseline is included. Four preexisting user-file hashes remain unchanged. JTAG only; no Flash, release overwrite or push.
