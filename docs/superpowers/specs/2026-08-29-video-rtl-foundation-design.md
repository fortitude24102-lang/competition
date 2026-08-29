# 视频 RTL 独立回归基础设计

## 目标

在不修改现有 `VideoAccelTop` 端口、算法或 SoC 连接的前提下，为视频 RTL 组员提供一个可以独立运行的 SystemVerilog 自检入口。该入口用于证明外部 Verilog 本身正确，不依赖 Chisel 测试才能定位问题。

## 范围

- 新增 `tb/tb_video_accel_top.sv`，直接实例化 `rtl/video/VideoAccelTop.v`。
- 新增一个简短脚本，使用现有 WSL Verilator 编译并运行 testbench。
- 检查同步复位、`enable=0`、bypass、gray、threshold 和一拍 `valid` 对齐。
- 将该脚本加入 SoC 验证入口，在调用 Vivado 前先完成纯 RTL 回归。

本轮不拆分或重写 `VideoAccelTop.v`，不新增视频时序、HDMI/VGA、Sobel、line buffer 或跨时钟域逻辑。需要目标分辨率、像素时钟、显示模板和 XDC 后，再开始板级视频链路。

## 接口与行为

接口继续以 `docs/accel_if.md` 为唯一约束。测试固定使用 RGB888，验证：

- 复位时输出、有效、忙和完成信号清零；
- `enable=0` 时有效输入不产生输出事务；
- bypass 输出原像素；
- gray 输出三个相同通道；
- threshold 在阈值两侧分别输出黑和白；
- 每个被接受的输入在下一拍产生且只产生一个有效输出。

任何检查失败都由 testbench 输出明确错误并返回非零状态。

## 验证

独立 RTL 脚本必须从项目根目录运行成功。现有 `VideoAccelExtSpec` 继续作为 Chisel/ExtModule 集成检查；新增 testbench 负责纯 Verilog 行为检查，两者不重复承担 SoC 软件验证。
