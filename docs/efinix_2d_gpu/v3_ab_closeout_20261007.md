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

- [x] 新增跨模块回归，生产已满足的行为测试可直接PASS，不伪造RED；发现缺陷则单独补失败回归后仅修其所属模块。
- [x] 一键入口运行Node/Python收尾测试、严格C与生产RV32编译；只回归受影响路径，不重复未改76项RTL。
- [x] 做一次新上下文只读整分支复核，修严重问题并保存真实结果/源码哈希，完成交付提交；推送结果以远端确认与对话回报为准。

## 执行记录

2026-10-07：A-work 从 fbde986 快进同步至 b3fc15d，main未动。现有Node行为基线PASS。预检：网页/采集只消费27字快照；证据检查只消费V3_PERF串口记录；B使用负责人v3_runtime API不改其生产文件，接口无循环依赖。

Task 1：完成。Node年龄/输入/CSV行为PASS，Python采集7项PASS；真实Edge/两个启动脚本入口PASS。采集工具缺文件RED；慢HTTP回执时间曾记录为0ms（期望≥100ms）RED，按故障定位流程确认时间戳取在请求之前，改为响应后打点并GREEN。真实PC三服务同时运行：原ASST服务完整背景/图集逐字节CRC、HTTP按键→管理UDP假板ACK、文档采集脚本输出及失联释放PASS；临时端口与SIMULATED标签不冒充FPGA。未重跑未改RTL。

Task 2：完成。10项Python检查PASS，板测脚本仅做PowerShell语法检查PASS，没有运行串口。缺实现RED后新增严格检查；额外非对象phase原先抛AttributeError，补例RED后改为明确拒绝GREEN。原始串口不插入人为标记，另外保存ASCII字符偏移sidecar；仅完整落在RIGHT/UP段内且tick/seq前进的LIVE样本计入，重开移动不再抵扣方向证据。已有输出拒绝覆盖。需负责人以后用新脚本重新取物理操作证据，旧记录不升级。

Task 3：离线收尾完成。2026-10-07最终运行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-v3-ab-closeout.ps1` 返回0，完整原始日志位于 `generated/verification/v3/ab-closeout-20261007-195639-941`；[源码哈希/准确资格回执](evidence/v3/ab-closeout-20261007/receipt.json) 随分支交付。8个严格C套件、Node行为、Python45项（19网关+7采集+15控制证据+1资源+1三服务+2入口保护）PASS。108000计划内LIVE更新+18恢复LIVE更新、21600回放更新、18次比较；每步全部规范状态/命令字段一致，Alpha保留。6个生产RV32对象成功，text合计8644 B、data/bss均0，单函数栈最高272 B；不是固件链接或整机栈证明。新生命周期测试消费已经合格的生产API，首跑PASS，不伪造功能实现RED。复核前40项的旧日志保留在 `ab-closeout-20261007-194843-271`，不覆盖历史。

额外入口保护验证缺失Node会非零退出、没有PASS回执，已有输出保持原内容。收尾入口本身恢复临时环境变量，并为每次测试创建独占目录。没有修改生产C、板级RTL、GPU、SoC胶合、工程源清单或release，没有运行串口/板测。文档修正旧“恢复LIVE清零输入去重”的危险建议，与main已修复的动作序号保持行为一致。

## 负责人剩余验收（不计入A/B离线完成）

1. 第13天同版消融、像素净收益、可见/Key/Alpha数量、最坏帧、扫描水位、资源/时序报告；不重新启用已经拒绝的实例候选。
2. 第14天真实≥30分钟高负载互动+遥测，冷启动/完整复位/热重载/缺服务器/断网/比较恢复矩阵，以及输入P95≤100ms条件、网页开关/慢连接的GPU P95增量。
3. 使用新的分阶段控制脚本取RIGHT/UP/释放证据，CPU慢600tick回放及GPU同记录结果；A/B本轮没有物理板测资格，历史板测不覆盖新脚本。
4. 候选异常与512@60、1024RAM失败仍留档；旧SoftwareDriverSpec/PangoBringupSpec异常不由本轮定向通过消除。release/v3位流/固件/资源/哈希由负责人完成，release/v2不变。

## 一次整分支复核与结论

执行计划要求的唯一新上下文只读复核（b3fc15d..8826a7e）：无Critical、无Minor，发现1个Important/P2。EXPIRE原先过滤掉非零键反证，只需出现一次零键便会通过；还会接受UP之后的旧tick释放记录。该问题属于证据门误判，不说明生产驱动租约有缺陷。

Final: fixed EXPIRE反证丢失/跨阶段旧tick — `test_release_cannot_hide_subsequent_reasserted_keys`、`test_old_expiry_cannot_follow_newer_up_phase`、`test_release_rejects_stale_grace_or_backward_input_sequence`、`test_direction_phase_chronology_cannot_restart` 实际RED→GREEN；最终45/45 Python、8/8严格C、Node、6/6RV32及脚本语法PASS。允许初始租约宽限，释放后每条记录继续检查而非过滤；按实际nc_poll的断开seq清零语义处理。只做这一轮修复，无重复复核派发。

独立复核没有认定下列资格，逐项采纳为明确边界，而非待修改的软件问题：

- Final: Ruling: 真实RIGHT/UP/释放、CPU慢回放与长按R/C仍依赖上板 — 本轮不连接硬件，离线工具不能升级为物理表现 — 代价为新物理证据仍需负责人补齐。
- Final: Ruling: ≥30分钟墙钟耐久、输入P95及网页/慢连接GPU P95扰动不由快跑验证 — 逻辑量与物理时间不同 — 代价为最终耐久和延迟资格仍未取得。
- Final: Ruling: HDMI目视、最终像素、冷启动/复位/热重载/缺服务/断网矩阵不重新认证 — 本轮无硬件/绘图修改，保留已存在像素证据且不拓宽 — 代价为新最终矩阵需另测。
- Final: Ruling: RTL时序/CDC/PHY/资源/消融净收益归负责人 — 冻结且未改的硬件不重复长仿真或综合 — 代价为新封版资源/收益报告仍须负责人与实际候选配套。
- Final: Ruling: RV32对象不证明完整链接RAM/动态栈 — 当前只有模块编译和静态栈报告 — 代价为容量/整机栈最终资格仍需map和实测高水位。
- Final: Ruling: 512稳定60、1024可运行、正式release和历史SoC异常没有被本轮证明 — main实际失败边界保留 — 代价为这些目标/异常仍未完成，不能据此封版。
- Final: Ruling: 不宣称未改生产入口/渲染器/既有模块全面正确 — 定向生命周期只覆盖相关接口 — 代价为其他未覆盖问题仍可能存在。

Deferred minors：无。全部本轮交付在A-work，main及release不改；临时复核副本可清理，原始测试日志和用户工作目录保留。
