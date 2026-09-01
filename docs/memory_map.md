# SoC Memory Map

The address map is frozen for the Demo. Unlisted addresses return a bus error and never alias another target.

| Region | Address range | Access | Reset/use |
|---|---:|---|---|
| Boot RAM | `0x0000_0000`–`0x0000_FFFF` | R/W, instruction read | 64 KiB program and data memory |
| Machine timer | `0x0200_0000`–`0x0200_FFFF` | MMIO | 64-bit cycle time and timer comparison |
| UART | `0x1000_0000`–`0x1000_0FFF` | MMIO | Decoded-byte transmit and receive interface |
| GPIO | `0x1000_1000`–`0x1000_1FFF` | MMIO | Eight input and eight output bits |
| Accelerator | `0x3000_0000`–`0x3000_0FFF` | MMIO | Video control and status |
| External memory | `0x8000_0000`–`0xFFFF_FFFF` | R/W | Reserved CoreBus window for a future AXI bridge |

Boot RAM does not define same-address read-during-write behavior. Software must not write a word through the data port while the instruction port reads that word in the same cycle; self-modifying code needs a separately specified synchronization policy.

## Machine timer registers

| Offset | Name | Access | Definition | Reset |
|---:|---|---|---|---:|
| `0x4000` | MTIMECMP_LO | R/W | Timer comparison bits 31:0 | `0xFFFF_FFFF` |
| `0x4004` | MTIMECMP_HI | R/W | Timer comparison bits 63:32 | `0xFFFF_FFFF` |
| `0xBFF8` | MTIME_LO | R | SoC cycle time bits 31:0 | 0 |
| `0xBFFC` | MTIME_HI | R | SoC cycle time bits 63:32 | 0 |

The timer interrupt is asserted while unsigned `mtime >= mtimecmp`. RV32 software reads a coherent time value by reading high, low, then high again and retrying if the high words differ.

## GPIO registers

| Offset | Name | Access | Definition | Reset |
|---:|---|---|---|---:|
| `0x00` | OUTPUT | R/W | Low 8 bits drive output pins | 0 |
| `0x04` | INPUT | R | Low 8 bits sample input pins | input value |

GPIO accepts aligned 32-bit accesses. OUTPUT writes require all four byte strobes; invalid offsets and writes to INPUT return an error without changing the output register.

## UART registers

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | TXDATA | W | Low 8 bits enqueue one byte |
| `0x04` | STATUS | R | bit0 `txReady`, bit1 `rxValid` |
| `0x08` | RXDATA | R | low 8 bits consume one buffered byte; empty read errors |

## Accelerator registers

| Offset | Name | Access | Definition | Reset |
|---:|---|---|---|---:|
| `0x00` | CTRL | R/W | bit0 `enable` | 0 |
| `0x04` | STATUS | R | bit0 `busy`, bit1 `frameDone` | input status |
| `0x08` | MODE | R/W | bits[1:0]: bypass/gray/threshold | 0 |
| `0x0C` | THRESHOLD | R/W | bits[7:0] | 128 |
| `0x10` | BYPASS | R/W | bit0 | 1 |
| `0x14` | PERF_CTRL | R/W | write bit0=1 to clear all counters; reads as 0 | 0 |
| `0x18` | CYCLE_COUNT | R | SoC clocks since reset or clear | 0 |
| `0x1C` | INPUT_COUNT | R | accepted input beats | 0 |
| `0x20` | OUTPUT_COUNT | R | accepted output beats | 0 |
| `0x24` | FRAME_COUNT | R | accepted output beats carrying end-of-frame | 0 |
| `0x28` | STALL_COUNT | R | cycles with output valid and not ready | 0 |
| `0x2C` | BUSY_CYCLES | R | cycles with accelerator busy asserted | 0 |

All accesses are 32-bit little-endian CoreBus transactions with four byte strobes. Writes to read-only or unknown offsets return `error=1` and have no side effects.

Performance counters are unsigned 32-bit values and wrap naturally. `PERF_CTRL` clear takes priority over event accumulation in the same cycle.
