# 共享DDR占用优化原始证据（2026-10-16）

配套报告：[定位、实现、正负结果与复现](../../gpu_memory_overlap_20261016.md)。源码基线62fdc55；本轮只在本地候选分支工作，不改release/Flash。

`raw-evidence.zip`解压后：

- `measurements/`：原始串口、HTTP逐快照、采集器控制转换、仿真红/绿及错误变体、软件测试、Efinity日志、最终菜单/身份。包含失败，不只保留最快值。
- `rtl-copy256/`、`rtl-scanout/`：两种不同候选的完整生成文件和filelist，各.v/.sv只有一个模块。
- `cad-copy256/`、`cad-scanout/`：各自实际工程XML、编译日志、最终资源/时序等报告，不能互相套用。
- `bins/normal/`：原正常菜单BIN/ELF/map；`bins/probe512/`：固定普通512终止探针BIN/ELF/map。
- `identities.json`：两种候选及原Key位流、正常和512探针固件的实际绝对路径及SHA256。BIT不重复放入压缩包，避免将大位流当发布包。
- `SHA256SUMS.csv`：包内其余全部文件的逐文件校验；`raw-evidence.sha256.txt`为ZIP本身校验。

关键记录：

|问题|记录|
|---|---|
|Copy256是否有收益|`measurements/copy-oracle-*-*.log`、`candidate-phases.log`、`key-baseline-r3.log`、`return-phases.log`；无明确整机收益，关闭|
|Scanout像素/时序|`scanout-final.log`的12项；`scanout-gap-mutant.log`、`scanout-tail-mutant.log`为故意错误的RED，不是最终未修复失败|
|Scanout实板字节/像素|`scanout-copy-oracle.log`的4种Copy、哨兵、字节；不是整个游戏帧像素读回|
|普通512同BIN A/B/A|`ordinary512-baseline.log`、`ordinary512-scanout.log`、`ordinary512-return.log`；各3600帧，work11527→9618→11528us，状态CRC相同|
|旧BIT有效1040|`native-baseline-r2/performance-final.json`、`uart.log`和HTTP保持窗口；3600帧＋5秒，四异常0|
|不得计分的边界/中断|`native-baseline/`、`native-scanout/`为会话中断；`native-scanout-r2/`和`native-scanout-r3/`为同会话下1572/1568最终stage6/best0，均无performance-final.json|
|采集器保护|`keepalive-*.log`、`collector-*.log`、`software-final.log`；严格租约/3600帧不改|
|最终板卡|`final-scanout-menu/`和`final-api-status.json`；新BIT/原正常BIN，真实四档后MENU、owner释放、遥测新鲜、错误/下溢增量0|

`key-baseline.log`存在启动下溢，`key-baseline-r2.log`存在诊断仅初始化64对象问题，均已排除比较；实际使用显式初始化全部对象的`board-r3`/`key-baseline-r3.log`。不得从排除组或短窗取更好分数。

执行与审查边界见[收尾清单](execution-closeout.md)。普通512通过不等于长期耐久，旧BIT成绩不等于新BIT成绩，软件容量1819不等于60FPS极限。
