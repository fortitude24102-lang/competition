# Cached validation limits: measured candidate selection

The ordinary1024-object workload reduces work from8648us to8616us per frame,32us /0.370028% against the accepted40249a3 baseline. Only object validation arithmetic in `bullet_demo.c` changes; every validation requirement and the validate-before-mutate pass remain. GPU RTL/BIT, CPU renderer, game rules, compiler flags and five-way/web control code are unchanged.

Six3600-frame cohorts used the same controller BIT, neutral input seal and exact workload:

| Run | Variant | Mean work us | Maximum work us | Maximum wall us |
| --- | --- | ---: | ---: | ---: |
| A1 | Original40249a3 | 8648 | 12779 | 16639 |
| B1 | Cached locals | 8657 | 13582 | 16639 |
| C1 | Cached limits | 8616 | 13525 | 16639 |
| A2 | Original40249a3 | 8648 | 13780 | 16639 |
| C2 | Cached limits | 8616 | 12271 | 16639 |
| B2 | Cached locals | 8657 | 12483 | 16639 |

All21600 frames report zero work misses, late presents, scanout underflows and GPU errors, with observed maxima strictly below16666us. Each cohort reports601 fps_x10,1006..1016 visible objects and130..131 Alpha commands. Each600-input recording seals at CRC `a7bd652f`,256-word budget and offset9836. This work-time improvement applies to this measured neutral1024-object trace, not a claimed display-refresh increase or an assigned speedup for every input trace.

The cached-locals alternative is rejected: although its validation loop drops from12 instructions to9, both runs are9us slower. The selected cached-limits version executes8 instructions in that loop and wins in both orderings. The cause of the rejected alternative's end-to-end regression was not isolated; instruction count alone is not treated as a performance result. Linked `step` shrinks from0x7a8 to0x79c,12 bytes.

The selected code computes `max_kind=manual?3u:2u` and `max_path=interactive?6u:256u` once. Every kind/shape/path byte is still compared. A legacy uint8 path is always below256, so it remains ignored; interactive mode still rejects paths6..255. Mode validation precedes these limits, array count remains bounded, and no state mutation occurs until all objects pass. The extra legacy path load stays inside an existing nonvolatile object under the single-writer contract; no packing, aliasing or widened field reads are introduced.

This uses the [loop-invariant code motion principle documented by LLVM](https://llvm.org/docs/Passes.html#licm-loop-invariant-code-motion). No external implementation is copied or linked, and global compiler options remain -Os. Both proposed rewrites were measured rather than selected solely from compiler output.

Correctness checks include9216 exhaustive mode/byte/index cases (7530 rejected with the entire state unchanged), first/middle/last-object rejection, and all four auto/manual × interactive/legacy combinations. Each candidate matches frozen40249a3 over19200 complete game-state steps and1280 ordered command streams across eight object counts and four seeds, including movement/fire/slow/restart/compare. Full SoftwareOnly/ShapeLut integration passes for the selected production source. A fresh reviewer independently reran the byte/differential checks and approved correctness.

The source-substitution builder first reproduces the accepted baseline probe byte-for-byte. The selected standard-builder normal BIN then exactly matches the normal BIN built from the measured candidate source. Exact identities:

| Artifact | SHA256 |
| --- | --- |
| Unchanged controller BIT | `a98148a59541161874a5f8685c5338b3742b6e553c4ba2d3718f3d25a7c98436` |
| Baseline probe | `52258c56ccf84797faa106097d9a5de71455e8b9276b60c9cc204ec70a3d6c6e` |
| Cached-locals probe, rejected | `fea698b3426c75914595d1308ead8284d0dc27ffd0266e6a87a308f5b34a2e48` |
| Cached-limits probe | `e92b41ad22408bcca28aca87acbccc8ebbc6527f39f395590f1b0ab0fdfaaf6e` |
| Selected normal | `87ef4b1d1e6d86865ffd2665fa347afeb30d96f6d60c62989e4df48f0054fe21` |
| Prior accepted fallback normal | `a6489281abd9aaa148e6293a85cde232b71da97ce10799b77947f194ce86513a` |

The six-run cohort completed with execution handle56901 exit0 and restored the prior normal first. After selected-source full integration completed with handle67243 exit0, the standard-built cached-limits normal was loaded and passed all six real START/MENU acknowledgement/snapshot transitions with handle58637 exit0. Final status was fresh, released MENU with zero underflow/error deltas. No debugger reads followed this restoration. The separate adoption record supersedes the measurement-only comparison's `adopted=false` field without rewriting that historical result.

Separate baseline diagnostic capture completed3600 scored frames plus30 warmup frames. Its121 periodic phase samples average logic2420.56us, build2631.79us, scene3213.42us and HUD192.44us. These are periodic samples, not complete all-frame phase averages, and their instrumented work score is not mixed into the ordinary cohort. The worst diagnostic frame was11587us with two logic steps. The GPU cycle counter includes `swap.io.pending` through `RenderEngine.io.busy`; the reported12894.39us/frame active count therefore includes PRESENT waiting and must not be interpreted as pure GPU drawing time or added to CPU phases. Counter byte totals measure delivered GPU-interface bytes, not DDR PHY utilization.

`evidence.zip` retains exact probes/normals, both candidate source files, frozen reference, disassembly, proof scripts, diagnostics, raw cohort records and final restoration evidence. Every payload is SHA256-inventoried and rechecked; the adjacent SHA256 identifies the archive. Physical timing/CDC remains scoped to the unchanged controller BIT and its161-file snapshot in `../local_keys_20261026/`. Earlier long endurance is separately scoped to its older BIT/BIN, not claimed for this candidate. Flash/release bundles and four preexisting user files remain untouched. Further bottleneck investigation is still required before claiming the hardware limit.
