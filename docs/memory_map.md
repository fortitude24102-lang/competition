# SoC Memory Map

The address map is frozen for the Demo. Unlisted addresses return a bus error and never alias another target.

| Region | Address range | Access | Reset/use |
|---|---:|---|---|
| Boot RAM | `0x0000_0000`–`0x0000_FFFF` | R/W, instruction read | 64 KiB program and data memory |
| UART | `0x1000_0000`–`0x1000_0FFF` | MMIO | Transmit-byte interface |
| Accelerator | `0x3000_0000`–`0x3000_0FFF` | MMIO | Video control and status |
| External memory | `0x8000_0000`–`0xFFFF_FFFF` | R/W | Reserved CoreBus window for a future AXI bridge |

## UART registers

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | TXDATA | W | Low 8 bits enqueue one byte |
| `0x04` | STATUS | R | bit0 `txReady` |

## Accelerator registers

| Offset | Name | Access | Definition | Reset |
|---:|---|---|---|---:|
| `0x00` | CTRL | R/W | bit0 `enable` | 0 |
| `0x04` | STATUS | R | bit0 `busy`, bit1 `frameDone` | input status |
| `0x08` | MODE | R/W | bits[1:0]: bypass/gray/threshold | 0 |
| `0x0C` | THRESHOLD | R/W | bits[7:0] | 128 |
| `0x10` | BYPASS | R/W | bit0 | 1 |

All accesses are 32-bit little-endian CoreBus transactions with four byte strobes. Writes to read-only or unknown offsets return `error=1` and have no side effects.
