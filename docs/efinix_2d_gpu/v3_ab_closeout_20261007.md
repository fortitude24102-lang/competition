# V3 A/B 第13～14天收尾实施与记录

> 执行方式：superpowers:executing-plans，当前 A-work 内联执行；最终做一次整分支独立复核。用户要求自主执行，不停下询问设计/执行方式。

**Goal:** 在已集成的 V3 上完成 A/B 可离线实施的网页、长测留证与游戏回归收尾，交给负责人执行真实板测。

**Architecture:** 复用 main b3fc15d 已验证的网口/游戏/旧GPU，冻结 wire/APB ABI。网页仅显示完整遥测，新增只读采集与分阶段操作证据检查；C 检查消费现有输入、回放与集成运行时，不改负责人生产入口。

**Tech Stack:** Python 标准库、原生 JavaScript、现有 GCC/RISC-V/Icarus；本机没有 WSL 发行版，不安装软件。

**Spec:** v3_two_week_plan_20261001.md 第9～14天 A/B 项，v3_interface_design_20261001.md，以及 v3_freeze_20261007.md 当前资格与失败边界。

## 全局约束及取舍

- main 不修改/推送，全部新交付在 A-work；先快进同步 b3fc15d，保留官方 demo 与两份既有未跟踪波形。
- main 已完成第8天集成、第9天测量、第10/11天默认关闭实例原型拒绝、第12天冻结。512仍约30 FPS，256交互只有短测通过，1024完整固件 RAM 溢出；这些不重新实现或倒写成已达标。
- 不改生产 main/SoC adapter、GPU/CPU renderer、板级源清单/时钟、vendor、release；不增加玩法、美术或未经测量的GPU架构。
- Ruling: 重用用户指定 A-work checkout，不另建 worktree — 它已隔离 main，用户指定路径且要求不询问 — 错误代价为仅当前分支可回退提交，不涉及 main。
- Ruling: 30分钟硬件耐久/输入P95/网络P95扰动仍由负责人上板；此处提供完整留证工具与加速逻辑检查，不在本机擅自接 COM/JTAG 或声称板测 — 没有本轮开发板验收条件 — 尚需负责人补真实资格。
- Ruling: CPU采样时间不在固定27字合同中；网页只能标旧值/无效及“最后新鲜观察距今”，不能伪造精确CPU测量年龄 — 不扩展ABI — 仍需未来协议扩展才有精确采样时戳。
- Ruling: 保留既有浏览器600份有界CSV，长测使用只读流式采集文件，不改网关UDP线程或让慢磁盘/网页阻塞它 — 长测需超过2分钟历史 — HTTP采集频率/磁盘吞吐须独立控制。

## Review Focus

1. 重复SSE状态不能使旧数据/CPU旧结果变新鲜。
2. 持续采集不能无界占用内存或覆盖旧证据，失败/模拟标签必须保留。
3. 重开改变位置不能掩盖 RIGHT/UP 实际不移动；证据缺段必须拒绝，而不是判通过。
4. 多轮比较期间真人输入不进入600tick记录；回到LIVE后 held R/C 不重触发。
5. epoch更换拒绝旧回放，旧会话KEYS不能控制新会话；软件逻辑快跑不能冒充30分钟板测。

## Task 1：A 网页年龄及只读长测采集

文件：修改 tools/control_gateway/web/dashboard.js、index.html 及对应Node/浏览器检查；新增 tools/control_gateway/capture.py、tests/test_control_capture.py；更新 v3_control_usage.md。

接口：TelemetryFreshness.observe(view, now_ms)/view(now_ms)；capture.collect(base_url, output_prefix, duration, interval) 仅 GET /api/status，流式写原始JSONL及CSV，返回有界统计。固定URL仅127.0.0.1，HTTP超时/响应大小上限，独占创建输出，无游戏/键盘/寄存器写。

