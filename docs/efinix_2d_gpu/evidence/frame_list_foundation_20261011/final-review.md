# Independent final review

Reviewer: gpt-6-astra, high, fresh context; range e9b55c4..6e80818. Read-only; no edits, test reruns, board/service access or subagents. Scope: current-game direct 16B list builder and standalone full-list AXI prefetch foundation.

Executor's archive summary of the review, retaining every declined-to-judge boundary; not a verbatim transcript.

Verdict: ready for this foundation stage. Critical0, Important0, Minor1.

## Strengths

- gpu_instances.c:165 skips inactive kind3 slots before every-eighth-slot glow; line170 rejects kind3 in R7. Legacy wrapper selects manual0.
- gpu_instances.h:25 documents disjoint state/items/stats and no partial publication. Construction/argument failure clears all five statistics; capacity is checked before writes. Correct under that internal caller contract, not arbitrary alias detection.
- FrameListReader.scala:57 widens end-address arithmetic; comparing the last included byte's bank permits an exclusive end exactly on a bank boundary.
- The13bit word counter covers4096 words; default RAM addresses0..1023, no final output-index increment.
- Output starts only after AXI registered completion/error. AxiReadEngine includes the final beat's error, so final RESP/ID faults cannot leak descriptors.
- Synchronous RAM read/latch/held-output stages preserve data under backpressure. Busy blocks new requests through consumption; error is latched until a new request.
- Transport completion is explicitly not rendering/PRESENT completion.

## Minor, deferred

Report interface section does not state signal lifetimes together: done is a one-cycle pulse; error remains latched until reset or next accepted request; busy remains asserted through descriptor consumption. Implemented correctly, but future register adapter must not treat done as sticky polling status. No current foundation malfunction.

## Evidence assessment

All nine archived SHA256 entries match. Logs support9600 current-game frames+3 full-pixel samples,12000R7+driver,18C+23UDPHTTP, Reader1/1, GPU81/81 across16suites and8damage suites18000golden frames. REDs are missing API/class compilation failures, not preexisting runtime-bug reproduction. git diff --check passed. Changed-file scope supports production Top/generated hardware/firmware entry/release unchanged.

## Declined to judge

- Top/0500 doorbell and batch execution: explicitly deferred; no integrated path in this change.
- Shared DDR arbitration/scanout priority/system deadlock freedom: standalone evidence does not establish them.
- CPU cache visibility/publication fences/list-template ownership/epoch locking: future producer-consumer integration.
- Backend completion/queue drain/tag wrap/PRESENT/partial-execution recovery: Reader covers transport only.
- Old-bitstream doorbell capability discovery: no new interface delivered.
- Wrong-RLAST recovery: inherited detection inspected, but no malformed-RLAST injection.
- Reset while AXI responses remain outstanding: tested after fetch; shared reset/drain unverified.
- Missing AXI response timeout recovery: intentionally outside transport; needs system policy.
- Arbitrary pointer validity/alias safety: outside explicit trusted internal C contract.
- Nondefault Reader capacities: source bounds appear consistent; simulation uses default only.
- 1024-Sprite hardware: possible1161-item list exceeds1024descriptors; correctly not claimed.
- FPGA RAM mapping/resources/100MHz/synthesis/fullSoC qualification: no corresponding evidence.
- New JTAG/Flash qualification/board health/FPS/stable51260: no deployment or measurement.

Ponytail: reuses descriptor/template logic and AXI engine without speculative integration machinery.
