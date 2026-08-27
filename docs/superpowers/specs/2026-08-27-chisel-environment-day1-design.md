# Chisel portable environment and Day 0-1 design

## Goal

Prepare a reproducible Windows Chisel environment and complete only the Day 0-1 deliverables from the corrected member-1 task document. The environment lives under `D:\Chisel-environment`; the source project lives under `D:\ZYNQ\smallproject`.

## Environment

- JDK: Eclipse Temurin 17 LTS, unpacked below the environment directory.
- Build tool: sbt 1.12.4, matching the selected official Chisel template.
- Chisel project: Scala 2.13.18 and Chisel 7.7.0, pinned in project files.
- Simulation tool: MSYS2 UCRT64 with its packaged Verilator 5.050.
- FPGA tool: reuse the installed Vivado 2019.2; do not copy or upgrade it.

Persistent user environment variables set `CHISEL_ENV_HOME`, `JAVA_HOME`, tool paths, and dependency-cache paths to locations below `D:\Chisel-environment`. Machine-wide variables are unnecessary. No Chisel dependency, generated RTL, or project source is stored outside the two stated directories.

## Project scope

The first implementation creates:

- `chisel/build.sbt` and `chisel/project/build.properties`;
- `chisel/src/main/scala/Blink.scala`;
- `chisel/src/main/scala/Generate.scala`;
- `generated/Blink.sv` produced by the generator;
- `scripts/chisel-env.ps1` for a repeatable project shell;
- `docs/chisel_env.md` containing versions, commands, and recovery notes.

The implementation does not add a CPU, bus, memory map, accelerator registers, video RTL, or speculative framework code.

## Flow

`scripts/chisel-env.ps1` resolves `D:\Chisel-environment`, configures the current process, and exposes Java, sbt, MSYS2 UCRT64, Verilator, Git, and Vivado. The Chisel project emits SystemVerilog into `generated/`. Generated RTL is treated as a build artifact and is never hand-edited.

## Verification

1. Print versions for Java, sbt, Verilator, Git, and Vivado.
2. Run the Chisel generator twice and confirm both runs produce non-empty `generated/Blink.sv`.
3. Confirm the generated module exposes the expected clock, reset, and output ports.
4. Ask Vivado 2019.2 to read/elaborate or syntax-check the generated SystemVerilog when its batch flow supports the generated syntax.
5. Start a fresh PowerShell process, load the environment script, and repeat the generation command.

## Failure handling

- Dependency downloads remain cached under `D:\Chisel-environment` where the tool supports an explicit cache location.
- If native Verilator integration fails, fix the MSYS2 UCRT64 invocation; do not introduce WSL, Docker, or another simulator during Day 0-1.
- If Vivado 2019.2 rejects syntax emitted by current Chisel/firtool, record the exact incompatibility before changing Chisel or emission options.
