# Exact path arithmetic: accepted ordinary-frame optimization

The1024-object ordinary game workload now uses less CPU time with identical game states and ordered render commands. Only path2/3 arithmetic in `bullet_demo.c` changed; the CPU renderer, GPU RTL, BIT, game rules, input routing and compiler flags are unchanged.

Four same-BIT3600-frame cohorts completed with terminal execution handle38997 exit0:

| Cohort | Mean work us | Maximum work us | Maximum wall us |
| --- | ---: | ---: | ---: |
| Original A1 | 8821 | 14182 | 16639 |
| Candidate B1 | 8648 | 13707 | 16639 |
| Original A2 | 8820 | 13011 | 16639 |
| Candidate B2 | 8648 | 12544 | 16639 |

The paired average falls from8820.5us to8648us, a172.5us /1.95567% work reduction. Each cohort reports601 fps_x10; this is a reduction in per-frame work, not an increase in the display refresh rate. All14400 frames have zero work misses, late presents, scanout underflows and GPU errors. Each observed maximum remains strictly below16666us. Visible objects remain1006..1016, Alpha130..131, and every600-input recording seals to CRC `a7bd652f` with256-word budget and offset9836. Results apply to this measured neutral1024-object workload; other input traces are not assigned this speedup.

Implementation and proof:

- The existing count/capacity and lifetime guards ensure index0..1023 and age<240+index%120, hence age<360 before path arithmetic.
- For index `i=5q+r`, `(i*205)>>10 = q+floor((q+205r)/1024)=q`; the largest valid residual is1023. Thus `i-5*((i*205)>>10)` is exactly `i%5`.
- For index `i=3q+r`, `(i*683)>>11 = q+floor((q+683r)/2048)=q` throughout the supported range. For age `a=12q+r`, `(a*683)>>13 = q+floor((4q+683r)/8192)=q` throughout the guarded range.
- `(v+(v<0))>>1` preserves C truncation toward zero for every signed16-bit value on the existing arithmetic-right-shift target, including negative odd directions.
- The linked RV32 `step` drops from six DIV/REM sites to two. The remaining two are once-per-step tick arithmetic. Step code grows28 bytes, from0x78c to0x7a8; this measured size/speed tradeoff is accepted without changing global optimization flags.

The algorithmic idea is informed by [libdivide](https://github.com/ridiculousfish/libdivide), including its constant-division macros, and [LLVM's constant division implementation](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Support/DivisionByConstantInfo.cpp). These sources use reciprocal multiplication/shifts and known numerator bounds. This change independently derives three fixed bounded formulas; no external implementation or runtime dependency is vendored.

Validation includes609792 legal index/age cases and127488 expired-object cases using the original division formulas, exhaustive signed16-bit half checks, and UBSan. A frozen49a77ec reference matches19200 complete game-state steps and1280 full ordered command streams across eight object counts and four seeds, with movement/fire/slow/restart/compare. The full SoftwareOnly/ShapeLut integration suite passes. A fresh read-only reviewer approved with no substantive findings.

Selected artifacts:

| Artifact | SHA256 |
| --- | --- |
| Unchanged controller BIT | `a98148a59541161874a5f8685c5338b3742b6e553c4ba2d3718f3d25a7c98436` |
| Original3600 probe | `40db4f913715f28e7d8298f47bb6e6bddd8d3ffca8967883566666e3904147ce` |
| Candidate3600 probe | `52258c56ccf84797faa106097d9a5de71455e8b9276b60c9cc204ec70a3d6c6e` |
| Selected new normal | `a6489281abd9aaa148e6293a85cde232b71da97ce10799b77947f194ce86513a` |
| Previous normal fallback | `70addf7858d5dd6cbd9cf29ae1ed7212b36c72b0554aa08f11efbbe7dc847ea3` |

The new normal preserves six levels, five-way controls, web START/MENU commands and the existing performance challenge. Final real START/MENU acknowledgements and fresh matching snapshots passed for all six tiers; the board returned to a fresh released MENU. No JTAG memory reads were performed after restoration. Hardware configuration/hash stability was checked against the161-file controller snapshot; its physical timing/CDC qualification is retained in `../local_keys_20261026/`. Flash and release bundles were not written. Four preexisting user files remain unchanged.

`evidence.zip` retains raw captures, exact executable artifacts, frozen reference source, current relevant software sources, proof/check scripts and verified per-entry hashes. The archive's adjacent SHA256 identifies it. The earlier108000-frame endurance result is separately scoped to its older BIT/BIN and is not claimed for this candidate. This accepted step does not establish that the overall hardware limit has been reached.
