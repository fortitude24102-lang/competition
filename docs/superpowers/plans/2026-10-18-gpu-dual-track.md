# GPU双线首轮 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 交付可回退的缓存Key裁剪和可选硬件缩放/镜像，不混入后续功能。
**Architecture:** 两个独立模块共享旧命令/DDR框架；性能线只改缓存Key，功能线独立引擎，顶层由负责人集成。新路径默认关闭。
**Tech Stack:** Chisel/Scala、现有Verilog像素/BSP、C、WSL现有sbt和标准库测试；不新增依赖。
**Spec:** docs/efinix_2d_gpu/gpu_dual_track_20261018.md

## Global Constraints

- 官方Sapphire、100MHz、DDR、HDMI、以太网与CPU基础渲染保持不变。
- 原命令0..6兼容；新硬件默认关闭、能力位检测、显式生成开关。
- 不写Flash、不推送main、不覆盖release或旧实测证据；无就绪板卡只离线。
- 手工.v一个模块；生成split-verilog；所有编辑apply_patch。

## Review Focus

- 空透明行无AW，但处理像素计数不减少。
- 已承诺W在晚到R/B错误时仍完成，后续行不再发起。
- Transform独立源/输出尺寸、残差DDA、半字相位、64位范围及镜像顺序一致。
- 老BIT与默认关闭模块拒绝新命令；原命令/flags处理不倒退。
- 重复命令、完成背压、PRESENT前事务退休，不能只测单个成功像素。

### Task 1: 缓存Key裁剪

**Files:** CachedKeyStream.scala、DenseBlitEngine.scala、CachedKeyStreamSpec.scala和新的KeyRowTrimSpec.scala。
**Interfaces:** CachedKeyStream新增`trimTransparentRows: Boolean=false`；Dense新增尾参数`enableKeyRowTrim:Boolean=false`。保持现有IO布局，wordPixelsDone在内部处理所有对齐字时计数，Dense对应流的计数门控须匹配；不影响其他路径。

- [x] 写全透明行AW=0、首尾裁剪W拍降低、半字相位像素/哨兵测试，先看旧实现失败。
- [x] 完整行缓存与首末范围判断，AW前预留完整W；保持旧路径。
- [x] 补暂停、多个命令、错误和源排空验证，运行定向套件。
- [x] 提交仅负责文件；交付RED/GREEN日志和处理像素统计证据，不声称板测加速。

### Task 2: Transform引擎与ABI

**Files:** 新TransformBlitEngine.scala、GpuTypes.scala、CommandValidator.scala；新增TransformBlitSpec.scala/TransformValidatorSpec.scala。
**Interfaces:** 新引擎command/completion与AXI口遵循扩展GpuCommand（尾部srcWidthPixels/srcHeightPixels）；输出pixelDone脉冲。opcode7、flags Mask19、任意最近邻DDA映射/error10遵循Spec；validator新增尾参数`enableTransformBlit:Boolean=false`。旧模板/实例格式不变；内部字段默认0。

- [x] 写非对称像素、非整数放大/缩小/HV翻转/Key及边界测试，先RED。
- [x] 用已有AxiReadEngine/AxiWriteEngine有序实现，不做通用除法、不新增依赖。
- [x] 对R/B错误、随机背压、完成/tag顺序、非法输入无AXI运行定向验证。
- [x] 提交仅负责文件并报告证据；默认关闭必须保留op7拒绝。

### Task 3: 顶层、驱动与生成集成

**Files:** RenderEngine.scala、Efinix2dGpuTop.scala、GpuApbRegs.scala、GenerateEfinix2dGpu.scala、scripts/test-v3-gpu.ps1；gpu.h/gpu.c/gpu_regs.h及独立C测试/板端功能诊断。
**Interfaces:** 顶层尾参数enableKeyRowTrim/enableTransformBlit；生成`--key-row-trim`/`--transform-blit`；STATUS bit17、TransformSourceSize0x00a8。`gpu_transform_blit_async(d,src,dst,src_stride,dst_stride,src_w,src_h,out_w,out_h,flags,key,tag)`仅通过新命令，能力缺失拒绝；原接口/CPU路径不变。

- [x] 先写集成完成顺序、能力位与C参数/MMIO行为测试，RED后再接线。
- [x] 互斥路由新引擎，PRESENT等待全部完成，保持旧计数/纹理/前端接口；生成开关默认关闭。
- [x] 增加独立功能板测固件入口，不改生产游戏BIN；定向测试通过后生成新目录RTL，全套回归与综合并行。
- [x] GPU全套一次29套/114项，113通过、1旧测试断言更新后仅定向4/4；最终C32软件全回归通过。独立审查无Important/Critical。

### Task 4: 资源/板测门槛与收尾

**Files:** 本设计文档的进度/证据节、README；候选日志/RTL仅generated新目录。
**Interfaces:** 接收前三项绿色测试及候选hash；正式默认和release保持不变。

- [x] 生成仅KeyTrim、联合及只开Transform三个配置，split-verilog；仅裁剪时序失败禁止加载，另两配置时序通过。
- [x] 检查真实USB/JTAG后，只JTAG执行像素oracle及同场景测量。按用户新增板键交互要求，最终保留独立Zoom演示供确认，不冒称恢复MENU；无Flash写入。
- [x] 同BIN裁剪联合候选无净收益，裁剪保持关闭；最终功能候选普通512基线不退化。记录两线后续任务，不声称首轮已覆盖全部升级。
- [x] 本地提交代码/证据索引，不推送、不改Flash。

### Task 5: 板键持续缩放

**Files:** zoom_control.c/h、test_zoom_control.c、board_top.v/peri.xml、独立test_board_zoom.c及构建入口；必要时单模块同步器和独立RTL检查。
**Interfaces:** `zoom_control_init(state,now_ms)`、`zoom_control_update(state,pressed_mask,now_ms)`返回Q8.8比例；bit0缩小/bit1放大，双键不变；起始256、范围64..1024、速度128单位/秒、20ms消抖、松开保持、毫秒回绕安全。板端Sapphire读取已同步真实KEY1/2；GPU新Transform取源/目标尺寸，不在软件预缩放。

- [x] 核对官方新指南与实际按键Demo约束；记录旧原理图标签冲突。保留LED原映射，新增按键专用输入和2FF同步。
- [x] 先写按住时长/释放/双键/反向/抖动/上下限/时间回绕的控制器RED测试，再实现无阻塞C状态。
- [x] 独立缩放演示由1x的16×16飞机开始，按比例给出4..64像素目标，HUD/普通游戏/挑战不变；固定UI/清背景使用原GPU命令。
- [x] 编译与离线验证后才候选JTAG；C32最终像素oracle与演示启动通过。
- [ ] 实际按键与HDMI人工确认；已保留演示，未将这项算作通过。
