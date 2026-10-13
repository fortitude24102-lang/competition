# Performance challenge implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. User requests inline continuous work, no intermediate approvals.

**Goal:** Add a truthful60FPS maximum-active-Sprite challenge on HDMI and web without replacing gameplay/CPU baseline.
**Architecture:** RISC-V deterministic workload/search/strict statistics in private DDR; original FrameList/Alpha/Key backend; bounded compatible management packet extension.
**Tech Stack:** C, existing Verilog, Python/JS stdlib, WSL/GCC/Icarus/Efinity/JTAG.
**Spec:** docs/superpowers/specs/2026-10-13-performance-challenge-design.md

## Global Constraints

- Keep GPU100MHz/960×540/RGB565, CPU drawing and normal game algorithms/configuration, assets and Ethernet; no Flash/release overwrite/push.
- N32..909, Key8 (firstplane16), Alpha12/1in8/64..124; scene state02d28000..02d40000, existing descriptor banks only; defaultoff/separate builds.
-60warm health checked,600search,3600confirm, zero late/work/health, precise>=60 and full activity; capacity not hardware ceiling.
- PC input/display only; oldBIT capability bit5 prevents new mode;32B type6 and unchanged128B field semantics, statusbits12/13.

## Review Focus

- Warmup health failure and rounded59.99FPS cannot qualify;10s candidate cannot be reported as confirmed.
- MENU/restart/capability/session/lease reset cannot reuse old qualification or allow concurrent list/CPU writes.
- N909 descriptor1024, all rectangles fully visible/actual Alpha and Key, private state bounds and original CPU BSS untouched.
- ACK/standard/performance TX fairness, duplicate/stale packets and fresh snapshot after applied command.
- NewBIT must pass resource/timing/CDC before JTAG; preserve original source lists/release and safe fallback.

### Task 1: RISC challenge core

**Files:** new performance_challenge.h/c,test_performance_challenge.c,Makefile/test-v3-integration.ps1.
**Interfaces:** pc_init(pc_state*,unsigned max,uint32_t seed);pc_advance(pc_state*,const game_input*);pc_build(const pc_state*,uint32_t dst,int network,gpu_instance*,gpu_instance_stats*);pc_record(pc_state*,uint32_t hz,uint32_t work,uint32_t wall,uint32_t under,uint32_t errors,unsigned visible,unsigned alpha).

- [ ] RED missing API then GREEN literal geometry/descriptor/full-activity, strict stats/warm failures, search bracket/final retry/capacity/invalidation; independent pixel reference and N909 guards. WSL sanitizer test.
- [ ] Keep state private DDR, fixed workload, bound600/3600 and no fake best; integrate build/test manifest and local commit.

### Task 2: Compatible command/status and UI/runtime

**Files:** v3_control_protocol.h,net_control.h/c,v3_runtime.h/c,v3_demo.c,game_menu.h/c,hud.h/c,protocol.py,gateway.py,web index/dashboard,build/test scripts;control_udp_rx.v/net_control_bridge.v and tests.
**Interfaces:** opcode3 level0;bit5 capability;status12/13;type6(target,best,stage_frames);nc_queue_performance/nc_try_publish;pc core above, PERF phase2 with original modeLIVE.

- [ ] RED literal C/RTL/Python new commands/packet/fairness/stale rejection/unsupported cap and runtime/menu/HUD/dashboard behavior; implement smallest compatible extension, preserve old paths.
- [ ] Wire originalGPU loop to pc movement/builder/qualification; full costs and health, clear old metrics on count transition, R reset/no C comparison; full suites and default/feature ELF links.
- [ ] Independent candidate board project/new netRTL using qualified frame-list generatedRTL; timing/resource/CDC before JTAG. Inspect first entry/cancel/supported/keyboard; auto-search and3600confirm if board ready, archive all results honestly; restoreMENU/release.
- [ ] One fresh whole-branch review, fix important by RED→GREEN, report/hash/readme and local commits, no push. If synthesis/board unavailable preserve source and explicitly record limitation.
