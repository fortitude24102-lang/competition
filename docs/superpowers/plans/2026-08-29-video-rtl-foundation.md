# Video RTL Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone, self-checking SystemVerilog regression for the existing `VideoAccelTop` without changing its interface or algorithm.

**Architecture:** A pure SystemVerilog testbench drives the real external module and terminates with a nonzero status on any mismatch. A WSL shell script owns the temporary Verilator build directory, a PowerShell wrapper exposes the test to Windows users, and the existing SoC verification script calls the same entry point before Chisel tests.

**Tech Stack:** Verilog/SystemVerilog, Verilator 5.020 in Ubuntu WSL, PowerShell

**Spec:** `docs/superpowers/specs/2026-08-29-video-rtl-foundation-design.md`

## Global Constraints

- Do not modify `rtl/video/VideoAccelTop.v`, `docs/accel_if.md`, CPU code, memory map, or SoC ports.
- Test RGB888 reset, disabled input, bypass, gray, threshold, and one-cycle valid alignment.
- Do not add video timing, HDMI/VGA, Sobel, line buffers, or CDC logic.
- Build only in a validated temporary directory and leave no generated binary in Git.

---

### Task 1: Standalone video RTL regression

**Files:**
- Create: `scripts/test-video-rtl.sh`
- Create: `scripts/test-video-rtl.ps1`
- Create: `tb/tb_video_accel_top.sv`

**Interfaces:**
- Consumes: frozen `VideoAccelTop` ports from `rtl/video/VideoAccelTop.v`
- Produces: root-level command `powershell -File scripts/test-video-rtl.ps1` returning zero only when every RTL assertion passes

- [x] **Step 1: Add the runner before the testbench exists**

`scripts/test-video-rtl.sh` must derive `project_root`, create a directory with `mktemp -d`, install a cleanup trap, and run:

```bash
verilator --binary --timing --top-module tb_video_accel_top \
  --Mdir "$build_dir/obj_dir" -o video_accel_tb \
  "$project_root/rtl/video/VideoAccelTop.v" \
  "$project_root/tb/tb_video_accel_top.sv"
"$build_dir/obj_dir/video_accel_tb"
```

`scripts/test-video-rtl.ps1` must translate the project root to `/mnt/<drive>/...`, invoke the shell script through `wsl.exe -d Ubuntu`, and throw on a nonzero exit code.

- [x] **Step 2: Run the entry point and confirm the missing-test failure**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-video-rtl.ps1
```

Expected: FAIL because `tb/tb_video_accel_top.sv` does not exist.

- [x] **Step 3: Add the self-checking testbench**

Create a 10 ns clock and a `tick` task that samples one time unit after the rising edge. Use `$fatal(1, ...)` for mismatches and cover these exact transactions:

```systemverilog
reset=1                      -> pixel_out/valid/busy/frame_done are zero
enable=0, valid=1            -> no valid output
bypass=1, pixel=24'h336699   -> 24'h336699
mode=1, bypass=0             -> 24'h666666
mode=2, threshold=8'h80      -> 24'h000000
mode=2, threshold=8'h40      -> 24'hffffff
valid=0 on the following tick -> valid/busy/frame_done return to zero
```

End with `$display("PASS: VideoAccelTop standalone regression"); $finish;`.

- [x] **Step 4: Run the standalone regression**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-video-rtl.ps1
```

Expected: `PASS: VideoAccelTop standalone regression` and exit code 0.

- [x] **Step 5: Commit the standalone regression**

```powershell
git add scripts/test-video-rtl.sh scripts/test-video-rtl.ps1 tb/tb_video_accel_top.sv
git commit -m "test(video): add standalone RTL regression"
```

---

### Task 2: Add the RTL regression to the SoC gate

**Files:**
- Modify: `scripts/verify-soc.ps1`

**Interfaces:**
- Consumes: `scripts/test-video-rtl.ps1`
- Produces: the existing `verify-soc.ps1` gate failing before Chisel/Vivado when external video RTL behavior is wrong

- [x] **Step 1: Prove the current gate does not call the new regression**

Run:

```powershell
Select-String -Path scripts\verify-soc.ps1 -Pattern 'test-video-rtl'
```

Expected: no match.

- [x] **Step 2: Invoke the PowerShell wrapper before the Chisel test suite**

Add:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\test-video-rtl.ps1')
Assert-LastExitCode 'standalone video RTL regression'
Write-Host '[PASS] standalone video RTL regression'
```

- [x] **Step 3: Run the standalone gate and the existing ExtModule test**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-video-rtl.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-chisel.ps1 -TestOnly soc.VideoAccelExtSpec
```

Expected: both pass. If `test-chisel.ps1` has no `-TestOnly` parameter, run the established sbt command through WSL with `testOnly soc.VideoAccelExtSpec`.

- [x] **Step 4: Check the handwritten diff and commit**

```powershell
git diff --check -- scripts/verify-soc.ps1 scripts/test-video-rtl.ps1 scripts/test-video-rtl.sh tb/tb_video_accel_top.sv
git add scripts/verify-soc.ps1
git commit -m "build(video): gate SoC verification on RTL test"
```

---

### Task 3: Branch verification

**Files:**
- Verify only

**Interfaces:**
- Consumes: Tasks 1-2
- Produces: a clean, independently reviewable video branch

- [ ] **Step 1: Run focused verification without Vivado**

Run the standalone RTL regression and `soc.VideoAccelExtSpec`; both must pass.

- [ ] **Step 2: Confirm branch isolation**

Run:

```powershell
git status --short --branch
git log --oneline -3
```

Expected: branch `codex/video-rtl-foundation`, clean worktree, no `sw/` files.
