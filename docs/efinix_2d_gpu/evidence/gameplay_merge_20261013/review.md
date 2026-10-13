# Compatibility merge review

Fresh readonly reviewer `/root/gameplay_merge_final_review` reviewed the pending
working tree against base `ac8f137` and A-work `cc86953`. Critical0, Important0;
approved compatibility merge. This is a faithful controller summary, not a
verbatim transcript. No second review was requested.

Confirmed actual V3 GPU scene routing, CopyAhead/HUD/PRESENT ordering, compact
builder enemy/visibility rules, failed list zero statistics, replay version2
canonical field order and retained nibble CRC. Saved tests and three ELF links
were inspected. No board/service access or source edits by the reviewer.

Only minor: the evidence link pointed to a directory still being assembled at
review time. Packaging completed before commit; raw hash verification confirms
the included archive. No code change was requested by review.

Declined behaviors and controller decisions:

- Board/gameplay/256/512 FPS/input/underflows/endurance: not tested this turn;
  merge only, no programming. Risk: new scene's actual performance or hardware
  interaction may differ; old59.6FPS not transferred.
- Runtime stack: static original4KiB reserve and linked margins accepted, no
  dynamic peak claim. Risk: runtime depth may exceed reserve.
- Full SoC/Chisel/historical failures: productionRTL unchanged; new pixel data
  run, no claim of full SoC qualification or repaired historical failures.
  Risk: untested whole-system combinations remain.
- Windows native entry: actual compiler subprocess launch failure retained;
  accept fullWSL20C and actual23network results, not native success. Risk: native
  entry still needs a functioning MinGW toolchain on this PC.
- WIN FPS vs512 battle: never equate low-load victory/killed-enemy frames with
  full-load capacity. Risk: ignoring visible/Alpha/workload fields inflates claims.
