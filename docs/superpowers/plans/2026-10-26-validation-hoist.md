# Object validation invariants implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce the existing object's validation-loop work without weakening error rejection or mutating invalid states.

**Architecture:** Preserve all existing checks and the validate-before-update boundary. Compare two minimal rewrites: cached kind/mode locals, and cached kind/path limits (256 accepts every uint8 path in legacy mode). Measure both on unchanged hardware; retain only a repeatable ordinary-frame win. Use existing builders and the accepted40249a3 normal as fallback.

**Tech stack:** Existing C11/RV32IM -Os, UBSan and JTAG/COM9 scripts.

**Spec:** This plan defines a candidate within the continuing hardware-limit goal; no rule or image changes are permitted.

## Constraints and review focus

- Preserve every256 possible kind/shape/path input value for auto/manual and interactive/legacy modes.
- Invalid inputs must still return GPU_DRIVER_ARGUMENT with the entire state unchanged, including last-object rejection.
- Keep capacity, age, campaign, position and restart guards; no removed validation pass, packed aliasing or compiler-flag changes.
- Keep GPU BIT/RTL, CPU renderer, five-way controls, web command/lease behavior, Flash and release bundles unchanged.
- Compare full valid-state/command traces with frozen40249a3 source. Separate diagnostic phases from ordinary performance scores.

## Execution

Ruling: build both candidates through a source-substitution copy of the existing builder and require byte-identical baseline reproduction first. Production remains40249a3 during measurement; restore its normal BIN after the six-run cohort, then apply and fully integrate-test the measured winner before adoption. This preserves a known-good board while avoiding speculative production edits.

- [x] Capture baseline diagnostic phases; restore accepted normal firmware.
- [x] Add exhaustive byte-validation oracle and observe a failing RV32 gate requiring the interactive validation loop to execute at most9 instructions (baseline12).
- [x] Compile both source-only candidates; reproduce the accepted baseline BIN with the source-substitution builder before measuring candidates.
- [x] Run byte-validation, complete state/command differential, path arithmetic and integration checks for the selected candidate; obtain fresh review.
- [x] Compare ordinary A/B/C/A/C/B3600-frame cohorts with identical BIT/input seal/workload. Reject non-repeatable gains.
- [x] Restore the accepted best normal six-tier MENU; archive raw proof and exact artifacts, and commit only accepted production changes.
