# Task 2 report — arbitrary-size Transform

## Scope and ABI

Implemented only `GpuTypes.scala`, `CommandValidator.scala`, new `TransformBlitEngine.scala`, new `TransformBlitSpec.scala`, new `TransformValidatorSpec.scala`, and the authorized three-line compatibility adjustment in `GpuFrontEndSpec.scala`.

- `GpuCommand` appends `srcWidthPixels` and `srcHeightPixels`, both UInt16. Internal Bundle width is 268 bits; legacy field order is unchanged. Instance descriptors remain 16 bytes and their existing whole-Bundle zero default supplies the unused new fields.
- `GpuOpcode.Transform=7`, `GpuError.TransformConfig=10`; allowed flags are HFlip=1, VFlip=2, ColorKey=16, Mask=19. The abandoned fixed 2x/half flags are reserved and rejected.
- Output width/height and explicit source width/height are independent. Coordinates are exactly `floor(x*srcWidth/outWidth)` and `floor(y*srcHeight/outHeight)`, then mirrored within the complete source rectangle.
- Validator constructor is `CommandValidator(enableTransformBlit: Boolean = false)`. Disabled validators reject opcode7 regardless of `GpuOpcode.Max=7`; the compile-time flag also gates the Transform-specific source/flag logic. Legacy op0..6 validation rules remain intact, including odd unused single-row strides.
- Transform requires all four dimensions nonzero, both addresses and both strides even, sufficient source/output stride, complete source/output rectangle bounds calculated with at least 64-bit arithmetic, and no source/output range overlap. Error priority is invalid opcode, zero size, TransformConfig, alignment, stride, range, overlap.

## Engine and self-review

The engine uses the existing `AxiReadEngine` and `AxiWriteEngine`, one source read followed by at most one destination half-word write per pixel. It has only the frozen command/completion/AXI/pixelDone ports. It assumes an upstream validated command.

The DDA keeps independent 17-bit X/Y remainders and 16-bit source coordinates. Add/subtract/compare loops advance one or multiple source steps; no combinational divider, interpolation, texture cache, dependency, or speculative generalization was added. X resets each destination row and Y retains its remainder between rows. No coordinate advance occurs after the final output pixel. Mirror is applied after DDA mapping.

Read errors never launch a write for that pixel. B errors finish the already accepted write before retirement. The underlying engines report done only after the promised single R/B handshake, so no subsequent pixel starts and exactly one completion retires after a fault. Completion/tag and command ownership remain stable under completion backpressure. A successful written or keyed-off pixel produces exactly one `pixelDone` pulse; a pixel with an R/B error produces none.

Ponytail full chose ordered scalar transactions and reused the existing AXI engines. The deliberate ceiling is documented in the implementation: severe shrinking spends additional source-step cycles. No FPS or throughput benefit is claimed.

## RED evidence

1. Before adding the ABI or implementation, moved the validator test into the test tree and ran:

   `./scripts/test-v3-gpu.ps1 -Suite @('gpu.TransformBlitSpec','gpu.TransformValidatorSpec') -LogPath generated/verification/v3/dual-track-20261018/transform-red.log`

   Only the validator suite existed at that point. One behavioral failure: opcode7 returned error1 (InvalidOpcode), expected0. No compile error was used as RED evidence.

2. Added the ABI and an inert, correctly typed engine IO shell, plus the revised source-size tests, but retained old validator behavior. Ran the same suites with log `transform-engine-red.log`.

   Four behavioral failures, zero suite aborts: valid engine tag1 and fault-case tag20 never retired (4000-cycle timeout); zero output size returned error0 instead of2; the default-disabled validator accepted opcode7 with error0 instead of1 after `Max` became7. Then implemented the engine and validation logic.

## GREEN and regression evidence

- `transform-green.log`: ran TransformBlitSpec, TransformValidatorSpec, and GpuFrontEndSpec. Engine mapping/fault tests passed, default-disabled/legacy-stride test passed, and all eight GpuFrontEndSpec legacy tests passed. Total11/12. The one failure was an incorrect adjacent-rectangle fixture that still used the default two-row source height; the validator correctly reported overlap6. Corrected the fixture to a one-row source and added per-case diagnostics. No production correction was needed.
- `transform-green-final.log`: reran both Transform suites after the fixture correction and added upper-size residual-carry coverage. **5/5 tests passed, 2 suites completed, zero failures/aborts.**
- `transform-validator-default-green.log`: after the final compile-time disabled-path simplification, reran TransformValidatorSpec. **2/2 tests passed, 1 suite completed, zero failures/aborts.** Engine code remained unchanged from its five-test GREEN run. The prior GpuFrontEndSpec run is the eight-test legacy regression evidence; parent will run the complete combined GPU suite after integration.

The bus-level tests cover 25 sequential commands across normal rendering, five R/B fault variants plus recovery, and bounded upper-size checks. Literal asymmetric fixtures include 2x2 integer scaling, 3x2→5x3, 4x3→3x2, and 7x5→3x2, separate H/V and combined mirrors, partial/all-Key transparency, odd output width, padded source/output stride, half-word phase and guard-byte/strobe preservation, random AR/AW/W backpressure with stalled payload stability, delayed R/B responses, four-cycle completion backpressure, tag ordering, RID/RRESP/RLAST/BID/BRESP errors, and no next pixel after error. Source-size65535/output32768 cases check the X/Y remainder carry using expected first pixels1,2,4 and stop on a fourth-read error to bound simulation runtime.

Validator tests independently cover all four zero dimensions, legal flags and reserved scale bits, alignment including one-row stride, insufficient independent source/output stride, low/high DDR boundaries, 32-bit-wrap-provoking stride values checked with wide arithmetic, maximum16-bit dimensions, exact DDR-end acceptance, complete-source overlap, exact adjacency, and default rejection.

The wrapper's software damage checks also passed on each recorded run (`DAMAGE_SUITE,PASS,C_suites=8,golden_frames=18000,UBSan`). This is wrapper evidence, not a claim of full SoC qualification.

## Integration boundaries

Parent owns APB source-size register/status capability, Render/top routing/arbitration/order, C API and button behavior, generated candidate RTL, and the one final combined full GPU run. Invalid commands are verified at the standalone validator boundary; end-to-end absence of AXI for rejected requests belongs to that integration. No full GPU suite, full SoC suite, board programming, release mutation, synthesis, timing, or FPS test was run by this worker.
