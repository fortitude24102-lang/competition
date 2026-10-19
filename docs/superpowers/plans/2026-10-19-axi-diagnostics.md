# AXI等待分解 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans in this session. Steps use checkbox syntax for tracking.

**Goal:** 实测背景和Key的总线等待，选择有依据的下一项GPU优化，不将诊断当提速。
**Architecture:** 候选仲裁器输出16个Render事件，独立APB诊断页计数；原握手/准入/写退休不改变。
**Tech Stack:** 现有Chisel、Scala测试、C、PowerShell；不新增依赖。
**Spec:** docs/superpowers/specs/2026-10-19-axi-diagnostics-design.md

## Global Constraints

- 官方Sapphire、CPU基础绘图、100MHz、DDR、HDMI、网口、灰度/缩放、原命令和资格规则不改。
- `enableAxiDiagnostics=false`，新APB页0x0600和STATUS bit19仅候选存在；C命令32字节不变。
- 只JTAG/RAM，不写Flash、不推送、不替换release；板卡与最终时序未就绪不加载。
- 计数模2^32，阶段小于42秒；不同通道不相加，B尾等待不直接当收益。

## Review Focus

- 显示或Asset事务不得混入Render计数。
- R无数据、B未返回必须计数，即使没有VALID背压。
- 非法CONTROL/只读写入不得启停或清零。
- Top候选响应级不能重复消费APB CONTROL，旧构建不能宣布新能力。
- 诊断固件必须停止后读取，阶段错误和下溢不可忽略。

### Task 1: 诊断事件与候选APB页

**Files:** 新AxiDiagnosticRegs.scala与AxiDiagnosticsSpec.scala；修改DdrQosArbiter.scala、GpuApbRegs.scala、Efinix2dGpuTop.scala、GenerateEfinix2dGpu.scala、scripts/test-v3-gpu.ps1。
**Interfaces:** DdrQosArbiter尾参`enableDiagnostics:Boolean=false`，`io.diagnostics:Option[Vec[Bool]]`16项；AxiDiagnosticRegs输入`events:Vec[Bool](16)`与ApbSlavePort；Top尾参`enableAxiDiagnostics:Boolean=false`。

- [x] 写AxiDiagnosticsSpec：CONTROL3清零启用；literal事件0/3/7脉冲分别2/5/3；CONTROL0后不增长；非法CONTROL4与只读写报错且计数/启停不变；仲裁器实际Render W/B延迟及R缺数事件，Scanout/Asset排除。先运行看到缺少类/接口的RED。
- [x] 实现页ID0x41585046、CONTROL0x0604、计数0x0610..0x064c，按Spec事件连线。Top诊断候选状态声明bit19、路由新页，默认不实例化。生成`--axi-diagnostics`，脚本`-AxiDiagnostics`必须Generate并使用独立新RTL路径。
- [x] 定向`gpu.AxiDiagnosticsSpec gpu.DdrQosArbiterSpec`共11项通过；Top候选APB读ID/能力/清零、默认无能力在同套覆盖。只作本地提交。

### Task 2: 阶段固件与实板选择门

**Files:** 修改sw/efinix_gpu/tests/test_board_sprite_phases.c、scripts/build-board-hud-dma-test.ps1；新增本轮evidence README，更新主README。
**Interfaces:** `-Test axi-phases -OutDirectory <全新>`生成`GPU_AXI_DIAGNOSTICS=1`固件，只有STATUS bit19存在时访问0x0600；输出`AXI_PHASE`含16项。原sprite-phases目标保持旧诊断工作量。

- [x] 原未知AxiDiagnostics被非advanced脚本静默忽略，首BIN隔离未加载；改用ValidateSet axi-phases，RED确实拒绝，加入独立目标后RV32固件构建通过；不修改原保存测量BIN。
- [ ] 最终GPU全套一次；受影响软件检查及生成一文件一模块RTL；综合检查全部16项最终时序关系。时序失败只修诊断实现或保持离线，不加载不合格位流。
- [ ] 板卡就绪时JTAG加载诊断候选；沿用原24阶段与CRC/数量/有效字节核对，零新增下溢/硬件错误；读取16项并明确总线拍与有效字节区别。对照旧同场景耗时，说明诊断开销边界。
- [ ] 记录选择结论及下一项设计：先比较Key/BG的B尾等待、W供应空拍、R供应/显示准入，而非先写双在途。恢复已验证双飞机Zoom BIT/BIN，关闭采集/烧录；本地提交证据，不推送。
