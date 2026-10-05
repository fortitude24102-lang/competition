# V3 management driver and input handoff

2026-10-05. Based on A-work baseline `79a0b7f` and the fixed 2026-10-01 V3 interface contract. These are independent software modules and host register tests; no production main/SoC integration or board measurement is claimed.

## Files and API

Owned files are `sw/efinix_gpu/include/v3_control_protocol.h`, `net_control.h`, `input_state.h`; `sw/efinix_gpu/src/net_control.c`, `input_state.c`; and `sw/efinix_gpu/tests/test_net_control.c`, `test_input_state.c`.

```c
int nc_init(nc_device *, uintptr_t apb_base);
int nc_poll(nc_device *, uint32_t now_ms, nc_input *);
int nc_try_publish(nc_device *, const nc_telemetry *, uint32_t now_ms);
void input_update(game_input *, const nc_input *);
```

`nc_init` returns zero on success. Other driver calls return a negative error, zero without progress, or positive progress. Errors are `NC_ERROR_ARGUMENT=-1`, `NC_ERROR_UNAVAILABLE=-2`, and `NC_ERROR_HARDWARE=-3`. Poll progress includes consuming rejected packets or releasing an expired lease. Publish progress means one packet was submitted. Initialization with an unknown management ID leaves the device unavailable; polling supplies disconnected zero keys, allowing the caller to choose its local fallback.

`nc_device` owns bounded session state, one pending ACK, one latest telemetry structure, counters and rate bookkeeping. No allocation, waits or unbounded queues are used. `nc_poll` consumes at most four RX records per call; `nc_try_publish` submits at most one packet. The caller must be the sole owner of the management TX shadow registers.

## MMIO and packet representation

Pass the existing GPU block base, normally `GPU_APB_BASE` from `gpu_regs.h`. Passing zero selects that same base. All `NC_REG_*` offsets include the management window: ID `0x0300`, STATUS `0x0304`, SNAPSHOT/RELEASE `0x0308/0x030c`, AGE/DROP `0x0310/0x0314`, COMMIT/DONE `0x0318/0x031c`, RX words `0x0320..0x033c`, TX words `0x0340..0x03bc`, and TX_LENGTH `0x03c0`. No existing GPU, resource or network ABI changes are needed.

APB words carry packet byte zero in bits 7:0, byte one in 15:8, byte two in 23:16, and byte three in 31:24. For wire magic `41 47 43 31`, the raw word is `0x31434741`. Multi-byte packet fields are serialized explicitly in network big endian; C structures are never copied directly to the wire. CRC is the existing `asst_crc32`, so link `asset_protocol.c` when building the driver.

RX requests a stable snapshot, reads age and all eight words, then releases exactly once. Every consumed packet receives software length/version/magic/CRC/type/reserved-field validation, even though RTL also checks it. Incoming ACKs, zero sessions, reserved key bits and malformed HELLO data are rejected.

TX checks READY before any shadow write, writes exactly eight ACK or 32 telemetry words plus the matching 32/128-byte length, fences and commits once. A busy transmitter receives no writes. ACK has priority over telemetry; a new telemetry request replaces the latest pending structure, preserving the packet already committed. Snapshot IDs advance only after successful telemetry commit, modulo 2^32. Default telemetry spacing is 200 ms (5 Hz); `publish_interval_ms` may be configured, with values below 100 ms clamped to 100 ms (10 Hz maximum). ACK is independent of that telemetry limit. Passing NULL telemetry flushes only an already pending ACK or snapshot.

## Sessions, lease and reset

Use `now_ms` from the same GPU-clock one-millisecond timebase as hardware RX age, modulo 2^32. Reception time is `now_ms - RX_AGE_MS`; processing a backlog never grants another 250 ms. Age 250 ms is still valid; greater age clears keys, connection and pending ACK. A key packet must belong to the established session, have a sequence delta in `1..0x7fffffff`, and have reception time at or after the accepted handshake/latest record. Duplicate, old and exactly half-range sequences do not refresh the lease.

HELLO contains zero data and cannot move the player. Another session cannot take over an active lease. Repeating the original HELLO for that active session queues its identical ACK without extending the lease or changing held keys. The most recently expired session remains retired: a reconnect must create a new random nonzero session. The PC gateway must regenerate its session after a lease/watchdog failure instead of reusing the expired session. This also lets delayed KEYS or HELLO for the retired session be discarded.

