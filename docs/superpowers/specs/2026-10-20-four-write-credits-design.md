# Four small-blit write credits

Purpose: increase GPU throughput without changing the CPU baseline, scene, Alpha/Key semantics, clocks or software ABI. Previous SmallCopy candidate is the control: BIT SHA256 `118491efb159cc4c8ad2f47b42fc073b5d956a43e9d106fe944df4db2f250dce`. Its isolated Key observer spends about 52% of its window with a missing head B response; this overlaps useful work and is not a speedup prediction.

This is a small architectural experiment, executed inline under the user's standing instruction to continue without intermediate approval stops. No main merge or push is included.

## Choice

Use four, rather than two, outstanding write-burst credits in the existing small-blit writer and DDR owner FIFO. Keep the existing FIFO16 pixel data and single ordered W channel. This is smaller and easier to isolate than cross-Sprite command issue/retirement; a separate CDMA targets background traffic rather than the observed cached-Key row turnaround. Neither alternative is included in this round.

Trailing `writeCredits: Int = 2` is propagated Top → Render → Dense → AxiWritePipeline/CachedKeyStream, and Top → DdrQosArbiter. Only 2 and 4 are supported; four requires the existing untrimmed Key write pipeline. CLI `--four-write-credits` selects 4; absent selects 2. No register/capability bits change.

The writer reserves a response marker at AW acceptance, including split bursts. The arbiter reserves room before selecting AW and commits owner at final W, exactly as before. Do not change this reservation scheme, arbitration priority, read buffering or scanout emergency rules. CachedKeyStream's outstanding-row counter must represent 4, not wrap to zero. Completion waits all accepted W/B and reads; errors stop new requests but never withdraw an offered AW or abandon a promised row. Preserve request-local B error attribution and next-command recovery.

## Gates

No CPU raster/config, challenge thresholds, scene quantity, Alpha/Key or network changes. JTAG/RAM only; no Flash or remote writes. Preserve unrelated files. All final setup/hold domains positive before loading. Prefer existing tests and scripts; no dependencies.

Tests must prove four admissions before any B, fifth blocked, exact ordered W/strobes, all four response positions and bad BID, split-4KiB behavior, delayed completion, pending-row count at four, mixed Render/Asset B ownership and emergency drain. Full Render Copy → Fill → cached even-width Key → Alpha must preserve golden bytes and recover after injected read/write failures.

Generate isolated RTL and Efinity build, check one module/file, all final setup/hold domains, resources and routed network CDC. Then compare unchanged BINs on control → candidate → control; normal 1024 measurements and isolated AXI phases are distinct from the normal 3600-frame challenge. Qualify/retain only with observable benefit and zero new errors/underflows. If no repeatable benefit, restore the two-credit normal six-tier menu; retain the experiment default-off and report negative results. No claim that ordinary1024 is stable60 without its own evidence.
