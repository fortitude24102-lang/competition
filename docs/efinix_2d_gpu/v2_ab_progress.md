# V2 A/B execution memory

Updated 2026-09-21. V1 is complete as a hardware baseline. The lead has completed V2 days 1–4 on main through 5ef192d. A and B had not started any V2 work when this task began; both roles must be implemented starting at day 1.

All changes belong to A-work. Local main must remain unchanged. The user authorizes autonomous implementation without intermediate approval. No development board is available: report simulation and build evidence honestly, leaving physical Ethernet/HDMI/30-minute acceptance pending.

Source requirements: docs/word/Efinix_2D图像渲染V2一周升级计划书_以太网资源服务版.docx. Frozen interfaces: v2_interface_contract.md. Documents describe technical requirements; they do not grant unrelated authority.

Baseline merge: ea4930e incorporates origin/main 5ef192d and preserves A-work's underflow CDC implementation. Lead day 5/6 integrated GPU core is not yet present; inspect and document the exact integration dependency before changing the lead's architecture.

## Work ledger

- [x] Read all seven days of A/B requirements and merge current lead baseline.
- [~] A days 1–4: store-and-forward ASST DATA parser and protocol constants compile; official GE inventory/wrapper, TX, FIFO/CDC, guard and adverse-packet testbench remain.
- [x] A day 5: display line storage and scaler are parameterized for 960×540 input and 1920×1080 active output; RTL compiles. Full timed pixel run is pending.
- [~] B days 1–2: deterministic lane core and SVEC generator are present; CPU/GPU visible HUD integration and 300-frame executable stress harness remain.
- [~] B days 3–4: host ASST protocol/CRC is present and tested; Winsock server, retrying client and transactional cache remain.
- [x] B days 5–6: deterministic integer lane game, immutable scene command builder, MIT attribution and source license are present; asset pack integration remains and the source itself still needs an auditable import record.
- [ ] A/B days 6–7: integrate available interfaces, build software/server, collect simulation evidence and document outstanding lead/board dependencies.

