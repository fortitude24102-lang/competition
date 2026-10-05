# V3 A control RTL handoff

2026-10-05 owner integration update: see `v3_integration_20261005.md` for current board evidence and limits. The independent-delivery notes below describe the original A-work handoff. The owner now wires `efinix_network_subsystem`, and shared `configured_local_ip/configured_peer_ip` outputs feed the bridge's same-named GPU-domain inputs. TX COMMIT snapshots these two addresses into the existing packet CDC; bridge `tx_local_ip/tx_peer_ip` outputs are GE-domain descriptor fields. No APB/wire contract changed. Wildcard test harnesses must declare these added ports. Do not hard-code a second management subnet.

Implemented on `A-work`, starting from `79a0b7f`, using the frozen 2026-10-01 interface and two-week plan. This is an independent simulation deliverable; it has not been integrated into the Sapphire adapter, synthesized, timed, or tested on a board. No vendor sources, GPU logic, C code, adapter, project lists, or release files are changed by this RTL task.

## Files and integration

Each production `.v` defines exactly one module. Add these self-owned sources to the integration candidate:

- `rtl/net/udp_payload_router.v`: four-byte magic buffering/replay, unchanged ASST byte/last/length stream, AGC1 routing, unknown/short prefix draining.
- `rtl/net/control_udp_rx.v`: 32-byte HELLO/KEYS validation, version/length/reserved-bit/CRC/last checking, packet and receive timestamp, bounded drop-and-drain behavior.
- `rtl/net/net_control_bridge.v`: frozen 0x0300 APB registers, depth-four RX records, atomic RX snapshot/release, 32/128-byte protected TX shadow, independent clocks/reset invalidation, completion and Gray-synchronized counters.
- `rtl/net/udp_tx_arbiter.v`: whole-packet round-robin descriptors, owner-specific done/error.
- `rtl/net/efinix_asset_network_shared.v`: opt-in shared MAC entry point, original resource APB and Asset DMA ports, independent resource request session, management RX/TX ports.
- `rtl/net/efinix_ge_mac_wrapper.v`: backward-compatible 32-byte default and opt-in bounded 32/128-byte TX cache; metadata and payload latch on acceptance.

Paths above are relative to `board/efinix_ti60`. Reuse the existing `rtl/display/pixel_async_fifo.v` and unmodified vendor FIFO/MAC sources.

Ruling: keep `efinix_asset_network.v` with its exact V2 port list and hierarchy, and put the shared implementation in `efinix_asset_network_shared.v`. Existing `tb_asset_network.sv` uses wildcard ports and inspects the original hierarchy, so adding optional ports directly would break that unmodified harness. The integration owner selects the shared module explicitly with `ENABLE_CONTROL=1`; the old module remains the resource-only fallback. The cost is two resource entry points to maintain, and the new module must be explicitly listed in the candidate project. `ENABLE_CONTROL=0` disables management TX and drains management RX. `efinix_ge_mac_wrapper` defaults `ENABLE_VARIABLE_TX=0`; the shared entry point sets it to one.

Connect the shared module's GE-domain management byte stream `control_rx_byte/valid/ready/last/length` to `control_udp_rx.rx_byte/valid/ready/last/length`. Connect parser `packet/packet_valid/packet_ready/arrival_ms/drop_count` to bridge `rx_packet/rx_packet_valid/rx_packet_ready/rx_arrival_ms/rx_drop_count`. Connect bridge `ge_time_ms` to parser `current_ms`.

Connect bridge `tx_packet/tx_packet_valid/tx_packet_ready/tx_length` to shared `control_tx_packet/control_tx_valid/control_tx_ready/control_tx_length`. Connect shared `control_tx_done/control_tx_error` to bridge `tx_done/tx_error`. Other shared descriptor inputs are GE-domain `control_tx_session/ports/peer_ip/local_ip`. For the standard management endpoint ports are `32'h1f9a1f9a` (8090/8090); IPs come from integration configuration. Session is the network-order session stored at packet bytes 8..11, i.e. `{tx_packet[71:64],tx_packet[79:72],tx_packet[87:80],tx_packet[95:88]}`. These descriptor inputs must remain stable through their valid/ready handshake.

