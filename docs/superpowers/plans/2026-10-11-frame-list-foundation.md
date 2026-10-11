# Frame List Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付当前游戏的直接16B列表构建器和AXI突发预取器，不宣称整机接入/帧率收益。

**Architecture:** 软件复用模板/裁剪直接写调用者缓冲；硬件复用ID6读引擎，先缓存完整列表再按顺序消费。顶层和生产固件不变。

**Tech Stack:** 现有C11/UBSan、Chisel7.7、ScalaTest/StableChiselSim。

**Spec:** docs/superpowers/specs/2026-10-11-frame-list-foundation-design.md

## Global Constraints

- 用户免除中间审批，当前对话亲自执行，最后一次独立审查；无远程推送。
- CPU绘图、官方Sapphire、GPU100MHz、960×540、Key/Alpha、网口/菜单和release不变；本阶段不烧录。
- 保留旧gpu_instances_build和16B四字格式；失败统计清零，不提交半帧。
- Reader默认1024项，ID6，1..1024、16B对齐、0x02d20000..0x02d28000且单批不跨16KiB bank。
- done是列表消费完成，不是后端渲染完成；不引入全帧旧命令中间数组或片内软件BSS列表。

## Review Focus

- 失活kind3在每8项glow位置时不得泄漏glow；R7不得放宽成任意kind3。
- 检查state/items/stats不重叠的调用契约和失败统计清零；不得把部分输出/错误count当作可发布帧，不宣称运行时检测任意指针别名。
- 请求结束正好bank边界/最大count：64bit范围计算不绕回，RAM索引不截断。
- 数据错误发生在最后一拍：不得先输出描述符再发现错误。
- done与后端completion不同：文档/名称不得暗示已完成渲染或可以立即PRESENT。

### Task 1: 当前游戏直接列表

**Files:** Modify sw/efinix_gpu/include/gpu_instances.h, sw/efinix_gpu/src/gpu_instances.c, scripts/test-v3-instances.sh. Create sw/efinix_gpu/tests/test_gpu_frame_list.c.

**Interfaces:** 新增gpu_instance_stats与gpu_instances_build_into(const bullet_state*,uint32_t,int,int,int,unsigned,unsigned,gpu_instance*,gpu_instance_stats*)；消费原game_build/gpu_instance_expand/golden_copy/golden_color_key/golden_alpha_blend。

- [x] 写真实API测试：game_reset512含kind3，600tick发射移动、负裁剪、容量护栏、R7不放宽；展开和原game_build+clip统计/顺序/像素等价。Expected RED: 新API尚不存在。
- [x] 运行wsl bash scripts/test-v3-instances.sh，保存RED（缺新API，不是shell错误）。
- [x] 修改私有append/sprite为指针视图，新增直接接口/旧薄包装，manual分支仅GPU构建器。Expected: 无全帧旧命令复制。
- [x] 运行同一C脚本。Expected: 原R7/真实驱动及新当前游戏测试全部PASS。
- [x] 运行test-v3-integration.ps1 -SoftwareOnly -ReplayCrcNibble。Expected:18C+23UDP/HTTP PASS；提交Task1，task-done用C脚本。

### Task 2: 有界整帧AXI预取

**Files:** Create chisel/src/main/scala/gpu/FrameListReader.scala, chisel/src/test/scala/gpu/FrameListReaderSpec.scala. Reuse AxiReadEngine unchanged.

**Interfaces:** FrameListRequest(address UInt32,count UInt16)；FrameListReader IO见Spec。descriptor四字直接消费Task1格式，任何错误整批零输出。

- [x] 写真实模块仿真：3项跨4KiB，65项跨256拍，1024项最大，AR/R/descriptor背压、非法范围/跨bank、首/尾拍错误、后续批/复位。Expected RED: 新类不存在。
- [x] 运行scripts/test-v3-gpu.ps1 -Suite gpu.FrameListReaderSpec。Expected: RED由未实现Reader引起。
- [x] 实现SyncReadMem完整缓存和原AXI引擎联接；先请求合法性，读完无误才输出。Expected: 不新增物理DDR端口/不改Top。
- [x] 运行同一针对性仿真。Expected:全部新用例PASS。
- [x] 完整scripts/test-v3-gpu.ps1、C实例套件。Expected:GPU套件/C PASS；记录实际数量和任何异常，提交Task2，task-done用完整GPU套件。

### Task 3: 留证和下一集成边界

**Files:** README.md, docs/efinix_2d_gpu/frame_list_foundation_20261011.md及证据。

**Interfaces:** 消费前两任务结果，明确未集成顶层/未板测；下步0500门铃+批执行+DDR仲裁/epoch/完成栅栏必须独立验收。

- [x] 写报告、归档全输出/首失败/SHA，记录不改生产Top/生成物/固件。
- [x] 最终一次只读独立审查，按实际影响处理发现；留存未验证边界。
- [x] 验证差异和证据完整性，提交本地分支，保留板上正常菜单；不把512旧FPS写成新前端成绩。
