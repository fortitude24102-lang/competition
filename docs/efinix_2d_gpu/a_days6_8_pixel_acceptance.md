# A：Day6～8 PixelPipe 离线验收

验收日期：2026-09-08。范围只包含 Copy/Fill RTL、反压和独立 Chisel 黑盒；没有板卡，不代表 HDMI 实显或 GPU/DDR 端到端联通。

## 冻结接口

顶层模块 `gpu_pixel_pipe`（文件同名），每个自写 `.v` 只有一个 module，`gpu_pixel_contract.vh` 只放常量宏。

| 端口 | 方向/宽度 | 合同 |
|---|---|---|
| clock | 输入 1 | 上升沿采样 |
| reset | 输入 1 | 同步、高有效；清空在途事务，清零 out_valid/result_pixel/write_enable |
| in_valid / in_ready | 输入/输出，各1 | 高有效；上升沿同时为1接收事务；reset期间in_ready为0 |
| op | 输入3 | 1=FILL，2=COPY；0、3～7当前不支持 |
| foreground / background | 输入，各16 | RGB565前景/背景；当前background保留不用 |
| fill_color / color_key | 输入，各16 | RGB565填充色/透明键；当前color_key保留不用 |
| alpha | 输入8 | 当前保留不用 |
| out_valid / out_ready | 输出/输入，各1 | 高有效；上升沿同时为1提交输出 |
| result_pixel | 输出16 | COPY前景直通，FILL填充色；不支持op输出0 |
| write_enable | 输出1 | 有效COPY/FILL事务为1，不支持op为0；写回必须同时满足out_valid && out_ready && write_enable |

`gpu_pixel_copy`、`gpu_pixel_fill` 是组合数据助手，统一由 `gpu_pixel_pipe` 管理 valid/ready。单级弹性寄存器在输入接收沿之后给出有效结果，最早下一上升沿输出握手；无反压时延迟1周期、连续吞吐1像素/周期，可同拍取出旧输出并装入新输入。输出反压期间valid、像素、write_enable都保持，复位可丢弃尚未提交的事务。没有时钟频率或板级时序收敛承诺。

Chisel `PixelPipeExt` 对应上述平坦端口，加载真实 `.v/.vh`；`PixelPipeHarness` 用既有 `PixelTransaction`/`PixelResult` 的 Decoupled 接口作独立接入适配。未修改或接入 `Efinix2dGpuTop`，未修改用户的 `PixelReadAligner.scala`、`RenderEngineSpec.scala` 草稿。

## 可复现命令与实际结果

在项目根目录 PowerShell 运行：

```powershell
./scripts/test-efinix-verilog.ps1
./scripts/test-efinix-pixel-chisel.ps1
```

两项最后运行均退出0，WSL Ubuntu/Verilator离线执行：

- vendor SHA256 manifest通过。
- RGB565全部65536输入通过。
- HDMI真实vendor encoder回归通过（控制符、三原色、256样本、复位/反相/IO控制），这只是仿真。
- 所有 `board/efinix_ti60/rtl/**/*.v` 每文件一个module结构检查通过。
- PixelPipe：10000笔有序事务，9915个输出stall周期，总25824周期。覆盖全部8种op、随机valid/ready、像素/写使能稳定、无丢失/重复/乱序、排空无额外输出、复位清空在途事务；前32个连续周期断言输入32/输出31，检验1周期延迟和每周期吞吐。
- `testOnly gpu.PixelPipeExtSpec`：1项测试通过，真实黑盒COPY输出F800、FILL输出07E0、非法ALPHA输出0且不写回，各自反压3周期保持。没有使用Scala参考模型代替RTL。

## TDD记录

先写SystemVerilog测试，首次编译确认缺少 `gpu_pixel_pipe`。加入只声明端口、始终不产生输出的空功能模块后，实际运行测试在 `lost transactions or no stalls` 断言失败；随后实现单级弹性Copy/Fill并得到上述绿色结果。Chisel测试先写，运行因缺少 `PixelPipeHarness` 编译失败，接入真实ExtModule后仿真通过（此项最初是缺失类型失败，不声称是功能断言红灯）。

开发过程中修复过脚本CRLF导致的启动器退出127；最终两项入口均退出0。没有新增宽泛Verilator告警屏蔽；现有vendor局部屏蔽保留。

## 文件

- `board/efinix_ti60/rtl/pixel/gpu_pixel_copy.v`
- `board/efinix_ti60/rtl/pixel/gpu_pixel_fill.v`
- `board/efinix_ti60/rtl/pixel/gpu_pixel_pipe.v`
- `board/efinix_ti60/rtl/pixel/gpu_pixel_contract.vh`
- `tb/verilog/tb_gpu_pixel_pipe.sv`
- `chisel/src/main/scala/gpu/PixelPipeExt.scala`
- `chisel/src/test/scala/gpu/PixelPipeExtSpec.scala`
- `scripts/test-efinix-verilog.sh`（更新，现有PowerShell入口继续使用）
- `scripts/test-efinix-pixel-chisel.ps1`
- 本文档

本文记录的 Day6～8 时点尚未实现 COLOR_KEY、ALPHA、SPARSE 和 PRESENT；后续 Day14～15 已完成 PRESENT 与 COLOR_KEY，ALPHA 和 SPARSE 仍按原计划推进。
