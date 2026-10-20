# Key专用双在途写 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline. Steps use checkbox syntax for tracking.

**Goal:** 隐藏缓存Key的逐行B尾等待，保持像素/错误/完成和显示契约。
**Architecture:** 新Key-only writer接受顺序请求，深度2 burst响应元数据；缓存Key行推进与退休分开，DDR仲裁独立返回B。通用writer不改。
**Tech Stack:** 现有Chisel/Scala/C/PowerShell，不增依赖。
**Spec:** docs/superpowers/specs/2026-10-19-key-write-pipeline-design.md

## Global Constraints

- 官方Sapphire、CPU绘图、100MHz、DDR/HDMI/网口、C32命令、场景和Alpha/Key顺序不变。
- `enableKeyWritePipeline=false`，必须KeyPrefetch且禁止与KeyRowTrim组合。
- 最多2笔burst，256拍和4KiB切分，最后B才退休；只JTAG/RAM，不推送/Flash/release。

## Review Focus

- 两请求同时在途时B错误不能归错请求，split首B不能完成。
- 下一行不能少源数据、提前覆盖aligner或在B未收齐时完成命令。
- Asset的B不能发给当前W owner；显示紧急入场不得撤回已呈现AW。
- 完成边界、credit满与同拍AW/B、请求/done需要守恒。
- 默认路径和通用Copy/Alpha不因候选模块改变。

### Task 1: 可独立验证的双在途writer

**Files:** 新AxiWritePipeline.scala、KeyWritePipelineSpec.scala。
**Interfaces:** 与AxiWriteEngine相同request:AxiWriteRequest、data:AxiWriteBeat、axiAw/axiW/axiB、done/error；不修改AxiWriteEngine。

- [x] 先写新真实RTL测试并看到缺类RED：两行在首B之前完成W但不done；第三请求满credit不接收；分别B退休；0xff8/4拍拆2+2且首B错误聚合到最终B；错误时禁止新请求。
- [x] 实现独立AW/W调度、深度2 lastBurstOfRequest响应FIFO和每请求错误累积，零拍只在无旧请求时处理，保持顺序。
- [x] 定向writer两项通过并本地提交。多行缓存/仲裁排空另由Task2集成验证，不能仅凭此声称全链路或上板。

### Task 2: 全链路候选

**Files:** CachedKeyStream.scala、DenseBlitEngine.scala、DdrQosArbiter.scala、RenderEngine.scala、Efinix2dGpuTop.scala、GenerateEfinix2dGpu.scala、test-v3-gpu.ps1；扩展KeyWritePipelineSpec候选集成。
**Interfaces:** 尾参数`enableKeyWritePipeline:Boolean=false`从Top/Render/Dense传播，CachedKeyStream尾参数`pipelineWrites:Boolean=false`；DdrQos尾参数`enableWritePipeline:Boolean=false`。生成与脚本使用独立新目录。

- [x] 实际候选Key在B延迟下第二行发AW、最终B前不完成；DDR候选Render/Asset交错B所有权及紧急准入测试先RED。
- [x] 实现行W推进与pendingRows守恒；Dense仅Key选择新writer；arbiter ownerFIFO在WLAST入队，预留slot后AW、B独立回送；诊断按B队首计。
- [x] 定向候选的像素/掩码、两半字相位、4KiB边界、cache错误、B错误＋后继Fill通过；当前源码默认兼容30套119项一次通过，另诊断3项和候选14项，合计35套136项，不重复通过批次。

### Task 3: 时序与净收益

**Files:** 生成RTL/独立编译目录、证据索引/README；正式release不变。
**Interfaces:** 既有保存分段/普通512/诊断固件，无改工作量和评分规则。

- [x] 独立审查，补齐错误归属和后继命令覆盖（未发现RTL缺陷，不伪造bug RED）；生成split-verilog，最终16个setup/hold均正才上板。
- [x] 同诊断/分段与普通512固件分别A/B/A，核对数量/CRC/读写/Cache/物理事务及零新增下溢/错误；看整帧平均与最坏值，不只看Key局部。普通512均值减少7.72%，最大值无改善，保留显式候选。
- [x] 封存实测与负结果，本地提交，不推送；正常MENU与控制释放已恢复，采集/烧录结束。另行完成1819＋228Alpha的3600帧与5秒保持，命中软件容量上限，不称硬件绝对极限；证据索引docs/efinix_2d_gpu/evidence/key_write_pipeline_20261020/README.md。
