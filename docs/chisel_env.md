# Chisel 环境说明

## 已安装版本

| 工具 | 版本 | 位置 |
| --- | --- | --- |
| Java | Temurin 17.0.20.1+1 | `D:\Chisel-environment\jdk-17` |
| sbt runner | 1.12.4 | `D:\Chisel-environment\sbt` |
| Scala | 2.13.18（由工程锁定） | `chisel/build.sbt` |
| Chisel | 7.7.0（由工程锁定） | `chisel/build.sbt` |
| firtool | 1.139.0 | `D:\Chisel-environment\firtool-1.139.0` |
| Verilator | 5.050 | `D:\Chisel-environment\msys64` |
| Vivado | 2019.2 | `D:\visit\Vivado\2019.2` |
| Git | 2.55.0.windows.3 | 系统现有安装 |

## 每次使用

在 PowerShell 中进入工程并加载环境：

```powershell
cd D:\ZYNQ\smallproject
. .\scripts\chisel-env.ps1
```

环境路径已写入当前用户的持久化环境变量；重新打开终端或 Codex 后可以直接找到工具。加载脚本仍是推荐方式，因为它同时固定 sbt、Ivy 和 Coursier 缓存位置。

## 生成 RTL

```powershell
cd D:\ZYNQ\smallproject\chisel
. ..\scripts\chisel-env.ps1
sbt "runMain Generate --target-dir ../generated"
```

不要手工修改 `generated/Blink.sv`。需要改动时修改 Scala 源码并重新生成。

## 验证

```powershell
cd D:\ZYNQ\smallproject
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-day1.ps1
```

验证脚本会重新生成 `Blink.sv`、检查顶层端口、运行 Verilator lint，并用 Vivado 2019.2 针对 `xc7z015clg485-2` 做内存工程 RTL elaboration。

已验证结果：Chisel 生成成功，Verilator lint 通过，Vivado RTL elaboration 为 0 Warnings、0 Critical Warnings、0 Errors。

## 缓存位置

- Coursier：`D:\Chisel-environment\cache\coursier`
- sbt boot：`D:\Chisel-environment\cache\sbt\boot`
- sbt global：`D:\Chisel-environment\cache\sbt\global`
- Ivy：`D:\Chisel-environment\cache\ivy`

## 注意事项

- 不要在两周 Demo 中途升级 Java、sbt、Chisel、firtool 或 Verilator。
- Chisel 7.7.0 使用 firtool 1.139.0；`CHISEL_FIRTOOL_PATH` 已固定到 D 盘，避免自动缓存到用户目录。
- MSYS2 的 Verilator 包需要 `libwinpthread`；当前环境已经安装，并通过 `D:\Chisel-environment\bin\verilator.cmd` 提供 Windows 命令入口。
- Vivado 沿用现有 2019.2 安装，不复制、不升级。
