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

- [ ] RED: test larger/smaller frames, derived residual and invalid phase/wall accounting with literal expected values; WSL GCC existing test.
- [ ] GREEN: bounded struct/helper and terminal-only capture; no normal diagnostic code; integration software tests.
- [ ] Build -DetailProbe current 512; capture original schedule and inspect worst-frame logic/build/scene/HUD/other before choosing Task2. Commit diagnostic evidence/code locally.

### Task 2: Early Copy candidate and measurement

**Files:** v3_demo.c, test_copy_ahead.c/new scheduling integration test, test-efinix-software.ps1, candidate capture script, README/evidence/report.
**Interfaces:** `V3_LOGIC_COPY`, build `-LogicCopy` requires -CopyAhead/-Interactive/separate OutDirectory; terminal02d10008 selector; reuse copy_ahead_begin/finish and gpu_wait_tag.

- [ ] RED: actual scheduling consumer must issue before advance, exactly once, wait before CPU/MENU; preserve argument/error/timeout and local/net A/B ordered pixel results. Test WIN original Copy/Fill.
- [ ] GREEN: minimal early issue / drain / reuse logic with default-off flag; relevant tests plus full V3 software suite, instance/frame-list driver tests; independent normal/probe/detail builds preserve4KiB stack.
- [ ] Same-BIT/BIN original→early→original 512, repeated early and 256 sanity. If benefit absent, restore old default; if present, retain opt-in qualified candidate. Do not claim stable60 without zero late.
- [ ] Restore normal candidate MENU; four tier ACK/state and 256 keyboard/lease test; release control, end programming. Evidence hashes, documentation, one fresh final review and local commits.
