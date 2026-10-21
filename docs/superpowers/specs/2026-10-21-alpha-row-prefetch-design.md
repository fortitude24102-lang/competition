# Alpha next-row read prefetch

Goal: improve GPU throughput/60FPS challenge capacity without changing the CPU baseline, firmware, scene quantity, Alpha math, Key masking, network or clocks. Control is the four-credit candidate07011f45516d2e028678a3ceadd4940fd8279b2d44e02fad0bac632e447e138a with normal BIN33aac5... . Its isolated1040 Alpha costs≈2.21ms and row-end B response stalls the next foreground/background read pair.

This is a focused architectural experiment executed inline under the user's standing continue-without-intermediate-approval instruction. Existing linked worktree/branch is reused. No main merge/push or Flash/release update.

## Choice and contract

Prefer read lookahead using the existing single AxiWriteEngine over adding Alpha multi-write credits: the current engine already overlaps reads between64-pixel chunks but serializes at row boundaries. Reuse those existing33-word foreground/background FIFOs and aligners. Alpha multi-write retirement needs more metadata/error bookkeeping; another background CDMA targets a different wait. Neither is included.

Add trailing `enableAlphaRowPrefetch:Boolean=false` in Dense/Render/Top and CLI `--alpha-row-prefetch`, requiring existing Alpha pixel pipeline. Latch eligibility only for Alpha, width1..64, height>1 and non-overlapping source/destination bounds. In-place Alpha and wide/chunked shapes retain the original path. No software ABI/capability changes.

After the current row's last pixel result is accepted by the packer, the eligible path may start reading the next row before the preceding B. Each pixel of the next row is disjoint from the previous row; shared aligned edge words remain safe because unused halfwords are masked/ignored. Still only one write request is outstanding; next-row AW must wait for the previous write's final B and be suppressed on its error. No early command retirement.

Accepted previous AW/W/B and both accepted read requests must drain on any error. An error during lookahead must not start an unaccepted future write; discard prefetched FIFO data and reset only the abandoned aligner state after bus drain. A following Alpha as well as Fill must work without stale pixels, errors or tags. Read errors already known at row tail do not launch lookahead. Successful output and per-ID AR/AW/W traces must match control; on failure, one safely prefetched DDR row may be read but no promised transaction abandoned. No peripheral/IO reads are eligible.

## Gates

No CPU rendering/config, firmware workload, challenge thresholds, clocks, network, Alpha/Key math or dependencies changed. JTAG/RAM only; no Flash/main/release mutation. Preserve unrelated files and all old sealed evidence. Test/measure once per changed implementation, not repeated unchanged full CPU/SoC suites. All16 final setup/hold relationships strictly positive plus existing routed CDC/resource gates before candidate board loading.

Use real RenderEngine plus byte-memory golden values: cached12x12 at pitch1920, phases0/2, noncached/odd-width/4KiB, delayed B, random stalls, first B error/wrongBID while next R is stalled, read errors and following Alpha recovery. Prove next-row AR overlaps B, only one write outstanding, no early completion, shape fallbacks, identical valid bytes and finite-delay cycle reduction. Existing Alpha and adjacent pipeline regressions cover default behavior.

Compare unchanged phase/1024/normal BINs on control→candidate→control after physical gates. Retain only measured GPU benefit without new errors/underflows; otherwise restore control. Normal1024 and normal3600-frame challenge are different workloads; no ordinary60FPS or absolute-limit claim without its own evidence. Restore selected normal six-tier MENU/release ownership/stop JTAG; one fresh whole-round review and sealed evidence/local commits.
