# Task 1 — Underflow CDC and focused waveform

## Implementation

- Added `board/efinix_ti60/rtl/display/underflow_pulse_cdc.v`, one synthesizable module in its own `.v` file.
  - Pixel domain detects a `scale_underflow` low-to-high episode boundary and sends a toggle token.
  - GPU domain uses a two-flop synchronizer and one-cycle XOR edge pulse, exported as `underflow_pulse_gpu`.
  - Pixel reset requires observing idle before re-arming; either independently asserted reset flushes and re-baselines the GPU receiver. This prevents a level spanning either reset from replaying as a pulse.
- Integrated `underflow_pulse_gpu` into `hdmi_subsystem.v` without altering the existing sticky `underflow_event`, 16-bit `underflow_count`, black-background scale behavior, vblank synchronizer, or FIFO interface.
- Added a focused self-checking SystemVerilog test and registered it with the Efinix Verilog harness. The focused VCD is generated only by that compact CDC test.

## Tests

Production change tested: omitting the underflow CDC module/output must make the focused behavior test fail; a long source episode, a later separate episode, and independently asserted resets must produce the specified GPU pulse counts.

### RED

Command (run from repository root):

```powershell
& 'D:/FPGA/iverilog/bin/iverilog.exe' -g2012 -s tb_underflow_pulse_cdc -o '.superpowers/sdd/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx/task-1-underflow-red.out' 'tb/verilog/tb_underflow_pulse_cdc.sv'
```

Expected/observed output:

```text
tb/verilog/tb_underflow_pulse_cdc.sv:12: error: Unknown module type: underflow_pulse_cdc
*** These modules were missing:
        underflow_pulse_cdc referenced 1 times.
EXIT=2
```

### GREEN

Command (run from repository root):

```powershell
& 'D:/FPGA/iverilog/bin/iverilog.exe' -g2012 -s tb_underflow_pulse_cdc -o '.superpowers/sdd/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx/task-1-underflow-green.out' 'board/efinix_ti60/rtl/display/underflow_pulse_cdc.v' 'tb/verilog/tb_underflow_pulse_cdc.sv'
& 'D:/FPGA/iverilog/bin/vvp.exe' '.superpowers/sdd/Efinix_2D图像渲染三人开发计划书_官方Demo版.docx/task-1-underflow-green.out'
```

Observed output:

```text
VCD info: dumpfile tb/verilog/underflow_pulse_cdc.vcd opened for output.
PASS underflow CDC: one GPU pulse per episode and independent resets suppress replay
tb/verilog/tb_underflow_pulse_cdc.sv:112: $finish called at 1475000 (1ps)
```

The final focused GREEN command above was re-run immediately before the implementation commit with the same PASS output.

### Integrated elaboration

The direct Icarus elaboration of `tb_hdmi_subsystem`, using its vendor FIFO, HDMI encoder, all display RTL including `underflow_pulse_cdc.v`, and `tb/verilog/tb_hdmi_subsystem.sv`, completed successfully. Icarus emitted only the pre-existing vendor warning:

```text
efx_fifo_wrapper.v:404: warning: Anachronistic use of begin/end to surround generate schemes.
```

`scripts/test-efinix-verilog.ps1` could not execute its normal WSL-hosted regression because this Windows host has no installed WSL distribution; it exited before running RTL. The direct elaboration above is the executable integration check in this environment.

## Files

- `.gitignore` — ignores generated focused VCDs.
- `board/efinix_ti60/rtl/display/underflow_pulse_cdc.v` — new CDC module.
- `board/efinix_ti60/rtl/display/hdmi_subsystem.v` — new GPU-domain pulse port and instance.
- `tb/verilog/tb_underflow_pulse_cdc.sv` — focused self-checking CDC test.
- `tb/verilog/tb_hdmi_subsystem.sv` — declares the added output for its wildcard connection.
- `scripts/test-efinix-verilog.sh` — includes the focused test and new RTL source.

## Waveform

- Path: `tb/verilog/underflow_pulse_cdc.vcd` (generated, 8,278 bytes, ignored by Git).
- It contains `pixel_clk`, `gpu_clk`, `pixel_reset`, `gpu_reset`, `scale_underflow`, and `underflow_pulse_gpu` (plus compact CDC state).
- The five asserted GPU pulses occur at roughly 195–205 ns, 425–435 ns, 845–855 ns, 1125–1135 ns, and 1265–1275 ns: each is exactly one 10 ns GPU period. Reset intervals at approximately 550–585 ns, 685–715 ns, 930–955 ns, and 1350–1375 ns do not add pulse transitions.

## Self-review

- Confirmed the source event is an episode edge rather than a level, so a continuous underflow cannot stretch the GPU pulse.
- Confirmed receiver warm-up establishes a post-reset toggle baseline before arming, and pixel reset flushes that receiver to suppress the toggle reset transition.
- Confirmed existing pixel-domain sticky/count behavior and black output condition remain unchanged in `hdmi_subsystem.v` and `display_scale2x_1080p.v`.
- Confirmed the production RTL directory still contains exactly one module per `.v` file through the existing harness structure check.

## Commit

Implementation commit: `6696f3817df40eb59bdbaf5dc36a05b9c510c39a` (`feat(efinix): synchronize display underflow to gpu`).

## Concerns

- The full WSL/Verilator regression was not runnable on this host because WSL has no distribution installed; direct Icarus integration elaboration passed instead.
- Toggle-based event CDC requires separate episode boundaries to remain observable long enough for the GPU receiver; scanout underflow episodes are expected to be much longer than the synchronizer latency.
