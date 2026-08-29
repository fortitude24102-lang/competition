# Software Validation Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and execute a bare-metal C accelerator-driver readback test on the existing RV32I SoC simulation.

**Architecture:** A tiny startup file and linker script run freestanding C from the 64 KiB boot RAM. MMIO primitives remain in one header, the accelerator driver owns all `0x3000_0000` constants, and an independent Chisel test loads the generated HEX and checks UART PASS, EBREAK, and final control outputs.

**Tech Stack:** C11 freestanding C, RV32I GNU toolchain, GNU assembler/linker, ChiselSim/ScalaTest

**Spec:** `docs/superpowers/specs/2026-08-29-software-validation-foundation-design.md`

## Global Constraints

- Compile with `-march=rv32i -mabi=ilp32 -ffreestanding -nostdlib`.
- Keep the existing assembly smoke test unchanged and add a separate C validation test.
- Do not implement UART RX, CLI, board download, serial baud generation, or visual validation.
- Do not put raw accelerator addresses outside the driver.
- Generated ELF/BIN/HEX files belong in ignored `sw/build/`.

---

### Task 1: Add the failing C software simulation test

**Files:**
- Create: `chisel/src/test/scala/soc/SoftwareDriverSpec.scala`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `SoCTop`, `sw/build/driver_test.hex`, UART byte stream, trap trace
- Produces: ScalaTest `soc.SoftwareDriverSpec` requiring UART `P`, EBREAK cause 3, enable 1, mode 2, threshold 128, bypass 0

- [x] **Step 1: Ignore generated software products**

Add `sw/build/` to `.gitignore`.

- [x] **Step 2: Write `SoftwareDriverSpec`**

Copy only the test harness pattern from `SoCTopSmokeSpec`. Load:

```scala
val ramImage = Paths.get("../sw/build/driver_test.hex").toAbsolutePath.toString
```

Drive video inactive, UART TX ready, and both external CoreBus responses as errors. Run up to 2000 cycles and require:

```scala
uartBytes shouldBe Vector(80)
trapCause shouldBe Some(3)
dut.io.accelEnable.expect(true)
dut.io.accelMode.expect(2)
dut.io.accelThreshold.expect(128)
dut.io.accelBypass.expect(false)
```

- [x] **Step 3: Run the focused test and confirm missing-image failure**

Run through the existing WSL/sbt environment:

```bash
sbt "testOnly soc.SoftwareDriverSpec"
```

Expected: FAIL because `sw/build/driver_test.hex` does not exist.

- [x] **Step 4: Commit the failing test**

```powershell
git add .gitignore chisel/src/test/scala/soc/SoftwareDriverSpec.scala
git commit -m "test(sw): specify C driver readback flow"
```

---

### Task 2: Implement MMIO and accelerator driver

**Files:**
- Create: `sw/bsp/mmio.h`
- Create: `sw/drivers/accel_driver.h`
- Create: `sw/drivers/accel_driver.c`

**Interfaces:**
- Consumes: frozen addresses from `docs/memory_map.md`
- Produces: `mmio_read32`, `mmio_write32`, `accel_set_enable`, `accel_set_mode`, `accel_set_threshold`, `accel_set_bypass`, `accel_get_status`, and readback getters

- [x] **Step 1: Add volatile 32-bit MMIO primitives**

`sw/bsp/mmio.h` must contain only:

```c
static inline void mmio_write32(uintptr_t address, uint32_t value) {
  *(volatile uint32_t *)address = value;
}

static inline uint32_t mmio_read32(uintptr_t address) {
  return *(volatile const uint32_t *)address;
}
```

- [x] **Step 2: Define the driver API and constants once**

In `accel_driver.h`, define base `0x30000000u`, offsets `0x00/0x04/0x08/0x0c/0x10`, and modes 0/1/2. Declare setters, `uint32_t accel_get_status(void)`, and readback getters for CTRL/MODE/THRESHOLD/BYPASS.

- [x] **Step 3: Implement direct driver operations**

Use `mmio_write32`/`mmio_read32`. `accel_set_mode(uint32_t mode)` returns `-1` for values greater than threshold mode and does not write; otherwise it writes and returns 0. Threshold accepts `uint8_t`; boolean controls write 0 or 1.

- [x] **Step 4: Compile the driver alone for RV32I**

Run:

```bash
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib \
  -I sw/bsp -I sw/drivers -c sw/drivers/accel_driver.c -o /tmp/accel_driver.o
```

Expected: exit code 0 and no implicit declaration or type warnings.

