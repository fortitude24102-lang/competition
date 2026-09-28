# 网口可靠启动与 GPU HUD 背景裁剪设计规格

日期：2026-09-28

状态：待书面规格确认

适用基线：`fa8f964`（4 KiB GPU 纹理 Cache 已合入 main）

## 1. 目标

本轮同时完成两个彼此独立、可分别验收的改进：

1. 消除“板卡正常但 PC 没有 UDP 8080 监听进程”造成的资源加载超时，
   提供可复现的前台资源服务器启动入口，并重新取得板端 ID 101/102
   零重试、CRC 成功的证据。
2. 在不改变 CPU 软件渲染基线、最终画面、游戏逻辑、对象数量、GPU
   时钟、分辨率、Alpha、Color Key 和双缓冲语义的前提下，只为普通
   GPU 演示裁掉最终会被 HUD 完全覆盖的顶部 72 行背景 Copy。

PC 继续只提供素材。Sapphire RISC-V 继续负责以太网协议、资源校验、
游戏状态和 GPU 命令生成；AetherGX 负责硬件渲染。

## 2. 已确认的根因与性能依据

### 2.1 网口

故障发生时：

- PC 网卡 `192.168.1.2/24` 正常，链路为 1 Gbps；
- 板端固件仍请求 `192.168.1.2:8080`；
- 两份 `asset_server.exe` 的 SHA-256 相同，Public 入站防火墙规则均为
  Allow；
- PC 上没有 UDP 8080 监听进程；
- 服务器源码在成功绑定后无限循环，不会在完成一次资源请求后主动退出。

重新以前台进程启动
`generated/verification/v2-network-software/asset_server.exe` 后，UDP 8080
立即出现监听；使用弹幕素材清单的回环测试 2/2 通过。因此根因是运行
前置条件缺失，不是 PHY、IP 配置、协议或素材服务器实现错误。

### 2.2 背景 Copy

纹理 Cache 候选的普通 64 档 GPU 渲染约 9.30 ms，而固定探针中全屏
960×540 RGB565 背景 Copy 约 8.0～8.8 ms，已经是主要渲染成本。正常
路径随后用 960×72 的 HUD Copy 完整覆盖顶部 72 行；这些背景像素和落在
其中的场景像素不会进入最终显示。

裁掉顶部 72 行后，每帧减少：

```text
960 × 72 = 69,120 像素
读取 138,240 B
写入 138,240 B
背景 Copy 工作量减少 13.33%
```

这是结构预算，不预先承诺 FPS 或稳定 60 FPS。

## 3. 非目标

- 不修改资源服务器 C 协议实现、素材格式、CRC、IP 地址或端口。
- 不创建 Windows 服务、不自动修改防火墙、不加入自动重启守护进程。
- 不优化 CPU 场景、CPU HUD、CPU 渲染器或 CPU 编译选项。
- 不在本轮实现脏矩形、脏 Tile、背景压缩、新 GPU 操作码或描述符 DMA。
- 不修改五档 Profile 的背景命令或历史测量口径。
- 不修改 100 MHz GPU 主频、960×540 逻辑分辨率或 1920×1080 HDMI 输出。
- 不减少 Sprite、Alpha 光晕、玩家、敌机或 HUD 内容。
- 不替换 `release/v2/`，不写 Flash。

## 4. 网口可靠启动设计

新增 `scripts/run-bullet-asset-server.ps1`，只做运行前检查并以前台方式执行
现有服务器，不复制协议逻辑。

参数：

```text
-ServerPath  可选；默认优先使用 generated/verification/v2-network-software/
             asset_server.exe，缺失时回退 release/v2/asset_server.exe
-Manifest    默认 sw/efinix_gpu/assets/bullet/manifest.csv
-Port        默认 8080
-PcAddress   默认 192.168.1.2
```

启动顺序：

1. 确认服务器、清单和清单内资源文件存在。
2. 确认本机任一活动 IPv4 网卡具有 `PcAddress/24`；不硬编码中文网卡名。
3. 检查 UDP 端口占用：
   - 若已由同一路径的服务器监听，打印 PID 和“已经运行”，成功返回；
   - 若被其他进程占用，报出 PID/路径并失败，不结束未知进程；
   - 若未占用，继续启动。
4. 打印服务器路径、清单、PC 地址和端口，然后使用调用操作符以前台方式
   执行服务器。终端关闭即代表服务停止，避免后台进程静默消失。

脚本不请求管理员权限，不创建或删除防火墙规则。若防火墙不允许，明确
打印已有使用说明位置，由用户处理系统授权。

### 4.1 启动器测试

新增一个 PowerShell 测试，在随机 UDP 端口启动脚本，等待对应监听出现，
确认进程保持运行，然后结束测试进程树。继续复用现有
`test_asset_server_udp.py` 验证真实 GET、分块、LAST、CRC 和完整文件；
不在 PowerShell 中重写协议测试。

### 4.2 板端验收

正式板测前先保持启动器终端运行，再重新 JTAG 加载当前候选位流和普通
弹幕固件。串口必须出现：

```text
BULLET_ASSET,id=101,bytes=1036800,retries=0,result=0
BULLET_ASSET,id=102,bytes=3104,retries=0,result=0
TEXTURE_CACHE,result=0,base=02a00000,bytes=3104,network=1
```