Call `nc_init` on firmware restart or after a known management/FPGA reset. It discards up to four pre-existing hardware FIFO records, preventing queued pre-reset HELLO/KEYS from restoring movement; post-reset KEYS alone cannot establish a session. The register ABI has no reset-generation field, so the driver cannot independently detect an ID-preserving hardware reset or authenticate a previously unseen delayed HELLO. Lifecycle reset notification and fresh session generation remain integration responsibilities.

## Game input and telemetry integration

Initialize `game_input` to zero. Its first public fields are `held`, `pressed`, and `released`; following bookkeeping is caller owned, so separate instances stay independent. Opposing left/right or up/down keys cancel. Normal keys use held-state edges. RESTART/COMPARE pressed bits execute once for a new modular `action_sequence`, including wrap; repeated snapshots or old action sequences do not repeat an action. A NULL, disconnected, zero-session or age-over-250-ms input releases all keys.

When a new action counter accompanies an identifiable rising action key, only the rising action is emitted. Holding RESTART then pressing COMPARE emits COMPARE alone; holding COMPARE then pressing RESTART emits RESTART alone. If no action edge is visible, the newer counter still emits the held action mask, recovering a same-key release/re-press whose intermediate zero snapshot was lost. The ABI has one shared counter rather than separate action counters, so both-held/no-edge snapshots cannot identify which action changed: both bits are emitted and the game retains its conservative RESTART priority. This ambiguity does not change the wire protocol.

Game logic consumes movement/fire/slow from `held` and restart/compare from `pressed`. When recording the u16 replay stream at a logic tick boundary, encode continuous held bits plus action pressed bits:

```c
uint16_t record_keys = (input.held & (uint16_t)~V3_KEY_ACTION_MASK)
                     | (input.pressed & V3_KEY_ACTION_MASK);
```

The caller fills all 27 named telemetry fields and their validity/status semantics. The driver keeps their prescribed order, removes reserved status bits, and chooses header session from the live control lease (zero for observers). It does not fabricate measurements or alter caller payload data to make it current. Set `V3_STATUS_CONTROL_CONNECTED` from `nc_input.connected`, populate `input_age_ms`, and use the `V3_VALID_*` group flags; unavailable measurements must stay invalid. CPU stale, probes, loading, local fallback, comparison, pause and recovery tags are defined in `v3_control_protocol.h`.

## Verification record

Native GCC on Windows was used because WSL has no installed distribution. Both new tests first failed against missing-function stubs, then passed against the implementation. Separate newer-sequence/older-reception and held-action/new-other-action regressions were observed failing before their fixes. Logs are in `generated/verification/v3/game/`: `net-control-red.log`, `input-state-red.log`, `net-control-reception-red.log`, `input-state-cross-action-red.log`, and the final `net-control-green.log`, `input-state-green.log`, `asset-protocol-regression.log`, `network-assets-regression.log`.

Final compilations use `-std=c11 -O2 -Wall -Wextra -Werror -pedantic`. The driver test additionally uses `-DNC_TEST_BACKEND`, providing `nc_io_read`, `nc_io_write`, and `nc_io_fence` register-boundary functions. The driver test links `net_control.c` and `asset_protocol.c`; input tests link `input_state.c`. The baseline asset CRC and network asset client regression tests passed as well.

Covered behavior: missing ID and invalid arguments; startup FIFO discard; no pre-handshake KEYS; coherent snapshots during arrival; bounded four-record polling; all packet validation fields; session contention; duplicate HELLO ACK; age-based expiry and age 250/251; stale/delayed records; sequence wrap/half-range; busy TX without writes; complete eight/32-word commits; ACK priority; latest pending telemetry; 5/10 Hz limits and clock wrap; input edges/opposing keys; action wrap/dedup; disconnect/stale release; and independent caller-owned input state.

Literal C fixtures were compared byte for byte with A's `tb/vectors/v3_control_packets.json`: HELLO and KEYS decode, complete ACK (`CRC c4e6ddc9`), complete 27-field telemetry (`CRC 7e06afbd`), and observer telemetry (`CRC f8647dd5`) all passed. These are host/APB-contract checks, not evidence of wire delivery, board latency, RTL reset behavior or complete project regression.
