# Independent CPU/GPU exhibition implementation plan

> **For agentic workers:** Use superpowers:executing-plans. Execute inline, with fresh read-only review and verified fixes.

**Goal:** Keep the final qualified row-handoff optimization, stop further hardware optimization, and add a separate HDMI CPU-left/GPU-right exhibition:256/512,15seconds per tier, independent refresh and actual displayed-frame FPS. Preserve all six original games.

**Architecture:** Both renderers use the same exact half-size480x270 scene/assets. Reuse the normal game's compact instance builder and cached logical clock; generate the same legacy commands for CPU/GPU. CPU golden-raster jobs progress row by row in private doublebuffers while GPU/PRESENT is pending. GPU never waits for a complete CPU frame; left content changes only when a complete CPU image is available. Count only new CPU images actually presented and GPU scene PRESENTs observed within each15-second window. Static UI setup/final-score overlays are unscored. Prepare only the back buffer, retire static PRESENT before reusing its former front. Existing browser C action enters only from MENU, existing MENU command exits; ordinary gameplay C replay remains unchanged.

**Tech stack:** Existing C, RGB565, GPU legacy queue/texture cache/PRESENT, Chisel hardware unchanged after0c47970, existing local gateway/JavaScript. No dependencies, Flash, release overwrite, push or new worktree.

**Spec:** User requests stop optimization after this round; separate exhibition in difficulty selection; subsequently replaces300frames with independent15-second CPU/GPU runs and asks to recover GPU60FPS.

## Files / constraints

- New split_compare and split_view modules own scheduling, half-size assets and private DDR030/032/034/036/037/038. Normal960x540 game raster loops remain unchanged.
- v3_demo/game_menu/local_keys/runtime add independent seventh menu card and web entry; six level semantics and old replay remain intact.
- Common driver refresh reads atomic DONE then sticky ERROR, retaining pending-tag/wrap bounds. Cached4x4 commands can advance between every read; requiring stable repeated DONE falsely rejected legal progress.
- Compact four half-size atlas phases into3104bytes and load existing texture cache. Restore native atlas only after split commands/PRESENT retire, before rendering any original game.
- Existing wire/status mask unchanged; build20261027 plus existing replay/paused marker identifies the exhibition. No local gateway restart is needed.
- Preserve all preexisting user-file hashes. Keep sources/evidence in this existing worktree.

## Review focus / proof

- [x] Final RTL short A/B/A/B720frames each:8703/8656/8702/8657us,allhealth/deadline0;adopt C9C5,stop further optimization. Evidence committed0c47970.
- [x] Pixel oracle: exact nearest sampling against native full raster across32 real scenes, odd phases, clipping, Key/Alpha/overlap,129600pixels per scene; packed atlas sources allwithin original4096byte cache capacity.
- [x] Logical clock oracle:2400 mixed-time/fire/restart updates preserve complete state and bounded-clock behavior using the immutable initial template.
- [x] Scheduler: two15-second windows, uncapped GPU frame count, CPU jobs during PRESENT, true new-left-frame counting, no partial award, pending-PRESENT positive/negative cancellation drains before reentry.
- [x] HUD: independent emitted-glyph model matches saved text cache after every frame and both physical buffers; redraw only changed cells. Active-front writes reproduced RED and fixed; static UI retirement precedes front reuse.
- [x] Driver: continuously advancing16-bit wrap completions reproduced false TAG RED; atomic-DONE/sticky-ERROR GREEN, future tags and hardware errors still rejected. Update vblank fixture to count completion observations independently of ERROR reads.
- [x] Fresh reviews cover ownership, source phases, shared clock and driver ordering; static-front-write finding fixed with a failing then passing test.
- [x] Final selected firmware: real browser entry/cancel, both15-second tiers,health0,then six original games after native-cache restoration,return fresh released MENU. Finish archive and exact-owned commit.

## Rulings and scope

- Both sides render480x270 using identical assets/scene semantics. FPS describes this cooperative same-screen workload, with one CPU also driving GPU commands; it is not an isolated renderer throughput benchmark.
- Count completion observations within the wall-time window. Deadline polling may conservatively exclude one boundary frame; never fabricate a missed presentation.
- Static setup may present a complete blank UI outside scoring; no animated scene or completed CPU frame is prepared before the timer.
- Main's unused AUTO initialization is compiled out only in the interactive FrameList-only build to reclaim its unused BSS. Legacy/profile initialization remains unchanged; full4KiB stack retained.
- Automatic approval rejected a local gateway restart with only“blocked by policy”. Kept the existing service/protocol instead; no process restart occurred.
- Earlier300-frame synchronized and uncached15-second versions are superseded, retained only as diagnostic history. No endurance or hardware-limit claim follows from this exhibition.