The resource parser samples its session only when a **resource** request descriptor is accepted in GE. Management requests never update this register, resource IP/port APB configuration, resource busy/done/error/count, or Asset DMA active/abort signals. An unsolicited ASST reply without a resource request is rejected. Resource GET length remains 32 and its upper 768 packet bits are zero.

There is no new game or GPU dependency. The owner must explicitly decode management APB 0x0300..0x03ff and select this bridge in the Sapphire adapter, without moving old 0x0000/0x0100/0x0200 windows. Neither production adapter nor source lists are modified here.

## Byte order and APB behavior

Packet bit `[7:0]` is byte zero on the wire. Each APB word contains four consecutive wire bytes in little-endian byte lanes. AGC1 bytes `41 47 43 31` therefore read as `RX_WORD0=0x31434741`. Protocol integers remain network big-endian inside those bytes. Independent PC HELLO/KEYS golden vectors in `tb/vectors/v3_control_packets.json` are embedded as literal test fixtures; ACK/telemetry serialization belongs to Sapphire.

| Local address | Behavior |
| --- | --- |
| 0300 | ID `0x4d475431` |
| 0304 | bit0 queue available, bit1 RX snapshot valid, bit2 TX ready, bit3 sticky TX error |
| 0308 | Write 1 to freeze queue head and receive age |
| 030c | Write 1 to consume that snapshot once |
| 0310 | Frozen age in milliseconds; valid with snapshot |
| 0314 | Gray-synchronized parser drop count |
| 0318 | Write 1 to commit a complete TX packet |
| 031c | TX completion count, including errored completions |
| 0320..033c | Eight frozen RX words |
| 0340..03bc | Thirty-two TX shadow words |
| 03c0 | TX length, reset/default 32; only 32 or 128 accepted |

APB completes immediately. Undefined or unaligned addresses, writes to read-only registers, no-snapshot RX word/age reads, repeated RELEASE, repeated SNAPSHOT while already frozen, incomplete COMMIT, busy COMMIT, and busy TX word/length writes return `pslverror`. SNAPSHOT/RELEASE/COMMIT accept only value 1. A rejected commit sets sticky TX error; MAC completion error also sets it. A legal commit or either reset clears it. Busy rejection does not mutate the in-flight packet. Commit consumes the written mask, so each later commit requires all eight or thirty-two necessary words to be written again. Changing TX_LENGTH does not clear previously written words; software writes the required packet before COMMIT.

The bridge uses `pixel_async_fifo` at depth four for RX records (256 packet bits plus 32 timestamp bits), TX descriptors, and completions. The head stays in the RX FIFO until RELEASE, so a frozen snapshot consumes one of the four records. Parser byte readiness is always asserted; when FIFO admission is unavailable, a complete packet is drained and dropped, counted once. Invalid classified AGC1 lengths are passed to this draining parser so they are counted. Unknown magic and prefixes shorter than four bytes are drained by the router and do not increment the parser's drop count. Oversized AGC1 uses fixed bounded storage and drains until `last`.

`GPU_CYCLES_PER_MS=100000` at the required 100 MHz GPU clock. A registered GPU-domain 1 ms counter becomes registered Gray code, passes two GE synchronizer stages, is sampled at the first parser byte, and returns with the record through the RX FIFO. RX_AGE subtracts that GPU-origin timestamp from the current GPU-origin count when SNAPSHOT is written and stays frozen thereafter. GE does not run an unrelated timebase. Small synchronization/classifier delay adds a bounded timestamp uncertainty; age is intended for the 250 ms input lease. Counter arithmetic wraps naturally at 32 bits. The test parameter 100 speeds simulation only; production defaults remain 100 MHz/1 ms.

