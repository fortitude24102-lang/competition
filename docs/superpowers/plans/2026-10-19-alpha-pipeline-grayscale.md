# Alpha连续提交与灰度缩放 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans in this session. Steps use checkbox syntax for tracking.

**Goal:** 验证可回退的Alpha连续像素调度，并将功能线限定为GPU灰度和板键缩放。
**Architecture:** 性能只加两项元数据FIFO，像素运算和DDR事务不重写；灰度复用Transform采样后的写回，独立演示不进入资格负载。
**Tech Stack:** 现有Chisel、像素Verilog、C及WSL测试，不新增依赖。
**Spec:** docs/efinix_2d_gpu/gpu_dual_track_20261018.md，2026-10-19范围收敛与第二轮。

## Global Constraints

- 官方Sapphire、100MHz、DDR、HDMI、以太网与CPU基础渲染保持不变。
- 原命令0..6、C命令32字节和旧BIT兼容，新性能候选默认关闭。
- 仅JTAG/RAM，不写Flash、不推送、不覆盖release或旧证据；板卡与时序未通过时不加载。
- 不扩展阈值、颜色映射、截图、压缩或网页图像预览。手工.v仍一个模块。

## Review Focus

- Alpha结果与元数据在背压下必须一一对应；不能在块末预先读取下一块。
- 半字相位、奇数尾和跨64像素块不得吞像素或写padding。
- R/B失败之后排空承诺写，错误退休一次，下一命令不受污染。
- bit17旧BIT不支持灰度时必须在任何MMIO写和tag变更前拒绝。
- Key在灰度之前判断，旧flags与不启用灰度时的像素保持不变。

### Task 1: Alpha连续提交候选

**Files:** DenseBlitEngine.scala、RenderEngine.scala、Efinix2dGpuTop.scala、GenerateEfinix2dGpu.scala、scripts/test-v3-gpu.ps1；新AlphaPipelineSpec.scala。
**Interfaces:** 顶层/Render/Dense尾参数enableAlphaPipeline:Boolean=false，生成--alpha-pipeline；现有命令及AXI/完成接口不变。

- [x] 先写旧/新相同AXI模型与真实像素RTL的对照测试；同源结果、哨兵/掩码、处理数与退休顺序相等，候选周期必须更少，先RED。
- [x] 两项元数据FIFO关联地址/行末/块末；只对Alpha连续提交，尾结果消费后再换块/行；默认生成不增加队列。
- [x] 定向验证随机读写背压、1/3/16/65宽与两相位、缓存68B、连续命令及R/B错误；独立审查补强跨块事务后4/4通过，提交cf5e44b。另修复地址生成器错误结束未清理、前后写块done/request同拍竞争。

### Task 2: 灰度与能力协商

**Files:** TransformBlitEngine.scala、GpuTypes.scala、GpuApbRegs.scala；gpu.h/gpu_regs.h/gpu.c；TransformBlitSpec.scala/TransformValidatorSpec.scala/TransformApbSpec.scala/test_transform_driver.c。
**Interfaces:** Transform.flags bit5，Mask51；STATUS bit18，缩放bit17不变；函数gpu_transform_blit_async签名不变，C布局32字节不变。灰度公式、先Key后灰度遵循Spec。

- [x] 写红绿蓝/黑白字面值灰度、非整数缩放/镜像/Key与暂停保持测试；bit17-only硬件拒绝灰度但接受旧缩放，先RED。
- [x] 在采样源像素处仅增加移位加法和灰度/原色选择；透明比较仍用源色。驱动分开检查两能力，默认关闭Transform时两能力位均0。
- [x] Transform三套8项及C驱动/V3软件检查通过，提交43afbd6。默认关闭及旧缩放能力行为保留。

### Task 3: 演示、回归与证据

**Files:** test_board_zoom.c、test_board_transform.c、新test_board_alpha_pipeline.c及构建入口、README、第二轮证据索引。
**Interfaces:** 现有zoom/transform构建入口；左右彩色/灰度飞机同尺寸、同键控，灰度固件需要bit17/18。旧游戏/挑战BIN不重建作为性能A/B输入。

- [x] 独立演示彩色/灰度同屏，复用原缩放控制；离屏oracle增加灰度×缩放×镜像×Key读回期望，共80例。宿主布局检查和两份RV32固件构建通过，尚不代表板测。
- [x] GPU完整首跑30套119项117通过/2个Alpha失败，修正后Alpha定向4/4通过；V3软件/真实协议检查及完整游戏链接通过。保留首失败，不伪造单次全GREEN，不重复通过套件。
- [x] 生成新目录R2开/关两版，全部16项时序关系正；A/B各80例Transform和24例Alpha物理读回通过，同BIN普通512三组3600帧A/B/A完成，候选约0.525%均值收益，最大耗时无改善。R1有竞争缺陷、从未加载，保留失败证据。
- [x] 独立审查覆盖核心RTL/驱动，跨块测试缺口已补；原始失败、定向GREEN、A/B/A、像素读回、RTL/时序与BIN/源码快照封存于evidence/alpha_gray_20261019/evidence.zip。只作本地提交，不推送/发布。人工灰度组合目视待补，不冒称新极限资格或全SoC通过。
