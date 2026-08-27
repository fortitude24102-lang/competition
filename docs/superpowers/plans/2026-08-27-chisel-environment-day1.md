# Chisel Environment and Day 0-1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a reproducible Chisel toolchain under `D:\Chisel-environment` and generate a Vivado-readable `generated/Blink.sv` from the minimal project in `D:\ZYNQ\smallproject`.

**Architecture:** Portable JDK and sbt run directly on Windows. MSYS2 UCRT64 supplies Verilator without WSL or Docker. A project PowerShell script configures the current shell, while persistent user variables make the same tools available in fresh terminals.

**Tech Stack:** Eclipse Temurin JDK 17, sbt 1.12.4, Scala 2.13.18, Chisel 7.7.0, firtool 1.139.0, MSYS2 UCRT64, Verilator 5.050, Vivado 2019.2, PowerShell, Git

**Spec:** `docs/superpowers/specs/2026-08-27-chisel-environment-day1-design.md`

## Global Constraints

- Store installed tools and dependency caches below `D:\Chisel-environment`.
- Store source and generated RTL below `D:\ZYNQ\smallproject`.
- Reuse Vivado 2019.2; do not copy or upgrade it.
- Pin Scala 2.13.18, Chisel 7.7.0, and sbt 1.12.4.
- Pin firtool 1.139.0 and select it with `CHISEL_FIRTOOL_PATH` so Chisel does not cache it outside D:.
- Use persistent user environment variables; do not require administrator access.
- Stop at Day 0-1: no CPU, bus, memory map, accelerator registers, or video RTL.

---

### Task 1: Portable toolchain and shell environment

**Files:**
- Create: `scripts/chisel-env.ps1`
- Create: `scripts/verify-day1.ps1`
- Create: `docs/chisel_env.md`

**Interfaces:**
- Consumes: official JDK 17, sbt 1.12.4, and MSYS2 archives
- Produces: `CHISEL_ENV_HOME`, `JAVA_HOME`, cache variables, and a current-process `PATH` containing Java, sbt, MSYS2 UCRT64, and Verilator

- [ ] **Step 1: Write and run the failing Day 0-1 verification**

Create `scripts/verify-day1.ps1` as an end-to-end check that loads `chisel-env.ps1`, confirms required commands, regenerates `Blink.sv`, checks its top-level contract, and runs Verilator lint. Run it before implementation:

```powershell
.\scripts\verify-day1.ps1
```

Expected: FAIL because `scripts/chisel-env.ps1` and the toolchain do not exist yet.

- [ ] **Step 2: Download and unpack the portable tools**

Create `D:\Chisel-environment\downloads`, then download:

```text
https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse
https://github.com/sbt/sbt/releases/download/v1.12.4/sbt-1.12.4.zip
https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe
https://github.com/llvm/circt/releases/download/firtool-1.139.0/firrtl-bin-windows-x64.zip
```

Unpack JDK to `D:\Chisel-environment\jdk-17`, sbt to `D:\Chisel-environment\sbt`, MSYS2 to `D:\Chisel-environment\msys64`, and firtool to `D:\Chisel-environment\firtool-1.139.0`.

- [ ] **Step 3: Install Verilator inside MSYS2 UCRT64**

Initialize MSYS2, update it twice as recommended by MSYS2, and install:

```text
mingw-w64-ucrt-x86_64-verilator
```

Expected: `D:\Chisel-environment\msys64\ucrt64\bin\verilator.exe` or the package's Verilator launcher exists and reports version 5.050.

- [ ] **Step 4: Write the project shell script**

Create `scripts/chisel-env.ps1` with these responsibilities:

```powershell
$env:CHISEL_ENV_HOME = 'D:\Chisel-environment'
$env:JAVA_HOME = Join-Path $env:CHISEL_ENV_HOME 'jdk-17'
$env:COURSIER_CACHE = Join-Path $env:CHISEL_ENV_HOME 'cache\coursier'
$env:SBT_BOOT_DIRECTORY = Join-Path $env:CHISEL_ENV_HOME 'cache\sbt\boot'
$env:SBT_GLOBAL_BASE = Join-Path $env:CHISEL_ENV_HOME 'cache\sbt\global'
$env:SBT_IVY_HOME = Join-Path $env:CHISEL_ENV_HOME 'cache\ivy'
$env:VERILATOR_ROOT = Join-Path $env:CHISEL_ENV_HOME 'msys64\ucrt64\share\verilator'

$toolPaths = @(
    (Join-Path $env:JAVA_HOME 'bin'),
    (Join-Path $env:CHISEL_ENV_HOME 'sbt\bin'),
    (Join-Path $env:CHISEL_ENV_HOME 'msys64\ucrt64\bin'),
    (Join-Path $env:CHISEL_ENV_HOME 'msys64\usr\bin')
)
$env:Path = (($toolPaths + ($env:Path -split ';')) | Select-Object -Unique) -join ';'
```

Fail immediately if any required tool directory is absent. Do not configure aliases or unrelated shell preferences.

- [ ] **Step 5: Persist the user environment**

Set user-scoped `CHISEL_ENV_HOME`, `JAVA_HOME`, `COURSIER_CACHE`, `SBT_BOOT_DIRECTORY`, `SBT_GLOBAL_BASE`, `SBT_IVY_HOME`, and `VERILATOR_ROOT`. Prepend the four tool directories from Step 4 to the user `Path`, removing duplicates before saving.

