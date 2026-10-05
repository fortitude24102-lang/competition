# V3 local control gateway (member A)

源码基点：`79a0b7f`，A-work 独立模块。协议依据 `v3_interface_design_20261001.md`；本工具不修改主程序、SoC 顶层、GPU 或 ASST。Python 标准库及原生 HTML/JavaScript，无安装依赖。这里只证明本地软件/假板合同，不能代表实际板卡、HDMI、性能或整机耐久已验收。

## 启动真实板卡

在仓库根目录运行；将板卡地址和 PC 网卡地址替换为实际配置：

```powershell
powershell -File scripts/run-control-gateway.ps1 -BoardIp 192.168.1.50 -UdpBind 192.168.1.100
```

HTTP 固定绑定 `127.0.0.1`，默认端口 `8765`。打开 `http://127.0.0.1:8765/`（不要用 localhost 别名）。网关 UDP 默认监听 `0.0.0.0:8090`，可通过 `-UdpBind` 限定本机网卡；目的地址/端口启动时固定，默认板卡 UDP `8090`，收到 UDP 仅接受该地址及端口。板端必须把管理 ACK/遥测发送到该 PC 的 `8090`。`-BoardPort`、`-UdpPort`、`-HttpPort` 可调整；浏览器端不提供目的地址或任意包发送入口。原 ASST 资源服务继续单独监听 UDP `8080`。

已有 Python 可通过 `-Python C:/efinity/efinity/python311/bin/python.exe` 指定；启动脚本会在运行期间设置该发行版所需的 `PYTHONHOME`，退出时恢复原值。脚本不会杀未知进程、修改网卡或防火墙、安装依赖。端口占用会失败退出。Ctrl+C 退出网关时尽力发送零键；板端自己的 250 ms 租约仍需开启。

若当前 Windows 执行策略禁止本地脚本，可在上述 `powershell` 调用中加入 `-ExecutionPolicy Bypass`，仅作用于这次 PowerShell 进程；工具不会改系统执行策略。也可直接运行相同参数的 `gateway.py`/`fake_board.py`。

## 假板演示（明确为模拟）

两个终端分别运行：

```powershell
powershell -File scripts/run-control-gateway.ps1 -FakeBoardOnly -Python C:/efinity/efinity/python311/bin/python.exe
powershell -File scripts/run-control-gateway.ps1 -Simulated -Python C:/efinity/efinity/python311/bin/python.exe
```

假板默认监听 `127.0.0.1:8091`、仅向固定 `127.0.0.1:8090` 回传；网页与终端显示 **SIMULATED / not board measurements**。它仅实现协议校验、HELLO ACK、完整键状态/序号的接收与租约、每秒 5 个完整遥测回显。不进行游戏更新、碰撞、AI、坐标、绘图或命令生成，也不伪造 FPS。`firmware_build_id=0x53494d31`（SIM1），`simulation_tick` 在这个明确模拟工具中仅回显收到的输入序号；只有输入/网络组有效，FPS/耗时/流量/Alpha 等显示 Unavailable。键掩码保存在假板接收状态供测试核验，不被当作 Sprite 数量。

## 键盘、所有权与失联

点击 “Acquire control in this tab” 获取独占浏览器控制；另一页的 POST 返回 409，界面给出明确提示，不能悄悄抢键。查看遥测无需获取控制。方向键/WASD 为左、右、上、下；Space/Z 射击；Shift 慢速；R 重开；C 请求比较回放。R/C 仅在新按下边沿推进 `action_sequence`；按键重复事件不重复执行动作。实际效果和比较模式决策由 Sapphire 实现。

浏览器每 33 ms 最多一个 POST，在途请求最多一个，慢 POST 期间只覆盖为最新完整状态。同一动作的别名键均释放后才清相应位。失焦、页面隐藏、关闭或点击释放时清键并发送零键释放；返回页面后须重新点击获取控制。关闭时若浏览器取消请求，网关从最后有效浏览器心跳起 250 ms 发送最后一个零键包、释放所有权并停止发包。板端独立租约处理 UDP 零包丢失。没有浏览器控制时不主动持续发送 HELLO/旧键。

每次控制会话产生新非零随机 session；只有配置板端对当前已发 HELLO 的正确 ACK（同 session/sequence、数据 1/0/0、CRC 正确、HELLO 发出后 250 ms 内）才能转发非零键。HELLO 全零，最多 2 次/秒；500 ms 重试已超过板端租约，因此每次未确认重试使用新 session。所有 UDP 发送（包括零键/HELLO）合计不超过 60 包/秒。新会话拒绝旧 ACK；板端复位/无控制状态或 500 ms 缺少新板端证据会重握手。无新证据时先清旧会话并让其租约到期，再获取新 session。板端启动/失联时仍必须默认零键，重复/过时 KEYS 不刷新板端租约。

## 遥测展示、有效性与导出

只接受 128 B AGT1 完整包，CRC 正确后一次发布 27 字；不会逐字段拼接。Sapphire 的 snapshot_id 是设备全局计数，同固件身份下跨所有控制/观察 session 和资源 epoch 按模 2^32 序号拒绝重复/过时/半区差值；切换 session 或资源不绕过检查。例如活动快照 100 后迟到的 session=0 快照 99 会被丢弃，不能覆盖数据或撤销正确 ACK；真正更新的观察快照 101 仍可标出控制已释放并启动恢复。无控制 session=0 可观察；有控制时仅当前 session 或观察者 session=0 可被接收。保留最多 4 个已退休固件身份以丢弃延迟旧固件包。500 ms 无新快照显示 stale，网页 SSE 中断也标过期并释放控制；SSE 状态刷新不是新遥测。