- [x] 先补重复SSE/过期/无效/保留CPU年龄行为测试，观察失败，再实现；Node检查期望旧数据持续过期、CPU无时戳时不伪造年龄。
- [x] 采集测试真实本机HTTP：超过600个快照不丢历史、断连与模拟标记、坏结构拒绝、已有输出不覆盖、零POST。先确认缺实现失败，再实现并检查。
- [x] 文档提供30分钟采集命令、安全边界/错误/字段口径；测试通过后提交本任务。

## Task 2：A/B 分阶段实体控制证据

文件：新增 tools/control_gateway/control_evidence.py、tests/test_control_evidence.py；最小修改 scripts/test-v3-board-control.ps1 记录RIGHT/UP/EXPIRE段并调用只读检查，不改变板卡/固件；文档更新。

接口：verify_trace(text) 返回各阶段样本、坐标变化和序号/逻辑tick摘要；CLI --serial <path> 输出JSON，缺证据或失败非零。RIGHT/UP每段至少两个同方向有效LIVE样本，tick/seq新鲜且坐标按该方向变化；EXPIRE须零键age=-1。没有阶段标记的历史证据只作历史，不能自动升级成新验收。

- [x] 先写“只有RESTART变位置但RIGHT/UP不动”失败用例、反向/缺段/旧tick拒绝、正常方向及释放通过，观察RED后实现。
- [x] 只读检查既有板测脚本语法及新标记使用；不执行COM13板测。记录main已知宽松谓词被替换，缺物理板的边界。
- [x] 测试通过后提交本任务。

## Task 3：B 收尾生命周期/长逻辑回归与交接

文件：新增 tests/test_v3_ab_lifecycle.c 和脚本 scripts/test-v3-ab-closeout.ps1；必要时仅修真正A/B自有模块问题；更新 v3_game_usage.md、README与本记录。

接口：直接调用已集成nc_poll/input_update/v3_runtime/game/replay，寄存器模型只在测试。108000个逻辑tick=30分钟逻辑量（不是30分钟墙钟或板测），交互64/256/512容量、边沿/租约/新会话、多轮600tick双后端语义、live保存恢复、epoch拒绝/换代。只用既有生产C模块，不发明主程序替代物。

- [ ] 新增跨模块回归，生产已满足的行为测试可直接PASS，不伪造RED；发现缺陷则单独补失败回归后仅修其所属模块。
- [ ] 一键入口运行Node/Python收尾测试、严格C与生产RV32编译；只回归受影响路径，不重复未改76项RTL。
- [ ] 做一次新上下文只读整分支复核，修严重问题并保存真实结果/源码哈希，提交推送A-work。

## 执行记录

2026-10-07：A-work 从 fbde986 快进同步至 b3fc15d，main未动。现有Node行为基线PASS。预检：网页/采集只消费27字快照；证据检查只消费V3_PERF串口记录；B使用负责人v3_runtime API不改其生产文件，接口无循环依赖。

Task 1：完成。Node年龄/输入/CSV行为PASS，Python采集7项PASS；真实Edge/两个启动脚本入口PASS。采集工具缺文件RED；慢HTTP回执时间曾记录为0ms（期望≥100ms）RED，按故障定位流程确认时间戳取在请求之前，改为响应后打点并GREEN。真实PC三服务同时运行：原ASST服务完整背景/图集逐字节CRC、HTTP按键→管理UDP假板ACK、文档采集脚本输出及失联释放PASS；临时端口与SIMULATED标签不冒充FPGA。未重跑未改RTL。

Task 2：完成。10项Python检查PASS，板测脚本仅做PowerShell语法检查PASS，没有运行串口。缺实现RED后新增严格检查；额外非对象phase原先抛AttributeError，补例RED后改为明确拒绝GREEN。原始串口不插入人为标记，另外保存ASCII字符偏移sidecar；仅完整落在RIGHT/UP段内且tick/seq前进的LIVE样本计入，重开移动不再抵扣方向证据。已有输出拒绝覆盖。需负责人以后用新脚本重新取物理操作证据，旧记录不升级。
