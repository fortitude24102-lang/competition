# 整帧列表顶层集成与实测

目的：完成dffa52d基础部件的实际GPU命令前端，消除逐Sprite APB提交；Sapphire仍更新游戏并直接生成列表，PC仅资源/控制/遥测。用户免中间审批、亲自执行；本地分支，不推送、不写Flash。

采用完整预取→现有模板展开/验证→现有16项渲染队列。拒绝重新引入逐实例APB循环；不新增CDMA/物理DDR端口、Cache或超频。候选默认关闭，生成器显式--frame-lists，沿用--legacy-copy以匹配合格硬件。

## 硬件契约

Efinix2dGpuTop新增enableFrameLists=false；启用时复用InstanceStream(enableFrameList=true)的模板RAM/统一验证/held命令，保留0400 API。新增FrameListBatch负责0500 APB、Reader请求、epoch、issued计数和排空。旧STATUS bit15能力，bit14模板API同时存在。候选沿用注册APB响应。

0500 ID=0x464c5431；0504 STATUS：bit0active、bit1sticky done、bit2error、bit3fetching、[15:8]错误码；0508 CONTROL写1START/4CLEAR(done/error，仅inactive)；050c地址、0510count、0514首tag(16bit)、0518epoch仅inactive可写；051c完成epoch、0520末issued tag、0524issued、0528预取字节只读。START只在后端/缓存/模板前端全idle且无硬件错误时接受；地址/count由Reader有界校验。忙态0500写失败不改变当前批。

START原子锁定模板及旧SUBMIT/缓存管理；完整预取成功才输出描述符。原Reader ID6临时复用DDR render AR/R，只在后端确实空闲时取得通路，最后R已被消费后归还；AW/W/B不变，Scanout/Asset及原QoS/FIFO不变。Reader.done为单周期运输事件，Batch.done为软件可轮询sticky状态，只有Reader结束、模板暂存全空、真实render/cache idle时完成并释放锁。RenderEngine仅候选启用可选frontend busy/read/stalled事件，原GPU counters计入预取及前端等待/读取字节，不把新增阶段漏计为零成本。

自动展开仍检查header、完整模板、尺寸/跨度/溢出、DDR边界、步长/对齐与统一CommandValidator；tag按成功验证的命令递增16bit回绕。记录真实queue握手issued。错误后剩余已预取描述符丢弃、已接受队列排空，完成带错误，禁止PRESENT及从头重放。失败/无响应不强行局部复位；需全SoC/响应端一起安全恢复。中途局部AXI复位不支持，正常候选不自动尝试。

## 软件契约

新增gpu_frame_list.h/c：init(gpu_frame_list*,gpu_device*,int network)，render(gpu_frame_list*,uint32_t address,unsigned count,uint32_t epoch,uint32_t polls)。init先读安全旧STATUS，没有bit15不碰0500/0400，不自动假装走新硬件。启用时使用已有模板API初始化12模板。

render等待原outstanding完成，再一次START；成功核对完成epoch、issued=count、末tag和旧ERROR，再一次更新软件tag/提交计数，避免uint8 outstanding装入整批。失败active保持，阻止盲重试；不重放旧路径。发布前调用现有gpu_platform_sync（官方fence/自定义data cache invalidate路径，CSR810不存在不使用），不改CPU绘图配置。

固件开关V3_FRAME_LIST（构建-FrameList，单独输出目录，不发布release）。两16KiB DDR列表bank仍为02d20000/02d24000；对应目标A/B。直接构建manual1当前游戏；只填scene统计供HUD/采样，不复制旧命令。CopyAhead时背景先提交，在CPU直接构建后等原Copy完成；列表跳过第0条背景，维持一次Copy和Alpha/Key顺序。非CopyAhead提交完整列表。CPU/menu及旧GPU回退保持原代码。epoch使用scene_generation，一批执行期间素材/模板/列表只由此单一GPU拥有者管理；资源下载仍仅启动时，不能宣称可并发任意素材更新。

## 验收与退出

真实Top AXI像素顺序、burst/延迟B、late错误零部分输出、非法descriptor只执行合法前缀不重放、template锁/legacy互斥、epoch/tag回绕及完成栅栏；C MMIO真实驱动安全探测/有界超时/错误不重试，当前游戏构建等价继续成立；完整GPU回归、18C/23网络回归。

生成物放独立verification目录，板工程新目录不改正式清单。必须100MHz最终setup/hold、网络CDC及资源合格才JTAG。正常/终止BIN均先检查软件RAM，不能扩大官方内存或优化CPU来掩盖溢出。若空间不足，仅对候选未使用AUTO-R7故障回退移除引用，CPU公平回放不动，并显式记录。

同BIT/BIN终止控制02d10004选择旧/新/旧，各30预热+600采样，256/512，真实可见/Alpha/Copy/HUD/输入一致，报告构建/发布等待/硬件busy/工作分布/迟到/下溢/错误。平均FPS不足以证明稳定60；候选无净收益则不默认启用并恢复原合格BIT/正常菜单，仅JTAG。不具备板卡或时序不通过须如实报告未完成验收。
