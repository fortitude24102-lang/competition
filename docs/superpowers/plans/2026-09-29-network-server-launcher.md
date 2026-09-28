# Network Asset Server Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing UDP asset server a reproducible foreground prerequisite and prove real board loads of bullet assets 101/102 complete with zero retries.

**Architecture:** Keep the C server and wire protocol unchanged. Add one PowerShell foreground launcher that validates files, local IPv4, and port ownership, plus one process-level test that exercises the real executable. Integrate that check into the existing software regression and document the board evidence.

**Tech Stack:** PowerShell 5.1, Windows UDP endpoint APIs, existing MinGW-built `asset_server.exe`, Python UDP protocol test, Sapphire firmware/JTAG.

**Spec:** `docs/superpowers/specs/2026-09-28-network-hud-background-design.md`

## Global Constraints

- PC remains an external asset store; Sapphire performs protocol, CRC, game state, and command generation.
- Do not change the C server, UDP protocol, CRC, asset format, default `192.168.1.2:8080`, firewall, or adapter configuration.
- Run the server in the foreground; do not create a service, daemon, watchdog, or administrator requirement.
- Do not terminate an unknown process that already owns the requested UDP port.
- Use temporary JTAG only; do not write Flash or replace `release/v2/`.

## Review Focus

- Relative asset paths in the manifest must resolve from the manifest directory; Task 1 uses a temporary manifest outside the repository.
- A missing local `PcAddress` must fail before the server starts; Task 1 checks an unassigned TEST-NET address.
- An unrelated UDP owner must survive launcher rejection; Task 1 checks its PID remains alive.
- A second invocation against the same executable and port must return success without starting a duplicate; Task 1 checks the original PID remains the owner.
- Killing the server must release the foreground launcher instead of leaving a silent background process; Task 1 waits for both processes to exit.

---

### Task 1: Foreground launcher and process-level test

**Files:**
- Create: `scripts/test-bullet-asset-server-launcher.ps1`
- Create: `scripts/run-bullet-asset-server.ps1`

**Interfaces:**
- Consumes: existing `asset_server.exe manifest.csv udp_port` CLI and `Get-NetUDPEndpoint`.
- Produces: `run-bullet-asset-server.ps1` parameters `ServerPath`, `Manifest`, `Port`, and `PcAddress`; exit 0 for a foreground run or an identical existing listener, nonzero for invalid prerequisites or foreign ownership.

- [ ] **Step 1: Write the failing process test**

Create `test-bullet-asset-server-launcher.ps1` using a temporary asset/manifest and random UDP ports. It must assert: missing launcher fails the test now; a valid invocation owns the port and remains running; a second invocation reports the same executable as already running; a foreign `UdpClient` owner is rejected and stays alive; missing manifest/resource and unassigned local IP are rejected; stopping the real server lets the foreground wrapper exit.

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-bullet-asset-server-launcher.ps1 -ServerPath generated/verification/v2-network-software/asset_server.exe`

Expected: FAIL because `scripts/run-bullet-asset-server.ps1` does not exist.

- [ ] **Step 3: Implement the minimal launcher**

Use only built-in PowerShell/.NET. If `ServerPath` is omitted, select
`generated/verification/v2-network-software/asset_server.exe` first and fall
back to `release/v2/asset_server.exe`. Resolve the executable and manifest to
absolute paths, validate each non-comment `id,relative-file` row, verify
`PcAddress` is assigned locally, query the requested UDP endpoint, compare its
owning process executable path, then either return success, reject the foreign
owner, or invoke `& $server $manifest $Port` in the foreground. Print the
resolved server, manifest, address, port, and PID decisions. On a firewall
failure, point to `docs/efinix_2d_gpu/bullet_demo_usage.md`; never request
elevation or alter a firewall rule.

- [ ] **Step 4: Run the test and existing protocol test**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-bullet-asset-server-launcher.ps1 -ServerPath generated/verification/v2-network-software/asset_server.exe
$env:ASSET_SERVER_TEST_DIRECTORY='sw/efinix_gpu/assets/bullet'
C:/efinity/efinity/python311/bin/python.exe sw/efinix_gpu/tests/test_asset_server_udp.py generated/verification/v2-network-software/asset_server.exe
```

