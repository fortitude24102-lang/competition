# CoreMark Baseline Design

## Goal

Run the official EEMBC CoreMark v1.0 workload on the current five-stage RV32I SoC and record the unoptimized cycle baseline required by the contest guide.

## Benchmark contract

- Pin official sources from `https://github.com/eembc/coremark` at revision `1f483d5b8316753a742cbf5590caf5bd0a4e4777`.
- Do not modify the benchmark algorithm files.
- Use performance seeds `0, 0, 0x66`, `TOTAL_DATA_SIZE=2000`, one context, and stack memory.
- Compile every source with the same `-O2 -march=rv32i -mabi=ilp32` flags and link RV32I multiply/divide helpers from `libgcc`.
- Use the existing 64-bit MMIO machine timer and UART BSP in the target-specific port.

## Result levels

The first result is a fast RTL development baseline. It validates the standard CRC values and records timer cycles for a fixed iteration count. It reports:

- total timer cycles;
- cycles per iteration;
- estimated `CoreMark/MHz = iterations * 1,000,000 / cycles`.

This estimate is not an official contest score because the contest guide requires a run of at least ten seconds. The same build supports a configurable long-run image for later execution on the Pango board or remote FPGA platform.

Maximum clock frequency and `CoreMark/LUT` remain PDS implementation metrics and are outside this baseline run.

## Fast simulation

The existing Scala per-cycle driver is too slow for CoreMark. A small Verilator C++ harness runs a simulation-only `SoCTop` with the CoreMark image preloaded, drives inactive external inputs, captures UART, and stops at EBREAK. It fails on timeout, missing validation text, or any algorithm CRC error.

## Scope

Do not change the CPU microarchitecture, add RV32M, caches, branch prediction, AXI, vendor IP, or invoke Vivado/PDS during this stage.
