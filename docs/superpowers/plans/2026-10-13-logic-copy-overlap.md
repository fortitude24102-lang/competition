# Logic / Copy overlap implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. User selected direct continuous inline execution and waived intermediate approval.

**Goal:** Measure worst 512 frame then hide background transfer beneath existing game logic, retaining only qualified measured benefit.
**Architecture:** Existing terminal diagnostics; optional earlier CopyAhead launch, reuse original GPU tags/DDR/list/pixel backend, drain before CPU or menu.
**Tech Stack:** C, PowerShell, existing Sapphire/JTAG/WSL tests; no new RTL.
**Spec:** docs/superpowers/specs/2026-10-13-logic-copy-overlap-design.md

## Global Constraints

- CPU basic drawing, gameplay, assets, Ethernet, GPU100MHz,960×540 unchanged. No Flash, release overwrite or push.
- Terminal scheduling switch 02d10008, default feature off, opt-in independent output; all error/timeout and tag/publication checks retained.
- Diagnostic scores never replace normal scores; 30+600 health includes warmup; restore normal menu.

## Review Focus

- LIVE→CPU, death→MENU, explicit MENU: drain original pending tag before any alternate writer.
- Failed advance/build/tag never PRESENT or replay partial work.
- WIN commands retain hardware Fill; A/B local/net use original immutable background.
- Logical time measured before Copy launch so launch overhead does not fabricate an extra simulation interval.
- Terminal JTAG selector never read by normal firmware; one same BIN per scheduling cohort.

### Task 1: Worst-frame diagnostic

**Files:** v3_frame_stats.h, test_v3_frame_stats.c, v3_demo.c.
**Interfaces:** `v3_worst_frame_record(v3_worst_frame *,const v3_worst_frame *)` retains largest valid work frame, derives exclusive other_us; DetailProbe prints retained data at STOP.

- [x] RED→GREEN worst-frame retention/residual/invalid accounting and raw before/after-state tests; terminal-only capture, full V3 software suite.
- [x] Original detail512 30+600: tick600 seal1 logic9339/work21874us; diagnostic source committed bcf446b. No unchanged RTL rerun.

### Task 2: Early Copy candidate and measurement

**Files:** v3_demo.c, test_copy_ahead.c/new scheduling integration test, test-efinix-software.ps1, candidate capture script, README/evidence/report.
**Interfaces:** `V3_LOGIC_COPY`, build `-LogicCopy` requires -CopyAhead/-Interactive/separate OutDirectory; terminal02d10008 selector; reuse copy_ahead_begin/finish and gpu_wait_tag.

- [x] Actual issue-before-logic, exactly-once ordered/full-pixel local/net A/B, MENU/death/CPU drain, timeout/error and WIN tests RED→GREEN.
- [x] Default-off early issue/drain/reuse, software/builder/driver suites and independent normal/probe/detail links pass;4KiB stack preserved.
- [x] Same-BIN original532/522 vs early597/597, late77/90 vs4/4;256early601 zero late. Net benefit retained opt-in, not stable51260.
- [x] Early normalMENU four-tier/control/lease checked, then combined candidate restored and rechecked. Raw hashes/report, one fresh review, local commits; no push.

### Task 3: Budget full seal scan outside one-frame peak

**Files:** replay_input.h/c,test_replay_crc.c,v3_runtime.h/c,test_v3_runtime.c,v3_demo.c,test-efinix-software.ps1,capture-game-probe.ps1,report.
**Interfaces:** `replay_seal_cursor {uint32_t crc,offset;}`, `replay_seal_step(replay_recording *,replay_seal_cursor *,unsigned words)` (1..256;0 pending,1 sealed,negative error); runtime seal_words/cursor default0; `-ReplaySealBudget`, terminal02d1000c0/256.

- [x] Independent canonical CRC budgets1/7/256 RED→GREEN, exact bounds/incomplete/invalid/tamper;620states equal, no601st key, Compare waits, reset/epoch cursor clear, legacy tests remain.
- [x] Full-scan256word budget and default-off build/terminal selector; full original replay_begin CRC verification retained.
- [x] Same-BIN off597/597 late4/4 vs budget598/599 late3/2;256601 zero late, completeCRC/offset equals independent reference.14healthy30+600cohorts, including diagnostic max restart hp0wait1→hp3round0 work16878us. No strict51260 guarantee.
- [x] Combined normalMENU8freshtransitions/control/lease verified, exit healthy/released/no programmer. Normal-r2 byte-equals restoredr1, default legacy link passes1776B extraRAM margin; hashes/archive/report and local commits. No Flash/push.

Completion: [full evidence, review dispositions and remaining qualification](../../efinix_2d_gpu/logic_copy_20261013.md). Independent review found C0/I0; one off-cohort guard finding was upgraded/fixed RED→GREEN and final20C/23network/guard suite green. New fields are terminal diagnostics only. HUD list batching and30minute/active-only512 qualification remain future work, not completed items.