- [x] **Step 5: Commit the driver**

```powershell
git add sw/bsp/mmio.h sw/drivers/accel_driver.h sw/drivers/accel_driver.c
git commit -m "feat(sw): add accelerator MMIO driver"
```

---

### Task 3: Add freestanding C test image

**Files:**
- Create: `sw/start.S`
- Create: `sw/link.ld`
- Create: `sw/tests/driver_test.c`
- Create: `scripts/build-software-test.sh`
- Create: `scripts/build-software-test.ps1`

**Interfaces:**
- Consumes: Task 2 driver API, UART TXDATA `0x1000_0000`, UART STATUS `0x1000_0004`
- Produces: ignored `sw/build/driver_test.elf`, `.bin`, and `.hex`

- [ ] **Step 1: Add startup and linker layout**

`start.S` places `_start` in `.text.init`, loads `sp` from `_stack_top`, calls `main`, then executes EBREAK. `link.ld` maps text/rodata/data/bss into RAM at `0x0000_0000` with length 64 KiB and defines `_stack_top` at the RAM end.

- [ ] **Step 2: Write the automatic C readback test**

The test must:

```c
accel_set_enable(1);
ok &= accel_set_mode(ACCEL_MODE_THRESHOLD) == 0;
accel_set_threshold(128);
accel_set_bypass(0);
ok &= accel_set_mode(3) == -1;
ok &= accel_read_enable() == 1;
ok &= accel_read_mode() == ACCEL_MODE_THRESHOLD;
ok &= accel_read_threshold() == 128;
ok &= accel_read_bypass() == 0;
uart_putc(ok ? 'P' : 'F');
```

`uart_putc` polls STATUS bit 0 before writing TXDATA. `main` returns after exactly one report byte.

- [ ] **Step 3: Add reproducible build scripts**

The shell script derives `project_root`, uses `${RISCV_TOOLCHAIN_HOME:-/mnt/d/Chisel-environment/riscv-toolchain}`, creates `sw/build`, compiles with `-Os -Wall -Wextra -Werror -fno-builtin`, and converts ELF to BIN and little-endian word HEX. The PowerShell wrapper translates the current project path and invokes the shell script through Ubuntu WSL.

- [ ] **Step 4: Build and inspect the image**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-software-test.ps1
```

Expected: all three products exist and `driver_test.hex` is nonempty.

- [ ] **Step 5: Run the C software simulation test**

Run `testOnly soc.SoftwareDriverSpec` through the established WSL/sbt environment.

Expected: PASS with exactly UART `P` and EBREAK cause 3.

- [ ] **Step 6: Commit the executable software test**

```powershell
git add sw/start.S sw/link.ld sw/tests/driver_test.c scripts/build-software-test.sh scripts/build-software-test.ps1
git commit -m "test(sw): run C driver on the RV32I SoC"
```

---

### Task 4: Add software validation to the SoC gate

**Files:**
- Modify: `scripts/verify-soc.ps1`

**Interfaces:**
- Consumes: `scripts/build-software-test.ps1` and `soc.SoftwareDriverSpec`
- Produces: normal SoC verification rebuilding the C image before running ScalaTest

- [ ] **Step 1: Confirm the current gate does not build the C image**

Run `Select-String -Path scripts\verify-soc.ps1 -Pattern 'build-software-test'` and expect no match.

- [ ] **Step 2: Call the C build before Chisel tests**

Add:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'scripts\build-software-test.ps1')
Assert-LastExitCode 'C software validation image'
Write-Host '[PASS] C software validation image built'
```

- [ ] **Step 3: Run focused branch verification**

Run the C build and `testOnly soc.SoftwareDriverSpec`. Do not invoke Vivado for this branch-only check.

- [ ] **Step 4: Check the handwritten diff and commit**

```powershell
git diff --check -- .gitignore chisel/src/test/scala/soc/SoftwareDriverSpec.scala sw scripts/build-software-test.sh scripts/build-software-test.ps1 scripts/verify-soc.ps1
git add scripts/verify-soc.ps1
git commit -m "build(sw): include C validation in SoC gate"
```

---

### Task 5: Branch verification

**Files:**
- Verify only

**Interfaces:**
- Consumes: Tasks 1-4
- Produces: a clean, independently reviewable software branch

- [ ] **Step 1: Confirm branch isolation and products**

Run:

```powershell
git status --short --branch
git log --oneline -5
```

Expected: branch `codex/software-validation-foundation`, clean worktree, no `tb/tb_video_accel_top.sv`, and ignored `sw/build` products.
