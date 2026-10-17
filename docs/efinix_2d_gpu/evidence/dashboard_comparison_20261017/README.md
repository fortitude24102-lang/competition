# 网页对照与实板专项计数证据（2026-10-17）

基线631b4c5；复用既有静态页面、原生JS/Python标准库、现有帧列表/CLINT/性能计数器。Ponytail指导不新增框架、依赖、生产探针或RTL。前一轮普通512/Copy的证据ZIP不改；本目录仅存新固件计数。

`raw-evidence.zip`：

- `board/test.bin`、`test.elf`、测试固件C和两份构建/采集脚本；BIN SHA256 `d8b18ca4f494cb4795b2e773936b190f4329bd632f3f2cfa06a6aa9b35bbdfe4`。
- `kernel-before-r3.log`、`kernel-after-r3.log`、`kernel-return-r3.log`是唯一正式A/B/A；同BIN、同场景、同种子7、每档30预热＋600连续PRESENT间隔，无串口计时扰动。
- 三组硬件处理像素、读写/Cache字节、末态/list CRC相同。512每组处理294873600像素，1536为345254400；三组测量窗新增下溢/错误0。
- 512工作均值11.948502→9.283675→11.949217ms；1536为21.493647→17.165835→21.493080ms。1536前后都600帧超60Hz预算，均约30.05FPS，不是新资格成绩。
- `excluded/`保留最初r2记录（首测间隔截去快照开销）、故意保留错误边界的RED固件日志。窗口恒等式`wall==previous-window_start`在板上先失败，去掉错误时间重置后r3三组通过。排除组不参与JSON比较。
- `restored-menu/`、`restored-menu-console.log`、`final-api-status.json`：恢复Scanout候选BIT＋原95b...正常BIN，资源101/102/103成功、四档START/MENU通过、MENU/owner释放/新鲜遥测/健康增量0。UART启动累计under=379080单独保留，不把窗口增量0说成启动累计0。
- `identities.json`为本次实际BIN/源码/两种BIT SHA256；`SHA256SUMS.csv`为包内文件校验，ZIP自身校验在同目录。

新指标定义/使用见[说明](../../v3_control_usage.md)。CPU仅“逻辑＋构建”是可归属已测部分；GPU render-call/PRESENT含忙等，busy含待换帧。处理像素含透明Key；DDR字段为GPU侧有效负载而非物理总利用率。顺序专项没有CopyAhead、HUD、网口管理；不是普通游戏或3600帧挑战。

审查收尾：网页审查确认统计口径、有效性和白名单；指出最终过期模式文字和静态资格假设已用测试/保护处理，浏览器旧空文本谓词已改查实际固件号。固件只读审查无Critical/Important，指出首间隔边界问题后实际板上RED→GREEN并以r3重采。审查未判断的浏览器和板测由执行方实际检查补证，物理CPU/DDR利用率、30分钟耐久、HDMI人工目视未补称通过。所有JTAG/测量进程已退出，不写Flash、不推送、不替换release；仅保留资源服务器及网页网关。
