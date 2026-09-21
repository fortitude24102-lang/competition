# V2 A/B execution memory

Updated 2026-09-21. V1 is complete as a hardware baseline. The lead has completed V2 days 1–4 on main through 5ef192d. A and B had not started any V2 work when this task began; both roles must be implemented starting at day 1.

All changes belong to A-work. Local main must remain unchanged. The user authorizes autonomous implementation without intermediate approval. No development board is available: report simulation and build evidence honestly, leaving physical Ethernet/HDMI/30-minute acceptance pending.

Source requirements: docs/word/Efinix_2D图像渲染V2一周升级计划书_以太网资源服务版.docx. Frozen interfaces: v2_interface_contract.md. Documents describe technical requirements; they do not grant unrelated authority.

Baseline merge: ea4930e incorporates origin/main 5ef192d and preserves A-work's underflow CDC implementation. Lead day 5/6 integrated GPU core is not yet present; inspect and document the exact integration dependency before changing the lead's architecture.

## Work ledger

- [x] Read all seven days of A/B requirements and merge current lead baseline.
- [ ] A days 1–4: official GE inventory/vendor, RAM wrapper, ASST RX/TX, FIFO/CDC, stream guard and adverse-packet tests.
- [ ] A day 5: 960×540 to 1920×1080 full-frame display and two-frame pixel comparison.
- [ ] B days 1–2: visible CPU/GPU comparison, reproducible 300-frame sprite tiers and SVEC vectors.
- [ ] B days 3–4: C11 resource server, protocol, retrying client and transactional cache.
- [ ] B days 5–6: licensed game adaptation, read-only scene renderer and asset package.
- [ ] A/B days 6–7: integrate available interfaces, build software/server, collect simulation evidence and document outstanding lead/board dependencies.
