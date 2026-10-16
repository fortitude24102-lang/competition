# 原始证据

`raw-evidence.zip`：83文件，其中82个数据文件在压缩包内`manifest.sha256`逐项校验通过。
ZIP SHA256：`5da0e9198272907d37f79801a623f2e59b0c5e530ddb7fe70d8a32f7b267051f`。

- `full-gpu.log`：21套件91项；`stripe-edges-final.log`：补充FIXED burst/4KiB/别名尾部边界。
- `software-final28.log`：28套C＋27项真实UDP/HTTP＋身份保护。
- `hud-route-red.log`/`hud-route-green.log`：真实V3 MENU/WIN列表HUD错误先失败再通过。
- `board-old/new/key-probe512.log`：同一dc82...BIN，分别旧/联合/仅预取BIT，普通512各3600帧。
- `board-stripes-pixels.log`：首轮测试数据Y79在GPU issue之前拒绝；`board-stripes-pixels-r2.log`：修正Y80后四个完整CRC/哨兵及负性能对照。
- `native-combined/`：1048搜索中控制会话重建，未获得成绩，采集器随后按PID/命令身份终止；不冒充3600通过。
- `native-key/`：原95b...BIN＋仅预取BIT，包含1047未合格、1040复核与5秒后观察；最终串口导出3600帧完整统计。
- `stripe-app/`：真实条带完整固件资源/四档控制可用，但低档也可见30FPS，不宣称性能合格。
- `final-menu/`、`final-status.json`：恢复仅预取BIT＋原正常固件，四档控制、最终MENU/无owner/新鲜状态。
- `combined/`、`key/`：候选最终资源/时序；使用最终route而非中间placement结果。
- `fw-probe512/`、`fw-stripes-final/`：实际诊断/条带BIN、ELF与链接图；原95b正常菜单BIN沿用前一轮归档/生成目录，不冒充新构建。

Render字节计数含片上访问，不等于物理DDR字节；隔离像素测试无Scanout，不是1819@60证据。报告见上级`row_stream_and_stripes_20261016.md`。本次只JTAG，未写Flash；未修改CPU基础渲染、资格规则或掩盖负结果。