status_flags bit16～22 对应 GPU 帧时间/FPS、CPU FPS、细分探针、流量、错误/下溢、输入/网络、Alpha/Key 有效组；无有效位显示 Unavailable。bit5 标注 CPU 保留结果已过期。页面展示板端 full-frame FPS，不从 busy_us 推算显示帧率，不运行游戏。原始字段单位沿名称（`*_us` 微秒、`*_bytes` 字节、`*_delta` 窗口增量、FPS ×100），流量/事件窗口最长 1 s，帧/窗口语义由板端状态标注。

网页保留最近 600 个原始完整快照，图表保留最近 120 个；CSV 含接收 UTC、session、snapshot_id 和原始 27 个 u32（包括无效字段的原始值及 flags），导出不会把无效值改写为零。历史与 CSV 仅存在当前网页内存，刷新页面会清空。收包保持一个最新快照，最多 8 个 SSE 查看连接、16 个 HTTP 工作线程、500 ms socket 超时，慢客户端写入不持有 UDP 状态锁；高压收包按每轮最多 32 个数据报让出发送/租约检查机会。

协议没有独立 boot nonce。相同固件复位且 snapshot_id 重置，无法仅凭 session=0 观察包与延迟旧包可靠区分；网关保守拒绝倒退。旧快照已至少 500 ms 过期且收到新的随机 session 的正确 HELLO ACK 后，只允许该新非零 session 的第一个控制已握手（status bit4）快照重建序号基线；这个机会使用一次即撤销，旧 ACK 和观察包都不能触发重建。普通快速浏览器释放/获取仍保持全局序号检查。实际同固件复位可经过过期/看门狗与新 ACK 恢复，因此需要等待这段保守恢复时间；纯观察模式可获取一次新的控制会话或重启网关恢复。回退到最近已退休固件版本也需重启网关。新基线建立后，复位前 session=0 包若恰好表现为新基线的更新序号，协议仍无法证明其启动身份，不能宣称具有 boot nonce 级别的抗延迟包保证。IP/端口过滤不是 UDP 身份认证，请在可信本地板卡网络中使用。

## 本地 HTTP 合同与安全边界

仅 `GET /`、`/dashboard.js`、`/styles.css` 提供固定本地页面文件；`GET /api/bootstrap` 返回随机网关 CSRF token 及模拟标签；`GET /api/status` 返回当前原子状态；`GET /api/events` 为 SSE 最新状态流。所有请求要求 Host 为当前 `127.0.0.1:端口`，POST 要求完全匹配的同源 Origin、JSON Content-Type、最多 1024 B Content-Length、随机 token 及每页 32 位十六进制 client 标识。

```json
{"token":"64 hex chars from bootstrap","client":"32 hex chars unique to this page","keys":0,"action_sequence":0,"release":false}
```

keys 仅接受整数 0..255（不接受 bool），action_sequence 为 u32；release 为 bool，true 时 keys 必须为零。多余/缺少字段拒绝。没有任意本机目录、远程文件、远程执行、任意寄存器、修改板端地址的 HTTP 功能；这不是公网服务器。

错误：400 JSON/字段/长度头无效，403 Origin/Host/token 错误，404 不在固定端点清单，409 其他浏览器持有控制，413 超过 1024 B，415 非 JSON，503 SSE 查看数已满。HTTP 所有权冲突不刷新原持有者租约，也不能通过竞争者零键释放清掉原持有者。

## 固定包与独立检查

控制 AGC1 32 B、遥测 AGT1 128 B；所有多字节字段网络大端；version=1，CRC32 为 IEEE 反射 0xedb88320（初值/终值取反），分别覆盖前 28/124 B。固定向量在 `tb/vectors/v3_control_packets.json`：`packets[]` 的 `name/type/session/sequence/words/crc32/hex` 可供 C 与 RTL 逐字节对比，包含 HELLO/KEYS/ACK/有数据遥测/session=0 观察遥测。

```powershell
$env:PYTHONHOME = 'C:/efinity/efinity/python311'
& C:/efinity/efinity/python311/bin/python.exe sw/efinix_gpu/tests/test_control_gateway.py
node sw/efinix_gpu/tests/test_control_dashboard.js
```

Python 检查真实本机 HTTP/UDP、固定向量、CRC/保留位、ACK门控、错误来源、租约、竞争者、限频、最新键、序号回绕、旧固件/旧资源、复位、新session、假板租约及慢 SSE/包压力。Node 使用内置断言检查单在途请求、最新状态覆盖、33 ms 限频、释放停止心跳、别名键与动作边沿、有效性和有界原始 CSV；不依赖浏览器框架。保存证据于 `generated/verification/v3/gateway/`。完整浏览器人工键盘、真实网口与板端渲染联调、长期压力与 30 分钟耐久仍由集成上板阶段验收。

验证环境若已有 Playwright/Edge，可额外运行 `test_control_dashboard_browser.js`（这不是工具运行依赖）；设置 `NODE_PATH` 指向已有 Playwright 所在模块目录。设置 `GATEWAY_TEST_LAUNCHER=1` 同时覆盖 PowerShell 两种启动入口。该检查使用真实浏览器验证页面事件、ACK、独占冲突、模仿标签、无效 FPS、CSV 下载与关闭页面清键，并保存 `dashboard.png`、`browser-raw.csv`。不会安装浏览器或包，结束只清理自己启动的进程。