Expected: launcher process checks pass; Python reports `Ran 2 tests` and `OK`.

- [ ] **Step 5: Commit**

```powershell
git add scripts/run-bullet-asset-server.ps1 scripts/test-bullet-asset-server-launcher.ps1
git commit -m "fix: keep bullet asset server foreground"
```

### Task 2: Regression entry and usage documentation

**Files:**
- Modify: `scripts/test-bullet-regression.ps1`
- Modify: `docs/efinix_2d_gpu/bullet_demo_usage.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1 launcher and test CLI.
- Produces: one documented command for normal use and one standard regression entry that covers launcher lifecycle plus both UDP catalogs.

- [ ] **Step 1: Add the launcher test to the native regression**

After building `$out/asset_server.exe`, invoke `test-bullet-asset-server-launcher.ps1 -ServerPath $out/asset_server.exe`; leave both existing Python catalog loops unchanged.

- [ ] **Step 2: Replace direct background-style usage with the foreground command**

Document:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-bullet-asset-server.ps1
```

State that its terminal must remain open during JTAG execution and that the script does not alter firewall or adapter settings.

- [ ] **Step 3: Run the complete native regression**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-bullet-regression.ps1 -HostGcc D:/aaa/mingw64/bin/gcc.exe`

Expected: all existing C suites, launcher lifecycle, and V2/bullet UDP catalog tests pass.

- [ ] **Step 4: Commit**

```powershell
git add scripts/test-bullet-regression.ps1 docs/efinix_2d_gpu/bullet_demo_usage.md README.md
git commit -m "docs: make asset server prerequisite explicit"
```

### Task 3: Real-board network acceptance

**Files:**
- Modify: `docs/efinix_2d_gpu/bullet_board_bottleneck_20260928.md`
- Create: `docs/efinix_2d_gpu/evidence/bullet-board-20260929/network-launcher.log`

**Interfaces:**
- Consumes: foreground launcher, current candidate bitstream, standard bullet firmware, COM13 at 115200 baud.
- Produces: raw UART evidence for assets 101/102 and texture-cache network selection.

- [ ] **Step 1: Build the unchanged normal firmware**

Run: `powershell -NoProfile -File scripts/test-efinix-software.ps1 -FirmwareOnly -Demo bullet -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102`

Expected: RV32 ELF/BIN/HEX build succeeds; `release/v2/` is untouched.

- [ ] **Step 2: Keep the launcher terminal open and load by JTAG**

Run the launcher at default address/port, load the already-built current candidate bitstream if the board lost configuration, then load `generated/verification/efinix-software/gpu_demo.bin` at `0x1000` with `reset halt; load_image ...; resume 0x1000; shutdown`.

Expected: only volatile FPGA/RISC-V state changes; no Flash operation.

- [ ] **Step 3: Capture exact UART acceptance lines**

Record COM13 at 115200 baud until both resource reports and the texture-cache report arrive.

Expected:

```text
BULLET_ASSET,id=101,bytes=1036800,retries=0,result=0
BULLET_ASSET,id=102,bytes=3104,retries=0,result=0
TEXTURE_CACHE,result=0,base=02a00000,bytes=3104,network=1
```

- [ ] **Step 4: Document evidence and commit**

Record hashes, command lines, observed adapter/port state, and any deviation without changing the acceptance criteria.

```powershell
git add docs/efinix_2d_gpu/bullet_board_bottleneck_20260928.md docs/efinix_2d_gpu/evidence/bullet-board-20260929/network-launcher.log
git commit -m "test: verify foreground asset server on board"
```
