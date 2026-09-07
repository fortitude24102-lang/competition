# 组员 B 第 2–4 天离线验收

日期：2026-09-08。范围为软件字段合同、RGB565 数学和 CPU Solid Fill。

## 运行

在仓库根目录执行 `pwsh -NoProfile -File scripts/test-efinix-software.ps1`。
需要 WSL 中的 GCC（本机 Ubuntu GCC 13.3）以及官方 Efinity GCC 13.4：
`D:/efinity/risc_v_gcc/toolchain/bin/riscv-none-elf-gcc.exe`。
工具链路径可用 `-RiscvGcc` 参数覆盖。任一编译或运行失败会抛错并返回非零。
本机 PATH 中 MinGW 缺少 cc1，不能作为可用主机编译器。

## 第 2 天合同

`gpu_regs.h` 的全部 30 个寄存器偏移、布局断言、STATUS 位、字段掩码，
及 `gpu.h` 的 opcode 0–6、error 0–9，按当前 GpuTypes.scala、
GpuMemoryMap.scala、GpuApbRegs.scala 逐项核对。
`gpu_command` 为普通 C 字段合同，不是能直接 memcpy 到 MMIO 的描述符。
打包函数仅处理 SIZE、COLOR_KEY、ALPHA_FLAGS，后者 bits 15:8 恒零。

当前 RTL 的 QoS/Perf 0x48–0x74 读零、写忽略；front/back 固定为 A/B；
CONTROL 只有 bit0 提交；flags 执行语义未实现，调用者使用零。
LAST_DONE 仅最近 tag，非历史完成队列。没有提供 MMIO 硬件驱动或后期 API。

`sapphire_probe.c` 直接包含只读官方
`board/efinix_ti60/vendor/sapphire_ddr3/par/ddr_demo_ti60/embedded_sw/include/soc.h`，
编译期核对 APB base/size、100 MHz、IRQ 16 和 32 位指针。
src 两文件及该探针均以 `-march=rv32im_zicsr -mabi=ilp32 -ffreestanding`
和 `-Wall -Wextra -Werror` 编译为 RV32 对象。没有改动官方 BSP。

## 第 3 天颜色

遵守冻结合同 docs/gpu_interface.md：在原生 5/6/5 通道使用
`(fg*a + bg*(255-a) +127)/255`。565 到 888 采用位复制，888 到 565
截去低位；返回 RGB888 的低 24 位为 0xRRGGBB。已校验 65536 种颜色往返，
全部 32×32×256 与 64×64×256 Alpha 通道组合。
独立 oracle 逐个寻找最近的合法量化候选，而非复用生产除法。
另含不对称红/蓝半透明以及不对称整像素 alpha 0/255 固定向量。

## 第 4 天填充和 CRC

Solid Fill 接受显式缓冲区长度、像素尺寸和字节 stride；不裁剪，非法请求无写入。
验证 2 字节对齐、非零尺寸、stride 下限、64 位末地址计算和矩形范围。
使用逐字节小端写入，奇数宽度不改动邻像素或 padding。
缓冲区最小 span 为 `(height-1)*stride + width*2`，无需最后一行尾部 padding。

主机测试启用 AddressSanitizer 和 UndefinedBehaviorSanitizer，覆盖带前后哨兵的
3 像素宽、跨两行、14 字节 stride 填充，以及零尺寸、越界、短 stride、
短缓冲、未对齐地址/stride、巨大 stride 和右下单像素。
生成 640×480 全绿、右下角红色参考帧：
`generated/verification/efinix-software/reference.rgb565`，614400 字节。

CRC 标准为 CRC-32/ISO-HDLC（反射多项式 0xEDB88320，初值及 xorout 均
0xFFFFFFFF）。函数覆盖传入 span 的每一个字节；包含 span 内 padding，
因此验收前必须初始化 padding。当前参考帧紧密排列，无 padding。
已知向量 `123456789` = 0xCBF43926，空串 = 0；参考帧 = **0x77DEF323**，
另以 Python 标准库 zlib 独立复核一致。

## 执行证据与限制

- 初始测试文件先写，官方 RV32 编译退出 1：`fatal error: gpu.h: No such file or directory`。
  这是缺少合同的编译红灯，不宣称为运行断言红灯。
- 编写实现后主机及官方交叉编译通过。额外将颜色实现复制到忽略产物目录、
  把舍入 `+127` 改为 `+0` 后，运行在不对称 Alpha 向量断言失败，退出 134；
  正式源文件始终未改。此变异检查证明断言可检出舍入错误。
- 最新完整脚本退出 0，输出 `reference RGB565: 614400 bytes, CRC32=77def323`
  和两行 PASS；编译无警告，ASan/UBSan 无错误。WSL 启动有本机 localhost
  代理配置提示，与本次离线编译无关。
- 所有产物位于忽略目录 generated/verification/efinix-software。
- 这不是板卡执行、UART、实际 DDR、MMIO、IRQ 或 GPU 渲染验收；
  第 5 天硬件驱动和实板比较仍待有板卡后开展。
