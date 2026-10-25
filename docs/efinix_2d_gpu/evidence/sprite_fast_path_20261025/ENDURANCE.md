# 普通1024连续108000帧（2026-10-25）

精灵短路径版本完成连续108000帧，约30分钟，逐帧work超预算、迟到、下溢及错误均0。最大work14.518ms，最大wall16.639ms，平均work9.076ms；可见范围1006..1016、Alpha130..131保持。这里同时检查最大wall低于16.667ms，未仅依赖原late计数器的25ms门槛。

|字段|真实汇总|
|---|---:|
|frames|108000|
|fps_x10|601|
|work_mean_us|9076|
|work_max_us|14518|
|wall_max_us|16639|
|work_miss / late_present / under / errors|0 / 0 / 0 / 0|
|visible_min / visible_max|1006 / 1016|
|alpha_min / alpha_max|130 / 131|

同一Alpha提前读BIT `ef240664…`，长探针BIN `25b5fe36…`，LogicCopy1、SealWords256、HudDirect1固定。完整SHA256和源/ELF/BIN/映射已在本目录原evidence.zip内，SHA256 `4c39d3a339450dabfb2258e6794875b9ef0f86d6a4ba8e577dcca5e27fee78a3`；对应精灵实现65881b9。长探针只增加采样帧数，期间CPU逻辑仍为该版本，后来29a0241的逻辑移位没有加载到此实验，新的QoS候选也没有加载。

使用真实普通游戏逻辑，固定中立输入，包含死亡及自动重启；不进入挑战、CPU绘图比较、WIN或MENU，不减少活动对象来凑成绩。原600输入封存CRC为a7bd652f，它不是游戏全状态或帧缓冲CRC。该长期证据仍限于这组输入与场景，不是任意操作或冷启动保证。

执行句柄38195已由write_stdin确认终止exit0。长测结束后完成真实六档菜单检查，选用正常808c2c51…BIN＋同一候选BIT；最终状态真实、新鲜、未持有、MENU。测试只写JTAG RAM，没有写Flash、发布或推送。随后才能启动下一组独立实验。

endurance.zip单独保存原始UART、采集输出、完整汇总、结束菜单/状态、实际脚本及输入身份；不覆盖原阶段ZIP。全部载荷按manifest逐文件回读检查，SHA256见ENDURANCE_SHA256SUMS。完整目标还需CPU/GPU/DDR上界与后续硬件验证，保持active。

长验证包74,944字节、16条目、102条状态JSONL解析通过；SHA256为`cdd1d164530867758b34fb3f7af0474a3e255dcf84dd8f88e4e2ccb292012b91`。主包源码中的原逻辑已与保存的65881b9基线逐字节核对，避免将后来未参与本实验的改动混入长证据。
