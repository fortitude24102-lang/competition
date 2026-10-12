# Frame List Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans task-by-task. Native execution and intermediate approval waiver are supplied by user.

**Goal:** 接入真正列表批执行并完成资格/收益验收，有收益保留，无收益恢复旧路径。
**Architecture:** Reader独占idle Render读端口，完整预取后原InstanceStream自动展开、原队列/像素后端执行，Batch排空完成。
**Tech Stack:** 现有C/Chisel7.7/Verilator/Efinity/JTAG。
**Spec:** docs/superpowers/specs/2026-10-12-frame-list-integration-design.md

## Global Constraints

- CPU基础绘图、Sapphire、100MHz、960×540 RGB565、网口/menu/Alpha/Key不变。不开新CDMA，不写Flash，不推送。
- 新功能默认关闭，候选独立输出/--legacy-copy。每SV模块独立文件；正式清单/release不替换。
- count1..1024、16B、单16KiB bank，地址02d20000..02d28000；非1024Sprite支持。
- 部分错误不重放/PRESENT；只有真实排空才能sticky完成。软件发布采用现有官方cache同步。

## Review Focus

- 最后读拍错误不得泄漏命令，descriptor错误不得自动重放已执行Alpha。
- 后端末B迟到、最后描述符尚待验证时，不得提前done/PRESENT或编辑模板。
- 旧位流安全探测不得访问0500；uint8 outstanding不能装整帧计数；tag回绕。
- 新批开始时render/cache在途，旧SUBMIT/模板/缓存并发不得混入列表或切错R归属。
- CopyAhead不得双Copy；CPU分支必须原算法/配置；正常/诊断固件空间不得越界。

### Task 1: Top列表硬件

**Files:** FrameListBatch.scala、新FrameListBatchSpec.scala；InstanceStream.scala、Efinix2dGpuTop.scala、GpuApbRegs.scala、GenerateEfinix2dGpu.scala。
**Interfaces:** consumes FrameListReader request/descriptor; produces batch APB0500,reader AR/R,fetching/active,InstanceStream optional list begin(tag),end,owned,descriptor,empty,error; legacy API unchanged.

- [ ] 新真实Top AXI测试：Copy→透明Key→Alpha像素0x83e0，3描述符ID6突发，65535→0→1，延迟B后才sticky done，epoch回读，legacy/template锁、末R错误零写，坏descriptor不重放，非法bank零AR。Expected RED:new Top flag/class missing.
- [ ] 实现Batch和InstanceStream自动入口、Top读mux/能力/注册APB，运行FrameListBatchSpec、InstanceStreamSpec、FrameListReaderSpec、Efinix2dGpuTopSpec。Expected全部PASS；提交，task-done用定向套件。

### Task 2: Driver与当前游戏

**Files:** 新gpu_frame_list.h/c、test_gpu_frame_list_driver.c、test-frame-list-driver.sh；v3_demo.c、Makefile、test-efinix-software.ps1。
**Interfaces:** init/render签名与Spec完全一致；V3_FRAME_LIST、-FrameList及终止选择地址02d10004；consume直接16B构建器、既有CopyAhead/官方sync。

- [ ] 真实C驱动测试先RED缺API，断言旧cap不读新地址、首次tag65535/n3→next2、epoch/issued错误、不重放、timeout/busy、publish同步在START之前。Expected missing API RED。
- [ ] 实现单门铃有界驱动、GPU-only列表路径及开关；跑新驱动、原实例、18C/23网络；编译正常/终止候选（新目录）。Expected PASS和静态RAM符合，记录实际容量；提交，task-done用新C脚本。

### Task 3: Qualification与实测

**Files:** 独立verification RTL、报告/README、原始证据，不改release/正式source list。
**Interfaces:** --frame-lists --legacy-copy生成参数，FrameListBatchSpec真正Top，现有Efinity候选工程、真实菜单/控制/终止采集。

- [ ] 完整GPU套件一次、生成新RTL，建立新板工程、检查最终setup/hold/资源/CDC。Expected全部合格才JTAG。
- [ ] 本地实现完成后一次fresh只读审查；必须修复项RED→GREEN及完整套件，次要项记录。
- [ ] 合格候选同BIT/BIN旧→新→旧256/512各30+600采样，健康异常立即停止。Expected workload一致/零新错，净收益实测决定保留。
- [ ] 恢复正常MENU，归档日志/SHA及CPU未改证据，README真实状态，本地提交。无法资格时留失败证据，不冒称完成板验。