任何回退地址 `02c00000`、非零重试或 `network_result!=0` 均不算网口修复
通过。只临时 JTAG，不写 Flash。

## 5. GPU 专用背景裁剪设计

在 `bullet_demo.h/.c` 增加：

```c
int bullet_clip_background_for_hud(bullet_stream *stream,
                                   unsigned hud_height);
```

函数只修改已经由 `bullet_build_frame` 生成的第 0 条全屏背景 Copy：

```text
src_addr      += hud_height * src_stride
dst_addr      += hud_height * dst_stride
height_pixels -= hud_height
scene_pixels  -= GPU_FRAME_WIDTH * hud_height
```

输入合同：

- `stream` 非空且至少有一条命令；
- `hud_height < GPU_FRAME_HEIGHT`，0 为合法无操作；
- 第 0 条必须是宽 960、高 540、源/目标步长 1920 的 Copy；
- 目标必须是 framebuffer A 或 B；
- 地址加法不得溢出 GPU DDR 范围。

合同不满足时返回 `GPU_DRIVER_ARGUMENT` 且不得部分修改 stream。

### 5.1 调用边界

普通 `main.c` 在 `bullet_build_frame` 成功后，仅当 `mode==GPU` 时调用：

```c
bullet_clip_background_for_hud(&scene, HUD_CACHE_HEIGHT)
```

CPU 模式仍提交完整 960×540 背景。Profile、板端纹理 Cache 专项固件和
其他场景不调用该函数，保持原始工作量。

HUD 仍在场景之后以一条 960×72 Copy 完整覆盖顶部区域。若 HUD 构建或
提交失败，当前帧直接报错且不 Present，不允许显示裁剪后但未覆盖的帧。

### 5.2 双缓冲与画面语义

该方案不依赖 back buffer 的旧内容：

- `y>=72` 的区域每帧仍从背景完整恢复后再绘制所有 Sprite；
- `y<72` 的旧内容可能保留，但同一帧最后被不透明 HUD 全覆盖；
- 跨越 HUD 边界的 Sprite 在可见区域 `y>=72` 仍以正确背景为底绘制；
- HUD 区域内的 Alpha 临时读取旧背景不会影响最终画面，因为结果随后被
  HUD 覆盖；
- framebuffer A/B 采用同一规则，无需增加每缓冲脏状态。

## 6. 验证策略

严格测试先行：

1. 先为启动器写失败测试：没有脚本或脚本未保持 UDP 监听时失败。
2. 实现最小前台启动器，使随机端口监听和现有 UDP 资源测试通过。
3. 先为 `bullet_clip_background_for_hud` 写失败测试，覆盖 72 行精确地址、
   高度、像素计数、0 行无操作和所有非法输入不修改原数据。
4. 实现最小裁剪函数。
5. 使用 CPU golden renderer 构造两份最终帧：
   - 完整背景场景 + 完整 HUD；
   - 裁剪背景场景 + 完整 HUD。
   对本地/网络地址、framebuffer A/B、多个 tick 和含跨边界 Sprite 的情况
   做逐字节相等比较。
6. 验证普通 main 仅在 GPU 模式调用，CPU 命令和 Profile 命令保持不变。
7. 运行软件回归、固件构建和相关 GPU/板级静态检查；硬件 RTL 不变，
   不重复 Efinity 布局布线。
8. 上板先验证网络零重试，再记录普通 64 档十个 CPU/GPU 窗口和 300 个
   GPU 样本；位流每次正式固件测量前重新 JTAG 加载，避免状态污染。

## 7. 性能与接受条件

必须同时满足：

- ID 101/102 板端加载字节正确、重试 0、结果 0，Cache 使用网络地址；
- CPU 命令、CPU 渲染函数和 CPU 编译路径没有性能改动；
- 裁剪前后最终帧逐字节一致；
- GPU 背景命令高度为 468、起始行 72，Profile 仍为 540 行；
- GPU 硬件错误和显示下溢增量均为 0；
- 普通 64 档 GPU `render_us` 相比纹理 Cache 基线约 9.30 ms 有可重复下降；
- 屏显 FPS、P5 和 60 FPS 判定如实记录，不因未达标而隐藏结果。

若渲染下降落入噪声或出现画面/下溢问题，撤回背景裁剪，保留独立的网口
启动修复。只有本轮通过后，才讨论双缓冲感知的脏 Tile 背景恢复。

## 8. 预计文件范围

| 文件 | 责任 |
| --- | --- |
| `scripts/run-bullet-asset-server.ps1` | 校验环境并以前台方式运行现有资源服务器 |
| `scripts/test-bullet-asset-server-launcher.ps1` | 验证启动器保持 UDP 监听且不误杀占用者 |
| `sw/efinix_gpu/include/bullet_demo.h` | 声明 GPU 背景裁剪接口 |
| `sw/efinix_gpu/src/bullet_demo.c` | 实现纯命令变换，不涉及渲染算法 |
| `sw/efinix_gpu/src/main.c` | 仅 GPU 普通模式接入裁剪 |
| `sw/efinix_gpu/tests/test_bullet_pixels.c` | 参数合同与最终像素相等测试 |
| `scripts/test-bullet-regression.ps1` | 纳入启动器和软件回归入口 |
| `README.md`、`docs/efinix_2d_gpu/` | 记录网口复现步骤、固定工作量与板测结果 |

不修改 Chisel、生成 RTL、板级 XML、约束或发布包。
