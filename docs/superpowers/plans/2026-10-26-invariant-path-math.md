# Invariant path arithmetic implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce RV32 game-step division cost with identical trajectories, state, commands and validation.

**Architecture:** Keep the current GPU BIT and compiler flags. Replace only path2/3 arithmetic after the existing index/lifetime validation, using exact bounded reciprocal multiplication and signed truncating shifts. Borrow the algorithmic idea from libdivide and LLVM constant division; do not vendor a dependency or copy their implementation. Compare against a frozen prechange source and same-hardware ordinary-frame cohorts before selecting the new normal BIN.

**Tech stack:** C11, RV32IM GCC13.4 with existing -Os, UBSan host checks, existing JTAG terminal probe and six-tier menu qualification.

**Spec:** This document records the narrow candidate within the continuing hardware-limit optimization goal.

## Global constraints

Preserve 49a77ec five-way controls and web commands; user confirmed physical controls normal. Do not change CPU renderer, pixels, game rules, GPU RTL, board configuration, compiler options, Flash or release bundle. Restore the accepted normal firmware after every cohort, including failure. Four preexisting user files remain untouched.

## Review focus

- Valid object indices cover0..1023; existing capacity assertion enforces the bound.
- Path math executes only at age<240+i%120, at most358; expired objects still spawn first.
- Negative odd table values must truncate toward zero when halved.
- Inactive/friendly objects, death/restart, win and malformed states retain existing flow.
- Physical input is disabled in terminal probes; board comparisons must pin the same BIT, neutral input seal, flags, counts and health counters.

### Task1: Prove and measure the candidate

Files: modify `sw/efinix_gpu/src/bullet_demo.c`; add `sw/efinix_gpu/tests/test_bullet_path_math.c` and its existing integration case. Keep baseline source, disassembly, differential harness and raw captures under `generated/verification/v3/logic-invariant-20261026`.

- [x] Freeze the current source and build baseline3600 probe; capture a failing RV32 gate requiring at most two DIV/REM sites in `step` (currently six).
- [x] Add an independent original-formula oracle for every legal index/age in paths2/3, including the expired-object boundary; run it before/after the change with UBSan.
- [x] Make the minimal exact arithmetic change; verify codegen, differential full game states/commands and existing software checks. Fresh review approved, no substantive findings.
- [x] Run controlled ordinary1024-frame A/B/A/B cohorts on the existing joystick BIT. Require exact input seal, expected visible/Alpha counts, zero health/deadline failures and lower repeated mean work before adoption.
- [x] Restore qualified normal six-tier MENU; archive exact artifacts, source identities and measurements, then commit only accepted changes. A failed candidate is rejected, not reported as a speedup.
