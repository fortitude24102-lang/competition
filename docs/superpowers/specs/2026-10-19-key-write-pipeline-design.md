# Key专用双在途写

依据4e67dd7的实板等待分解：1040 Key窗口约3.52259ms，B尾等待1.47104ms/41.76%，W背压0。背景B尾仅0.235ms，因此不先重写通用Copy。目标是增加相同工作量下60FPS余量和活动Sprite上限，不预报百分比或新纪录。

候选`enableKeyWritePipeline=false` / `--key-write-pipeline`必须同时开KeyPrefetch，首版不得与KeyRowTrim同时启用。保留原AxiWriteEngine及全部Copy/Alpha/Sparse/Transform调用，仅缓存Key使用新AxiWritePipeline，接口沿用request/data/done/error。数据不交错、AW ID0、每请求按256拍和4KiB切分，最后一个B才产生该请求done/error。最多两笔burst在途；下一行只能在上一行最后W数据被接受后开始，不额外收集整行。

CachedKeyStream候选用最后W推进行地址，另计已接受但未B退休的行数；完整源行credit、源读完成、FIFO排空、错误排空不放宽。错误到达时停止新行，排空已接受行的所有W/B；允许错误前已承诺第二行被修改，但下一命令不得看到残留。每条Key命令只完成一次，必须等全部B。默认路径不变。

DdrQosArbiter候选用深度2的B-owner FIFO：新AW选择前预留响应容量，W所有权保持到WLAST，WLAST入owner队列后释放AW/W调度，B独立按队首回原Render/Asset。禁止混淆AW/W当前owner与B owner。保持已呈现AW的稳定、显示紧急准入、Render公平限制；不靠改显示阈值换性能。诊断B尾事件改按候选响应队首归属，可能与有效W重叠，不能全部称为浪费。

官方Sapphire、CPU绘图、100MHz、DDR/HDMI/网口、C32命令、场景和Alpha/Key顺序不变。只JTAG/RAM，不推送/Flash/release。独立生成默认关闭/候选各保留证据，先真实背压和故障测试，最终全时序为正才上板。相同旧分段BIN、同一新诊断BIN和同一普通512 BIN分别A/B/A；分段不是FPS资格，有净收益再保留，不因局部周期改善启用。

RTL检测行W尾、同拍新请求/B退休、4KiB拆分第一B不得完成、两笔满credit、B/R错误后继Fill、Asset交错、显示紧急入场、B背压和AW稳定。现有旧测试只能证明旧路径，候选必须用支持排队多个B的总线模型。先限定每Key内部重叠，不跨命令重排。
