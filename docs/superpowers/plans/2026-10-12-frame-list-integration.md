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

- [x] 新真实Top AXI测试：Copy→透明Key→Alpha像素0x83e0，3描述符ID6突发，65535→0→1，延迟B后才sticky done，epoch回读，legacy锁、末R错误零写，坏中间descriptor不重放，非法bank零AR。Expected RED:new Top flag/class missing；实际RED→GREEN。模板/缓存写锁和busy-START经代码审查，本轮未直接注入，记录为待补测试，不冒称直测。
- [x] 实现Batch和InstanceStream自动入口、Top读mux/能力/注册APB，运行FrameListBatchSpec、InstanceStreamSpec、FrameListReaderSpec、Efinix2dGpuTopSpec。实际4套件12/12通过；已提交。

### Task 2: Driver与当前游戏

**Files:** 新gpu_frame_list.h/c、test_gpu_frame_list_driver.c、test-frame-list-driver.sh；v3_demo.c、Makefile、test-efinix-software.ps1。
**Interfaces:** init/render签名与Spec完全一致；V3_FRAME_LIST、-FrameList及终止选择地址02d10004；consume直接16B构建器、既有CopyAhead/官方sync。

- [x] 真实C驱动测试先RED缺API，断言旧cap不读新地址、首次tag65535/n3→next2、epoch/issued错误、不重放、timeout/busy、publish同步在START之前。实际缺API和故障后重新init两个RED→GREEN。
- [x] 实现单门铃有界驱动、GPU-only列表路径及开关；跑新驱动、原实例、18C/23网络；编译正常/终止候选。实际全部通过；早期probe溢出528B未加载，最终保留4KiB栈，余量15616/14896B。已提交。

### Task 3: Qualification与实测

**Files:** 独立verification RTL、报告/README、原始证据，不改release/正式source list。
**Interfaces:** --frame-lists --legacy-copy生成参数，FrameListBatchSpec真正Top，现有Efinity候选工程、真实菜单/控制/终止采集。

- [x] 完整GPU一次17套件82/82，生成新RTL，最终setup/hold/资源/CDC通过后才JTAG。
- [x] 一次fresh只读审查Critical0/Important0；两项minor及全部未判定边界记录。额外诊断构建器重复源实际RED→GREEN，生产RTL/C未变化。
- [x] 同BIT/BIN旧→新→旧256/512各30+600；再验实际旧合格BIT/原固件基线及新512重复。新增下溢/错误均0，新51259.6FPS、5/600迟到，真实旧42.5FPS。有净收益保留显式候选，不宣称稳定60。
- [x] 正常MENU、四档真实ACK/新快照、256方向/租约释放通过；归档日志/SHA、CPU未改及README，本地提交。最终收尾命令校验已归档原始证据，不重复运行未变化的完整RTL或再烧录；正式发布/main不替换。

完成记录：[整机实现、数据、剩余边界](../../efinix_2d_gpu/frame_list_integration_20261012.md)。本轮完成的是前端候选阶段，不是V3全部验收或稳定512@60。
