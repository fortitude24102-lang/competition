# Copy地址等待期间预取：小幅帧收益与资源余量（2026-10-26）

提交4d8378d复用原两字缓冲，在已提交完整bank的AW等待期间预取同步RAM，W仍等AW接受。普通游戏同D731 BIN的A/B/A及重复各3600帧：

|组|平均work us|最大work us|最大wall us|超预算/迟到/下溢/错误|
|---|---:|---:|---:|---|
|E0控制A1|8778|12903|16639|全部0|
|Copy预取B1|8774|13077|16639|全部0|
|E0控制A2|8778|12961|16639|全部0|
|Copy预取B2|8774|14110|16639|全部0|

按整数微秒输出均值，减少4us、约0.04557%，幅度很小。候选最大work并未更低，不能宣称尾部改善。合计14400帧、候选7200帧；NETWORK1/LIVE1024、build20261015、epoch30002、可见1006..1016、Alpha130..131和600输入封存a7bd652f相同。该CRC只认证封存输入。

16项Copy、96项Alpha离屏黄金、96个LOCAL0阶段窗口通过，fixture/数量/接口字节相同；LOCAL固定阶段与NETWORK普通场景分开解释。独立Copy trial0为1841→1784→1836→1782us，但固定阶段BACKGROUND的混合窗口并未一致加快，不把单项约3%的差值推广为整帧收益或恒定Copy加速。原始分项全部保留。

## 借鉴机制与最小实现

- [verilog-axi axi_cdma，516bd5d](https://github.com/alexforencich/verilog-axi/blob/516bd5dadc3365b7f9e225d2af8fe0b8d804fe53/rtl/axi_cdma.v)：地址/数据独立分级，利用既有缓冲隐藏延迟。
- [PULP axi_mux，70b8e54](https://github.com/pulp-platform/axi/blob/70b8e54fd460e3308e58be596ceb3566a6e3576e/src/axi_mux.sv)：已呈现地址锁定、写数据归属与响应分离；其ID扩展不适合本板直接移植。

只借机制，没有复制第三方RTL、引入库、扩大信用或添加缓冲。fetch/send索引在bank提交时初始化，AW接受时不清掉已预取的字；fetch允许awPending或wActive，外部W仍由wActive保护。bank至B退休，abort/fault继续兑现已承诺的AW/W/B。

新真实事务测试在旧代码先失败：1/64拍、AW无等待/阻塞8拍，首W均为AW接受后第3拍。新实现分别第2/第1拍；逐字、last、strb、AW前无W、B退休和重复使用通过。DMA5/5（含跨页、错误和GPU-only abort）及渲染/顶层/MUX/配置15/15通过，独立只读审查无重要问题。不是全仓所有测试的声明。

## 物理与输入身份

|项目|E0控制6a8d19dd|Copy预取de149efd|
|---|---:|---:|
|XLR|54526|54349|
|距54720门槛余量|194|371|
|RAM / DSP|186 / 38|186 / 38|
|core setup / hold ns|+0.142 / +0.026|+0.236 / +0.026|
|最终时序|16项严格正|16项严格正|

少177是这两次实际映射的差异，不保证任意重新布局的同等变化。core保持100MHz；实际1488个CDC data路径最大1.199ns，request2个最大0.969ns、ack2个最大0.894ns，生效8ns约束与实际路径通过。

18项features一致。38份Scala仅WideCopyDma变化；70份生成物仅WideCopyDma.sv及它的断言文件变化，断言差异只在源码位置注释。控制E0源摘要e0efa379…，候选0a0b96f1…；这是单源文件优化，不称为同源码功能开关对照。原compare-gpu-build要求不放宽，自比较只检查候选清单，实际旧/新差异另独立核对。

原预检查因准备XML的2025.2格式版本与已安装/归档2026.1.132不同而拒绝，原文件保留，仅对齐已核验的工具版本后才冻结238项并首次编译。原执行25972最后因Efinity重写XML声明/换行而退出1，失败保留：精确重建的编译前XML SHA匹配冻结dc9f…，编译后5171…；前后ET.tostring完全相等，其他237份原始字节相同。没有泛化XML例外或放宽器件、seed、综合/P&R检查。后续独立资格1071退出0，最终238项另冻结复核；独立只读审查重算全部输入、源/RTL、BIT、时序和实际路由，同意该确定BIT进入实验。

静态source-change记录中的physical/board=false只表示该检查本身不认证物理或板测；当前资格以独立physical-result和完整板测/选用记录为准，不把原wrapper失败改写为成功。

控制BIT完整SHA：`6a8d19ddd10f2ac9fbef59d874113206aebfa63fe90268f571830c2e24928442`。
候选BIT完整SHA：`de149efdc78e1dded2c0e070efe52cd8e5e70fdc52e577dd7061c94902c72879`。
普通探针：`d731f59769989ee44b49a08709acfeab57cc4bc0d9dad4995ad07185c494d1f6`。
正常BIN：`6000d1559cccaa91b340e2881db2afaed5c693cac2aa2e863f0340edb9c50b3c`。

## 当前选用与剩余工作

板测15855已exit0并先恢复旧EF正常MENU。随后独立24749用新de149efd＋原6000d155 BIN完成真实六档菜单、释放控制，选作后续验证组合；没有写Flash或覆盖release。新组合尚无自己的108000帧长成绩，也没有新容量成绩。原65881b9在旧硬件的108000帧不可挪用。主要实际改善是资源余量，继续优先验证长期稳定及定位CPU/GPU等待，不为这点均值变化立即重跑大规模容量搜索。

本组与[读容量零净收益/930帧诊断补充](../read_capacity_admission_20261026/BOARD.md)分开封存，原归档保持原字节。

归档大小及SHA256见[artifact-manifest.json](artifact-manifest.json)，逐载荷校验见[SHA256SUMS](SHA256SUMS)。
