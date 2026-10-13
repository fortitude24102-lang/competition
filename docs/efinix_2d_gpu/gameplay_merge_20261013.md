# A-work新玩法与列表前端兼容合并（2026-10-13）

范围：在本地`codex/efinix-2d-gpu`（基点`ac8f137`）合并A-work
`cc86953e7057a872d5b1b497afb1c7f92820f4cd`，保留前一天的GPU列表/CRC优化。
没有烧录、板测、推送main或覆盖release。用户要求是本地合并；旧工作区的无关未跟踪文件保留。

## 新玩法与适配

A工作交付移动敌机、六种弹道、敌机HP、击毁和WIN，详情见
[A的玩法说明](gameplay_campaign_20261011.md)。Sapphire继续负责全部逻辑；CPU基础绘图算法/配置、PC职责、网口协议、素材、GPU时钟和生产RTL不变。

直接合并先复现两个真实断言失败：紧凑列表敌机地址与`game_build`不一致；新版回放CRC与旧独立规范参考不一致。针对性修复如下：

- 紧凑列表与原命令构建器共用`bullet_enemy_position`；死亡敌机及失活敌弹的核心/光晕隐藏规则同步。不复制六种弹道逻辑，逻辑仍只有A实现一份；冻结R7绘制/规则保留。
- WIN含30条Fill，当前16B模板前端不支持Fill。GPU-only `v3_build_gpu_scene`在普通战斗选列表，在WIN选原硬件命令路径；仍GPU绘制，不是CPU代画。菜单、CPU比较分支不改。该函数直接被实际V3循环使用，测试也调用它，避免只检查源码字样。
- 原始列表构建器明确拒绝人工模式WIN并清零统计，不会生成能发布的错误列表；V3在执行前选择合法路径，不以执行失败触发自动重放。
- 保留64B小表CRC算法；回放版本2的新interactive/won/3个enemy_hp及每弹path同时进入生产CRC和独立逐位参考。固件整体重新链接，不混用旧对象或内存记录；没有对旧版本记录补造迁移或磁盘存档接口。
- README仅为段落冲突，双方历史记录均保留；明确历史59.6FPS不属于新玩法。

## 本轮离线验证

| 检查 | 结果 |
|---|---|
| 合并前基线 | 12000冻结R7、9600旧互动列表/3完整像素样本及真实实例驱动通过 |
| RED顺序 | 实际地址不一致→移动适配后击毁数量不一致→隐藏适配后WIN拒绝断言失败→修复后通过；新dispatcher缺符号RED也保留 |
| 新列表/真实V3选择 | 12000R7＋9600新玩法逐字段/顺序/统计、3个完整战斗像素样本、WIN/R实际像素、30 Fill/33命令、失活/击毁隐藏、状态不变、容量canary通过 |
| CRC | 原合并真实CRC断言RED；新版规范字段参考与保留的小表算法GREEN |
| 完整软件入口 | 20项C＋23项实际UDP/HTTP通过，含campaign、108000计划内LIVE更新和18轮CPU/GPU各600步回放；不算墙钟耐久 |
| 原始帧列表驱动 | 旧能力安全、585计数、tag回绕、epoch、发布、bank、timeout、拒绝重放通过 |
| 原像素RTL | 新战斗＋WIN，共1121602次核对通过：Copy1036800/Key33872/Alpha9936/Fill40994；生产RTL未改 |
| 完整固件 | 列表正常版、列表512终止探针、无列表版都链接ELF/BIN/HEX通过，未加载 |

实际本机Windows GCC位于Downloads，但无法启动其编译子进程，A的原生入口
`build-test_net_control`报`gcc.exe: error: CreateProcess: No such file or directory`。
该失败保留，**没有宣称原生15项入口在本机通过**；未修系统工具链、未掩盖退出码。
现有WSL/GCC完整20项入口与同一像素RTL实际运行通过，覆盖所需软件功能。
既有RWX LOAD链接警告保留。整SoC历史两项固件异常未在本轮解决或复跑；本轮没有重跑未改变的22分钟Chisel整套仿真。

4KiB预留栈保留，ELF实际`_sp`与软件RAM上限`0x20000`比较：

| 候选 | _sp | 预留栈后的额外余量 |
|---|---|---:|
| 新列表正常版 | 0x1cdd0 | 12848B |
| 新列表512终止版 | 0x1d0d0 | 12080B |
| 无列表互动版 | 0x1f690 | 2416B |

这是静态链接布局，不是运行时栈峰值。A说明中的2896B来自其较早基点/构建参数，不作为本轮合并固件余量。

一次独立只读审查无Critical/Important；唯一文档打包提醒（证据目录尚在准备）已在提交前完成。
[审查与所有未判定边界的取舍](evidence/gameplay_merge_20261013/review.md)。没有将这些边界补写成通过。

## 复现与下一步

```powershell
wsl bash scripts/test-v3-instances.sh
wsl bash scripts/test-frame-list-driver.sh
powershell -NoProfile -File scripts/test-v3-integration.ps1 -SoftwareOnly -ReplayCrcNibble
powershell -NoProfile -File scripts/test-efinix-software.ps1 -FirmwareOnly -Interactive -CopyAhead -ReplayCrcNibble -FrameList -NetworkLocalIp 0xc0a80103 -NetworkPeerIp 0xc0a80102 -OutDirectory generated/verification/v3/new-game-normal-fresh
```

完整20项入口已加入campaign和A/B生命周期，不需依赖Windows原生GCC入口。
本轮输出目录`generated/verification/v3/gameplay-merge-20261013`；归档首失败、GREEN、软件/像素结果、链接符号与文件身份见
[证据目录](evidence/gameplay_merge_20261013)。大BIN/ELF和生成目录不进Git。

合并后仍需新固件的实板移动/击毁/WIN/R、CPU慢比较、新256/512满负载帧率、输入延迟/下溢和耐久。
击毁或胜利造成元素变少，不可拿其60FPS替代512满负载验收；旧59.6FPS只属于10月12日旧玩法。
本轮不换GPU架构、不在画面美化上追加任务。
