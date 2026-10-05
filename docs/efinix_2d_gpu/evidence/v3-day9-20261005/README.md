# 第9天原始证据

`day9.zip`包含如下原始文件，未修改日志内容：

| 文件 | SHA256 | 含义 |
|---|---|---|
|render-phases-20261005.log|6941e242dbc8aef1c3f7d0f23d06a2cf14bda4074787c6ba3de38f6c14e8de3a|十组300帧：五档正常/提交探针；30个隔离阶段；完整STOP result0/hardware0|
|test.bin|3ff9c53396ed8df8b83aa293071d7e50c9646c3e2624e15afa2529c9d1f0ea37|本次加载的诊断固件，地址0x1000，仅JTAG|
|restore-20261005.log|0ad722413e241d81833226e83f103e0d88ccc41e405dffe93d40a411e69665e9|恢复原交互固件后的串口；捕获脚本误写不存在的V3_FPS停止模式，75秒后超时，不能称脚本通过；固件实际持续输出V3_PERF、under/miss0|
|restore-control-20261005.serial.log|eb52dac376116bcf8e7115a735f318a1f55e53eb09520b1471228b962150baf2|随后独立真实控制检查，RIGHT/UP被Sapphire消费、坐标改变、输入过期释放|
|restore-control-20261005.status.jsonl|ec2fb38cd5fc7adf334e02451cb3c85827fdcf7301ca1602373455cd88cfd28a|独立检查完整HTTP快照；真实ACK和遥测，非模拟|

恢复未重复下载或烧写Flash：r3 BIT/BIN加载成功，随后运行`scripts/test-v3-board-control.ps1 -Out generated/verification/v3/day9/restore-control-20261005`退出0。原网关通过新HELLO/ACK重新接收同build复位后的序号，没有降低旧包过滤或重启其他服务。网关历史drop计数包含拒绝旧序号的恢复阶段，不能当成链路丢包率。收尾API真实/stale=false、GPU6010(×100)、CPU显示null、under/error/miss0，无OpenOCD/烧录进程。

最终交互固件SHA256仍为`b55d038d4d7e7973e9de2f1960087052e07bf52c4b162c3e5e7738a001562483`；r3 BIT哈希及正常测量口径见[v3_decision_day9.md](../../v3_decision_day9.md)。源基点7af83b3加该次诊断文件差异；不是新的功能发布包或耐久证明。
