# 容量扩展与六档游戏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline. Steps use checkbox syntax for tracking.

**Goal:** 将列表容量扩至4096项/3640活动数，并新增786和1024游戏档位。
**Architecture:** 原1024项预取不变，仅扩DDR块和白名单；实际容量能力发现；六档贯穿运行时、协议、菜单和网页。
**Tech Stack:** 现有Chisel/C/Python/JS/PowerShell，无新依赖。
**Spec:** docs/superpowers/specs/2026-10-20-capacity-six-levels-design.md

## Global Constraints
- 64/128/256/512/786/1024；不是768。CPU基础绘图、官方核、100MHz、网口不优化或删除。
- 新arena0x02d20000..0x02d30000，PC状态0x02d30000..0x02d40000；每批1024、总4096、最大3640。
- Top新能力bit20，网络六档能力bit14/mask0x007f7fff，旧BIT安全回退2048/1819。
- 只JTAG/RAM，本地提交，不推送/Flash/release；原4KiB栈不变。

## Review Focus
- 512旧构建/旧BIT被新界面请求5/6，或C上限提高却仍使用旧地址白名单。
- 1024普通场景从bankB越到状态区；扩大bullet_state导致runtime/probe/scene区域重叠。
- 第三/四批错误后PRESENT或重放，tag回绕，部分前缀执行后才发现后缀非法。
- 网络能力/新旧固件切换、浏览器缓存四档状态、伪造level/flags和过期控制。
- 菜单六卡遮盖HUD/性能入口/网络提示，旧缓存未重建，786被误写成768。

### Task 1: 容量与能力
**Files:** FrameListReader.scala/FrameListBatch.scala/GpuApbRegs.scala/Efinix2dGpuTop.scala/GenerateEfinix2dGpu.scala/test-v3-gpu.ps1；gpu_frame_list.h/.c、performance_challenge.h、v3_control_protocol.h、v3_demo.c。
**Interfaces:** enableExtendedListArena=false传Top/Batch/Reader；C uint16_t arena_items实际2048或4096；PC_STATE_ADDRESS0x02d30000，PC_MAX_SPRITES3640。
- [ ] 新FrameListArenaSpec先RED：新mode接第三/四块仍1024max、不跨16KiB/arena末端，默认拒绝；Top bit20。
- [ ] 实现默认关闭白名单/能力和生成开关，测试GREEN；原Reader/Batch边界回归仅一次。
- [ ] C真实驱动测试先RED：新cap发现、4096四批/tag回绕、整体非法零START、第三批错误/超时不再发第四批；PC3640/4096、canary与状态断言。实现最小扩容/运行时最大依arena，再GREEN。
- [ ] 本地提交容量实现。

### Task 2: 六档端到端
**Files:** v3_runtime.c、game_menu.c/.h、v3_demo.c、net_control.c、v3_control_protocol.h、test-efinix-software.ps1；board/efinix_ti60/rtl/net/control_udp_rx.v与tb_net_control.sv；protocol.py/gateway.py/fake_board.py、web/index.html/dashboard.js；现有对应C/Python/JS测试、test-game-menu-board.ps1。
**Interfaces:** v3_level_count1..6映射上述精确数字，>对象容量返回0；status bit14仅1024配置声明；game_menu_cache.levels=6表示六卡，默认旧4；新网页限制旧固件5/6。
- [ ] 先写六档runtime、菜单字形/几何、真实网络ACK/无效7、网关cap门、JS映射与浏览器按钮RED。
- [ ] 实现容量1024构建、列表大场景baseA、六卡/六按钮、能力边界，键盘/死亡/重选及旧档行为不变，GREEN。
- [x] 补齐硬件网口接收层1..6准入；真实router/CRC/CDC/APB测试先复现level5被丢，再最小修复，level7仍拒绝；六套网络RTL及实际子系统回归通过。原计划/首轮审查未覆盖此层，已补正。
- [ ] 当前软件/网关/协议套件一次完整检查，固件实际链接和DDR/4KiB栈边界检查；本地提交。

### Task 3: 集成与上板
**Files:** 独立RTL/编译/固件输出、README和本轮证据索引。
**Interfaces:** 新BIT须原Key双在途/Scanout/Alpha/Gray功能保留；normal1024固件/网关新mask一致。
- [ ] 一次新鲜只读审查，解决重要项；新split RTL各.v单module，最终16项时序均正。
- [ ] 独立JTAG跑四块列表像素/计数oracle，正常六档START/MENU/网络资源、786/1024短测及性能挑战；记录性能但不预报60FPS。
- [ ] 验证静态菜单截图/用户目视可选不阻塞；恢复MENU/释放控制，停止采集烧录，封存实测、本地提交。历史问题不补称通过。
