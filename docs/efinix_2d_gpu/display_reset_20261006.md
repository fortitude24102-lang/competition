# HDMI 热重载横向错位（2026-10-06）

## 现象与定位

照片不是两个独立场景，而是同一场景横向绕回：HUD 的开头在右侧，后半段在左侧。此前 UART/网页窗口的 60.1 FPS、underflow_delta=0 只验证性能和近期供数，不验证像素空间位置；不能据此宣称画面正确。照片中的 UFL 是累计下溢次数。

官方 Sapphire 的 debug resetOut 经 system_cores_0_debugReset、复位置一的 BufferCC_27、ddrCd_logic_inputResetTrigger 和 io_ddrMasters_0_reset，最终进入 GPU reset。因此仅执行固件加载脚本的 `reset halt`，也会重启 ScanoutDMA、清空像素 FIFO。

旧 hdmi_subsystem 的行缓存、缩放时序只使用 HDMI PLL 像素复位。GPU 重启后输出从 x=0 开始，行缓存却保留半行 write_index；它仅置 protocol_error，不纠正行起点。后续每行仍按固定 960 个像素分组，故形成持续横向绕回，FIFO 供数恢复后不必继续下溢。protocol_error 目前是内部线，不在 HUD 的 GPU ERR 中。

诊断短仿真重现：保留 640 像素的行缓存，再让上游重启，新行左端得到 x=320 而非 x=0。正式新增回归直接实例化真实 FIFO/行缓存/缩放器/编码器，旧代码在第一行 x=1 得到 0x1000，期望 0x1001，退出 1。

## 最小修复

仅 hdmi_subsystem 内部增加两个复位释放触发器：gpu_reset 或 pixel_reset 异步置位，在 pixel_clk 两级同步释放。FIFO 读端、行缓存、缩放器、编码器、下溢状态和 CDC 的像素侧共用该本地复位。FIFO 在行缓存释放前仍保持清空状态，不让新流先写入旧行起点。

接口、960×540 RGB565 / 1080p60 输出、GPU/CPU 绘制算法、网络/游戏/素材、正式 GPU 生成物和 release 均不变；不增加新 IP。只处理已确认的 GPU 热复位路径，不把任意坏包/丢像素自动重同步或像素 PLL 独立失锁下的完整上游恢复称作已实现。

## 检查与板测状态

- 新 tb_hdmi_warm_reset：GPU-only 复位发生在 1/319/640/959 像素；脉宽 2.7ns 或 51ns。每次逐像素检查两个源行的四个输出行（7,680 个输出像素），同时检查 line marker 无错误。旧代码 RED，新代码四例 GREEN。
- 回归入口：`scripts/test-efinix-verilog.ps1 -IcarusHome C:/iverilog`，新增测试也接入原 Verilator 入口。本轮完整 Windows 回归8项 exit0，包含正常整帧逐像素/时序/CDC、下溢恢复和新热复位回归；未重复运行完整长仿真或 Chisel 原型测试。
- 修复前的同版完整 JTAG 重载：r4 BIT SHA256 `8c9e4ef648d83717cf3c9782bc48412f1b744b157ab83db990c7708c82ba9f77`，互动 BIN SHA256 `b55d038d4d7e7973e9de2f1960087052e07bf52c4b162c3e5e7738a001562483`。资源101/102 result0、retry0，首窗 under0/miss0；用户确认完整画面恢复。它支持触发路径判断，但不是修复后位流验收。
- 新候选 `D:/efinity_builds/display_reset_20261006_r1` 的 map/interface/pnr/pgm exit0。整机 XLR44,624（修复前44,595，增加29）、RAM142、DSP20；解析器781 XLR/1 RAM。最终16个 setup/hold 关系非负，最小 setup0.197ns、hold0.021ns；100MHz核心 setup1.371ns、HDMI像素域 setup2.844ns。网络1488数据/2请求/2确认路径与工具实际展开约束均核对通过，最长1.027/0.604/0.546ns（门槛8ns）。两级复位释放触发器在映射网表中保留 async_reg 属性。既有旧JTAG/未用端口约束警告保留，不宣称物理MTBF或全部复位恢复/移除时间已穷尽验证。
- 新 BIT SHA256 `ca4fa62b1afe977996cb40fec5bac4931b8904086b8022df7b00ed7384d850b9`。完整回归/最终STA/网络CDC检查通过后临时JTAG加载，继续使用原互动BIN，资源101/102 result0/retry0。两次有效的仅固件热重载均看到新 V3_READY、tick 回到28/29、恢复60.1 FPS，完整捕获窗口 under0/miss0；最后一次稳态 tick59、scene8130us、P95work10480us。冷启动首窗59.9、热重载首窗60.5/59.1 FPS不当作稳态数。
- 首次仅固件重载日志 fixed-warm-1 仅抓到旧 tick418/448 的串口残留，虽然JTAG执行成功，但不能作为新启动验证。测量脚本新增清除旧串口缓冲，本轮停止条件还要求新 V3_READY 之后的性能行；fixed-warm-2/3 才是有效证据，保留失败设置日志。最终 fixed-warm-3 等待完整60.1FPS/under0/miss0/age−1行，而不是碰到中间fps片段就结束。
- 修复版真实 HTTP→UDP→FPGA→Sapphire 移动/ACK/租约释放通过（未跑CPU慢回放），x480→740、y480→192，停心跳后 keys0/age−1。上述为短窗测试，不是30分钟耐久或新增512@60成绩。最后热重载后用户确认“仍完整，没有再错位”，完成本轮空间位置验收；无持续烧录进程，保留PC资源服务和互动固件运行。
- 独立只读审查：无 Critical/Important。热复位新增用例检查 RGB/行标记，不单独逐字解码热复位后的 TMDS 或穷举 CDC 脉冲时序；现有正常输出/CDC 回归仍保留，不用单项 GREEN 冒充全部验证。
- 不写 Flash，未推送 main；先前实例原型与历史 SoC 测试异常仍单独保留，不混入此修复。

本轮诊断与日志位于 `generated/verification/v3/display-wrap/`，归档见[证据包](evidence/display-reset-20261006/README.md)，不是旧 release 的替代品。
