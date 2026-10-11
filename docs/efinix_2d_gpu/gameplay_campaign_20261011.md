# 互动游戏：随机敌机、六类弹道与胜利（2026-10-11）

## 范围与接入

用户明确要求不改硬件，只优化画面/逻辑并传入 **A-work**。基点为最新main `7edbb61`；仅将A-work快进至该基点后开发，不修改或推送main。沿用现有生产互动入口，由已有 `game_reset` 自动启用新玩法，不另造主循环。

生产改动限 `bullet_demo.c/h`、`interactive_game.c`、`replay_input.c/h`。不改生产RTL、Chisel、工程源清单、GPU驱动/时钟、CPU基础绘图、`main.c`、`v3_demo.c`、菜单、HUD、网关、网络协议和素材；不综合、不连接板卡、不写Flash，不覆盖release。唯一 `.sv` 改动是离线像素测试台，不是硬件设计。官方Demo目录及原有用户VCD保留。

## 玩法

- 三架既有不同外形的敌机每120逻辑tick选择一个种子航点，线性平滑移动。各有独立航点，限定在上方安全区域，不侵入72像素HUD；最大横向约2像素/tick，整数舍入检查允许3像素变化。R重开相同种子可重现同局，不使用PC时间或外部随机源。
- 敌机绘制、光晕、发弹与友弹命中共用 `bullet_enemy_position`，不会出现模型移动而碰撞仍在旧位置。暖启动保留密集弹幕分布，后续回收弹从当前机位发射。
- 六类轨迹随对象编号和180tick阶段轮换，均用Q8整数运算，无逐弹浮点或三角函数。

| 编号 | 轨迹 | 行为 |
|---|---|---|
| 0 | 直线/扇形 | 保留原放射及偏向扇形 |
| 1 | 瞄准弹 | 发射时对准玩家一次，飞行中不持续追踪 |
| 2 | 蛇形 | 向下移动，横向速度按方向表周期摆动 |
| 3 | 弧线 | 分段旋转速度方向，形成弯曲/回旋路径 |
| 4 | 加速弹 | 向下速度逐段增加，设上限，横向保持扇形分布 |
| 5 | 反弹弹 | 向下斜行，左右边界反射一次或多次，不越界绘制 |

- 每架6HP，每次友弹命中扣1HP并加25分，击毁额外200分。已击毁飞机及光晕消失、不再发新弹；已经发出的弹继续飞行，到期/出界后回收停用，避免直接抹掉仍在空中的威胁。
- 全部三架击毁后进入胜利状态：停止战斗推进和新发射、隐藏余弹，在原背景上显示绿色WIN、黄色R；保留玩家及光晕。按R重新开始当前档位，网页回菜单仍走现有机制。每次调用仍递增绝对tick，局内tick/分数/机位冻结。
- 玩家仍3HP、受击60tick保护、支持擦弹和慢速移动。最新main已有的菜单模式死亡回菜单不变；无菜单的独立逻辑仍保留既有死亡等待重开。

胜利字样只使用现有Fill命令构造：29个字形矩形，加面板/背景/玩家/光晕共33条命令，不增加资源下载或字体数组。正常满池仍最多585条场景命令、68条Alpha；敌机摧毁或胜利后元素下降是真实玩法变化，不可冒充同屏满负载加速。

## 确定性、兼容与内存

`bullet_reset` / `bullet_step` / `bullet_build_frame` 保留冻结R7；互动入口通过 `bullet_reset_player` 打开新规则。冻结32/128/512档各600tick摘要仍为 `0cec877a / 225e4a68 / 598a29df`。

敌机HP、互动标记、胜利标记和逐弹路径参与规范化回放CRC。内存记录版本由1升2，无磁盘存档迁移、没有网口ABI变更；固件必须整体重编译，不能混用旧对象文件或内存状态。CPU和GPU从同一初始状态/600条输入重放，种子和逻辑tick决定航点，不受两种渲染速度影响。

默认512池：`bullet_object` 仍20B（路径占用原padding）；`bullet_state` 10,284B（+4B），命令流18,740B，回放记录11,500B。没有扩大默认对象池或把1024主机测试当成可上板固件。

用原官方BSP、原生产源清单完整链接互动版：text=45,112B、data=0、bss=78,964B；链接图RAM至`0x20000`，`_end=0x1e4b0`，4KiB预留栈结束`0x1f4b0`，余量`0xb50=2,896B`。这是链接布局检查，不是动态最坏栈证明。保留既有 `LOAD segment with RWX permissions` 警告，未修改链接脚本以掩盖问题。

## 复现（无需开发板）

从仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-gameplay-upgrade.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-bullet-regression.ps1 -HostGcc D:/aaa/mingw64/bin/gcc.exe
```

新入口支持 `-HostGcc / -Python / -IcarusHome / -RiscvGcc / -Out`，默认使用本机已有工具；每次新建输出目录，拒绝覆盖旧证据。不安装WSL，不占用现有控制/资源服务，不连接板卡。输出全部日志、RGB565/PNG、像素向量、RV32对象/栈报告和源码SHA256收据。

完整固件链接另用既有脚本，`-Soc` 可替换为本机官方BSP路径；本轮使用用户提供的官方Demo：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-efinix-software.ps1 `
  -FirmwareOnly -Interactive `
  -RiscvGcc C:/efinity/riscv/toolchain/bin/riscv-none-elf-gcc.exe `
  -Soc Ti60F225_DemoBoard_v4/08_ti60f225_soc_demo/09_Ti60F225_co_debug_demo/par/ddr_demo_ti60/embedded_sw/soc `
  -OutDirectory generated/verification/gameplay-candidate-firmware
```

不加 `-Interactive` 并改为另一个新输出目录可单独链接旧R7版。两者都只产生候选ELF/BIN/HEX，不加载、不发布release。

## 本轮结果与证据

本机输出根为 `generated/verification/gameplay-20261011/`（生成物不加入Git，可按上述入口再生）：

- `final-native/`：15项C套件全通过，包括冻结R7、已有操作/输入/回放、实际菜单GPU命令、runtime菜单/档位/死亡/取消、性能计数合同、旧/差分提交、容量、跨模块生命周期及新campaign定向检查；6个实际生产模块RV32编译通过，启用2KiB单函数栈告警。
- 新campaign检查覆盖：敌机实际绘制地址变化、4999tick/机的边界/连续性、换种子、六路径及具体速度、移动位置再发射、逐机6次命中、击毁停止再发射、全灭才WIN、WIN冻结/R重开、胜利发生tick的双后端600步回放、HP/path/won篡改拒绝。
- 生命周期：108,000次计划内LIVE更新、18轮双后端各600步规范字段/命令比较；不是墙钟30分钟耐久，也不保证这些更新始终处于满负载战斗。
- CPU基础绘制与独立标量参考对600tick的10张整帧抽样完全一致。新第600tick画面CRC为 `dd374ef2`；显式合法WIN状态整帧CRC为 `0700a89f`、33条命令，并断言WIN/R关键像素实际点亮。WIN整帧测试使用明确构造的状态，实际击毁进入WIN另有生产逻辑定向测试。
- **未改生产像素RTL** 对正常/WIN两帧共1,121,602次输入/输出和背压保持核对通过：Copy 1,036,800、Key 33,872、Alpha 9,936、Fill 40,994。不是全SoC新位流验证，不反复重跑未改网络RTL。
- `final-native/live.png`、`victory.png` 已目视检查：弹幕/敌机正常、胜利文字清楚，均为游戏层预览；顶部未叠加生产HUD，不代表实板HDMI照片。
- `firmware-final/` 和 `firmware-r7/`：完整互动/R7 ELF/BIN/HEX链接通过，未覆盖release。原生旧12项C回归、前台启动器与V2/bullet实际本机UDP资源目录检查通过。

原生入口没有宣称全部15个Linux集成单测：两个未改的HUD文本/app-helper测试在PE链接器下无法丢弃其未调用硬件函数，仍保留于 `test-v3-integration.ps1` 供Linux运行；本轮不屏蔽未解析符号、不改生产硬件函数。已运行受影响runtime、实际菜单命令、旧HUD软件回归及完整固件链接。

另修旧回归脚本的假失败：启动器负面用例正常返回非零，原先进程内调用会将最后一个预期失败的 `$LASTEXITCODE` 留给外层。改用独立PowerShell子进程读取启动器整体退出结果，保持所有断言和服务清理；没有修改资源服务器或杀掉已有用户服务。第一次假失败及复跑结果均如实记录，不算游戏逻辑失败。

## 仍需负责人实板确认

本轮只交付A-work软件候选。未验证新版真实HDMI画面、操作难度/可玩性、最坏栈、输入延迟、CPU慢比较控制租约、256/512档新场景帧率、下溢或真实30分钟耐久；原main的0.34秒CPU帧/250ms租约限制仍存在。新版游戏工作量变化，不能沿用10/08的板测结果标为本版通过，更不承诺512@60。建议先用既有合格硬件加载候选，确认移动/六轨迹/击毁/WIN/R，再按未击毁满负载阶段重新采样性能；这项板测不在本轮执行。