Either GPU or GE reset asynchronously clears both FIFO halves, snapshots, timestamps, written masks, busy/completion/error flags, and resource/shared transactions. Bridge and shared network synchronize deassertion separately for each clock. Reset the standalone parser with the combined reset, with deassertion synchronized in GE in the integration wrapper. Management traffic does not wait for CPU polling or Asset DMA activation.

## Verification and evidence

Native executable entry, using the existing `D:/FPGA/iverilog` installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-v3-control-rtl.ps1
# After the original resource suite has passed, iterate only affected suites:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-v3-control-rtl.ps1 -Scoped
# Original harnesses alone, unchanged:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-v3-control-rtl.ps1 -Legacy
```

Required compatible-host entry:

```sh
wsl bash scripts/test-v3-control-rtl.sh
# Subsequent targeted iterations:
wsl bash scripts/test-v3-control-rtl.sh --scoped
```

The shell entry compiles every self-owned net module with Verilator and then invokes the original `test-v2-network-rtl.sh`. This Windows host has no installed WSL distribution, so shell execution/Verilator is unverified. No tools were installed. Native verification uses the **real** vendor FIFO model and two real vendor MAC peers, not a FIFO or MAC mock.

Results/logs are saved under `generated/verification/v3/control-rtl`:

- `tb_net_control`: PASS — ASST exact prefix replay with backpressure; unknown/short drains; literal HELLO/KEYS PC vectors; CRC-invalid packets; CRC-valid bad HELLO data, upper key bits, trailer/version; ACK refusal; early/late last, bad lengths; depth-four admission, counted overflow, next legal recovery; APB word order, frozen queue head and age with later input; old age; incomplete/busy TX, immutable 128-byte and valid 32-byte TX, mask consumption, done/error, either-clock reset.
- `tb_net_control_arbiter`: PASS — both owners requesting, MAC backpressure, alternating packet owners, complete metadata selection, blocked mid-packet replacement, correct success/error return, idle completion suppression and reset.
- `tb_net_control_mac`: PASS — real MAC management TX while DMA inactive; immutable full 128-byte wire payload and UDP length; magic-split management RX without DMA contamination; resource GET then management TX then valid ASST64 with independent resource session; invalid length64 gets bounded done/error.
- Unmodified `tb_asset_udp_rx`: PASS — its existing parser error/backpressure/boundary/timeout recovery checks.
- Unmodified `tb_asset_network`: PASS — real MAC ARP/GET/DATA64/DATA1024, CRC rejection/recovery, asynchronous clocks, payload backpressure, reset, legacy APB errors.

Tests were authored before production implementation. `red-missing-modules.log` and `red-missing-arbiter.log` record the initial missing-module elaboration failures; these are absence evidence, not behavioral failures. A later behavioral red-to-green check is `red-management-length-drop.log`: the malformed-length management test failed because drop count was five instead of six; routing recognized AGC1 to its draining parser fixed it, and the scoped suite passed. The initial shared-MAC test timed out because it tried unsolicited ASST without a resource GET; investigation showed resource session zero, so the harness was corrected to issue GET and then a management send before checking DATA. This was a harness precondition correction, not a production workaround.

Only read-only vendor warnings remain in native build logs: FIFO generate begin/end style and ICMP RAM address truncation. No new self-owned module warnings appear in the native run.

## Remaining integration/board checks

These simulations do not establish Efinity synthesis/resource use, CDC timing constraints or bus-skew constraints for Gray signals, 100 MHz timing closure, real PHY/ARP reliability, end-to-end keyboard latency, or packet-loss behavior under resource load. The existing shared RX RAM still admits one frame at a time and can drop other Ethernet frames while busy. CPU session/sequence/lease validation is intentionally in Sapphire, and FIFO age alone does not enforce the 250 ms lease. IP/port descriptors must use the intended board configuration. Owner integration, FPGA timing and board measurements remain outstanding; this handoff does not claim the full V3 feature is already on board.
