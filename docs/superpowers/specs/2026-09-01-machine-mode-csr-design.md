# RV32 Machine-Mode CSR and Interrupt Design

## Goal

Replace the SoC configuration's permanent halt on every exception with a small, precise machine-mode trap path. The core implements the Zicsr instruction subset needed by bare-metal firmware, direct-mode `mtvec`, `MRET`, machine timer interrupts, and the core machine CSRs required by a trap handler.

The implementation follows the official RISC-V Zicsr 2.0 instruction semantics and the machine-level privileged architecture:

- <https://docs.riscv.org/reference/isa/unpriv/zicsr.html>
- <https://docs.riscv.org/reference/isa/priv/machine.html>
- <https://docs.riscv.org/reference/isa/priv/priv-csrs.html>

## Compatibility Modes

`Rv32Core` has two elaboration parameters:

- `enableMachineMode` defaults to `true`. When true, synchronous exceptions redirect to `mtvec` and timer interrupts are accepted.
- `haltOnEbreak` defaults to `true`. This keeps EBREAK as the deterministic simulation/program-completion mechanism used by the existing tests. A compliance configuration can set it to `false` so breakpoint exceptions enter `mtvec`.

The legacy precise-trap regression explicitly sets `enableMachineMode=false`; this preserves its original permanent-halt checks without weakening the default generated CPU.

## Implemented CSRs

| Address | CSR | Behavior |
|---:|---|---|
| `0x300` | `mstatus` | MIE bit 3, MPIE bit 7; MPP reads as Machine mode |
| `0x301` | `misa` | Read-only RV32I value `0x4000_0100` |
| `0x304` | `mie` | MTIE bit 7 writable |
| `0x305` | `mtvec` | Direct mode only; low two bits read as zero |
| `0x340` | `mscratch` | Full 32-bit read/write |
| `0x341` | `mepc` | Read/write with low two bits forced to zero |
| `0x342` | `mcause` | Full 32-bit read/write; interrupt flag is bit 31 |
| `0x343` | `mtval` | Full 32-bit read/write |
| `0x344` | `mip` | MTIP bit 7 reflects the machine timer input; writes have no effect |
| `0xF14` | `mhartid` | Read-only zero |

Unsupported CSR addresses and attempted writes to read-only CSRs raise an illegal-instruction exception. CSRRS/CSRRC and their immediate forms do not attempt a write when the encoded source field is zero, even if a register happens to contain zero.

## CSR Instructions

The decoder recognizes `CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, and `CSRRCI`. The old CSR value is the integer destination result. Register forms use the normal EX-stage forwarding network; immediate forms zero-extend the encoded five-bit source.

CSR reads, legality checks, and the new value calculation occur in EX. A CSR write occurs only when that instruction advances out of EX and no older synchronous trap wins. This makes back-to-back CSR instructions observe program order while preventing a younger CSR from modifying state ahead of an older failing memory operation.

## Trap Entry and Return

For a synchronous exception, the MEM-stage trap event has priority over interrupts and redirects. Trap entry writes:

- `mepc` = faulting instruction PC;
- `mcause` = exception cause;
- `mtval` = bad address, bad instruction bits, or zero as appropriate;
- `mstatus.MPIE` = previous `mstatus.MIE`;
- `mstatus.MIE` = zero.

The direct trap target is `mtvec & ~3`.

`MRET` redirects to `mepc`, restores MIE from MPIE, and sets MPIE to one. Only M-mode is implemented, so MPP reads as Machine mode.

EBREAK follows the `haltOnEbreak` elaboration parameter. Trap trace reporting remains active for both redirected traps and the debug-halt path.

## Timer Interrupt Precision

An interrupt is eligible when all three conditions hold:

- the external machine timer line is asserted;
- `mie.MTIE` is one;
- `mstatus.MIE` is one.

Synchronous exceptions have priority. When a timer interrupt is accepted after the current MEM-stage instruction completes, that instruction is allowed to flow into WB, younger EX/ID/fetch state is flushed, and `mepc` records the oldest flushed instruction PC. `mcause` becomes `0x8000_0007` and `mtval` becomes zero. This preserves precise architectural state without adding an interrupt signal to the core's longest ALU/data-memory path.

## Trap Values

| Cause | `mtval` |
|---|---|
| Instruction address misaligned | bad target address |
| Instruction access fault | faulting PC |
| Illegal instruction | instruction bits |
| Breakpoint / ECALL | zero |
| Load/store address misaligned | effective address |
| Load/store access fault | effective address |
| Machine timer interrupt | zero |

## Out of Scope

- User or supervisor modes, delegation, PMP, virtual memory, NMI, AIA, vectored `mtvec`, software interrupts, external interrupts, and debug mode.
- `mcycle/minstret` CSRs; CoreMark uses the already implemented 64-bit MMIO machine timer.
- Changing the five-stage structure or adding a new combinational path through the external CoreBus.
