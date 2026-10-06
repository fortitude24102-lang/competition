# HDMI 热复位修复证据

[qualification.zip](qualification.zip) SHA256：`cd5bb90c1e790e2ff4780a771e686dbb26914ba7cc1ae5e962808b5bad5bd25c`。

包含修改时的 hdmi_subsystem.v / 新测试快照、旧代码RED与新代码GREEN日志、完整8项显示回归、最终资源与时序、网络实际展开SDC及全部1488数据/2请求/2确认物理路径、旧版完整重载与修复版冷/热重载的UART日志、真实网口输入和遥测记录。

`fixed-warm-1.log` 的结束条件被旧串口数据提前触发，不作新启动证明。有效热重载证据为 `fixed-warm-2.log` 和 `fixed-warm-3.log`；最后一个等待新启动后完整稳态性能行。首窗59.1～60.5FPS不作为稳态数。

新BIT在 `D:/efinity_builds/display_reset_20261006_r1/outflow/efinix_2d_gpu.bit`，SHA256 `ca4fa62b1afe977996cb40fec5bac4931b8904086b8022df7b00ed7384d850b9`；互动BIN保持 `b55d038d4d7e7973e9de2f1960087052e07bf52c4b162c3e5e7738a001562483`。只用JTAG，不写Flash。

照片和用户目视确认不在此压缩包中；最后热重载后用户另行确认“仍完整，没有再错位”。软件/时序检查与目视确认是两项独立证据。完整结论与边界见[修复记录](../../display_reset_20261006.md)。