- [ ] **Step 6: Verify a fresh process**

Run:

```powershell
powershell -NoProfile -Command ". 'D:\ZYNQ\smallproject\scripts\chisel-env.ps1'; java -version; sbt --version; verilator --version; git --version; vivado -version"
```

Expected: JDK 17, sbt 1.12.4 project runner availability, Verilator 5.050, Git, and Vivado 2019.2 are all visible.

- [ ] **Step 7: Document and commit the environment**

Write `docs/chisel_env.md` with the installed versions, tool locations, fresh-shell command, cache locations, and the rule that tools are updated only deliberately.

```powershell
git add scripts/chisel-env.ps1 docs/chisel_env.md
git commit -m "build: add local Chisel toolchain environment"
```

---

### Task 2: Minimal Chisel project and Blink RTL generation

**Files:**
- Create: `chisel/build.sbt`
- Create: `chisel/project/build.properties`
- Create: `chisel/src/main/scala/Blink.scala`
- Create: `chisel/src/main/scala/Generate.scala`
- Create: `generated/Blink.sv`

**Interfaces:**
- Consumes: Java and sbt exposed by `scripts/chisel-env.ps1`
- Produces: top module `Blink` with implicit `clock`, `reset`, and `io_led` output; generator entry point `Generate`

- [ ] **Step 1: Write the pinned build files**

`chisel/build.sbt` contains only the Chisel library and matching compiler plugin:

```scala
ThisBuild / scalaVersion := "2.13.18"

val chiselVersion = "7.7.0"

lazy val root = (project in file("."))
  .settings(
    name := "smallproject-chisel",
    libraryDependencies += "org.chipsalliance" %% "chisel" % chiselVersion,
    addCompilerPlugin("org.chipsalliance" % "chisel-plugin" % chiselVersion cross CrossVersion.full)
  )
```

`chisel/project/build.properties` contains:

```properties
sbt.version=1.12.4
```

- [ ] **Step 2: Write the minimal Blink hardware**

`chisel/src/main/scala/Blink.scala` contains:

```scala
import chisel3._

class Blink extends Module {
  val io = IO(new Bundle {
    val led = Output(Bool())
  })

  val counter = RegInit(0.U(24.W))
  counter := counter + 1.U
  io.led := counter(23)
}
```

- [ ] **Step 3: Write the generator entry point**

`chisel/src/main/scala/Generate.scala` contains:

```scala
import circt.stage.ChiselStage

object Generate extends App {
  ChiselStage.emitSystemVerilogFile(new Blink, args)
}
```

- [ ] **Step 4: Run the first generation check**

Run from `chisel/`:

```powershell
. ..\scripts\chisel-env.ps1
sbt "runMain Generate --target-dir ../generated"
```

Expected: exit code 0 and a non-empty `generated/Blink.sv` containing `module Blink`.

- [ ] **Step 5: Verify reproducibility**

Delete only `generated/Blink.sv`, rerun Step 4, and check:

```powershell
Select-String -Path ..\generated\Blink.sv -Pattern 'module Blink','input.*clock','input.*reset','output.*io_led'
```

Expected: all four patterns match.

- [ ] **Step 6: Run a Verilator lint check**

From the project root:

```powershell
. .\scripts\chisel-env.ps1
verilator --lint-only --top-module Blink generated\Blink.sv
```

Expected: exit code 0.

- [ ] **Step 7: Run the Vivado 2019.2 syntax/elaboration check**

Use Vivado batch mode with an in-memory project that reads `generated/Blink.sv`, sets `Blink` as top, and runs RTL elaboration. Do not create a persistent Vivado project.

Expected: no syntax error. If Vivado 2019.2 rejects a construct emitted by firtool, capture the exact error and adjust only the emitter options required for compatibility.

- [ ] **Step 8: Commit the minimal project**

```powershell
git add chisel generated/Blink.sv
git commit -m "feat(chisel): generate minimal Blink RTL"
```

---

### Task 3: Final Day 0-1 verification and documentation

**Files:**
- Modify: `docs/chisel_env.md`

**Interfaces:**
- Consumes: the installed toolchain and committed Chisel project
- Produces: a reproducible Day 0-1 handoff from a fresh PowerShell process

- [ ] **Step 1: Run the full fresh-process verification**

Start a fresh PowerShell process, load `scripts/chisel-env.ps1`, print all tool versions, regenerate `Blink.sv`, and rerun Verilator lint.

Expected: every command exits 0 without relying on the old terminal state.

- [ ] **Step 2: Confirm caches and artifacts stay on D:**

Check that `COURSIER_CACHE`, `SBT_BOOT_DIRECTORY`, `SBT_GLOBAL_BASE`, and `SBT_IVY_HOME` resolve below `D:\Chisel-environment`, and that `Blink.sv` resolves below `D:\ZYNQ\smallproject\generated`.

- [ ] **Step 3: Update exact observed versions and commands**

Replace any planned version wording in `docs/chisel_env.md` with the versions printed by the successful verification. Include the Vivado result and any compatibility option actually needed.

- [ ] **Step 4: Commit the verified handoff**

```powershell
git add docs/chisel_env.md
git commit -m "docs(chisel): record reproducible Day 0-1 setup"
```
