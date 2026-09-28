# V2 A/B implementation plan

**Goal:** Complete both A and B's V2 deliverables from day 1 using the lead day-4 baseline.

**Architecture:** Official Ethernet transports ASST resources; the CPU owns requests, CRC and cache publication. Independent Verilog network/display and C resource/game components use the frozen interface contract.

**Spec:** ../../word/Efinix_2D图像渲染V2一周升级计划书_以太网资源服务版.docx and ../../efinix_2d_gpu/v2_interface_contract.md.

**Constraints:** A-work only; main read-only; one module per .v; preserve original vendor bytes and licenses; no fabricated physical results. Network DATA is 1–1024 bytes, big-endian 32-byte header; frame 960×540 RGB565 stride 1920. CPU 100 MHz, UDP timeout 20 ms, at most five retries.

## Independent implementation units

1. A network: own rtl/net, tb/verilog/tb_asset*, tb_efinix_ge_mac_wrapper, ge_params.md, vendor/ge_udp and manifest additions. Verify RAM length minus eight, malformed headers, packet bounds, backpressure, CDC/reset and recovery. Use Icarus behavioral tests with byte/metadata scoreboards.
2. B assets: own asset_protocol.h, asset server/pack tools, net_asset_client, asset_cache and respective tests. Verify network encoding, file bounds, CRC, retries and failure-preserving cache with host C tests.
3. B benchmark/game: own benchmark/HUD/stress/lane files and tests, notices/licenses and vectors. Verify formulas, threshold boundaries, deterministic game state, scene immutability and command hashes. Preserve sources/licenses for adapted code.
4. Root display/integration: own display RTL, main.c integration, board adapter/top/XML/constraints and scripts. First test full-frame coordinates, implement scaling, then run one full two-frame comparison. Integrate component interfaces after their tests pass; cross-compile firmware and server; check generated-core availability before board wiring.

## Review focus

- A retry of CRC-failed data must not be suppressed forever as a duplicate.
- Reset in one clock domain must not expose stale metadata paired with a new payload.
- Packet timeout must distinguish network silence from legitimate downstream backpressure.
- Failed cache replacement must preserve referenced, already usable data.
- Benchmark arithmetic must handle zero cycles, overflow and exactly 60 FPS without inventing measured results.

Each implementation unit adds meaningful failing behavioral tests, implements, then runs its targeted tests once; fix failures before integration. Root reviews cross-component contracts and runs the aggregate relevant regressions after changes settle. Record evidence and dependencies in v2_ab_progress.md. Commit role-separated deliverables; do not push or modify main.
