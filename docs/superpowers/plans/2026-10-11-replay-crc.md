# Replay CRC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保持完整回放校验语义，用64B半字节CRC减少封存/开始校验成本。

**Architecture:** 替换现有crc_word内部算法；逐位编译回退和独立输出候选。用一个RV32探针BIN隔离算法成本，游戏成绩另测。

**Tech Stack:** C11、既有WSL GCC/UBSan、官方RV32工具链、既有JTAG采集。

**Spec:** docs/superpowers/specs/2026-10-11-replay-crc-design.md

## Global Constraints

- REPLAY_CRC_NIBBLE默认0；记录格式、参数/篡改检查和CPU绘图算法/配置不变。
- GPU/SoC100MHz、960×540 RGB565不变；不写Flash、不覆盖release。
- text+data+bss+4096不超过126976B；容量通过不等于运行栈水位保证。
- 用户2026-10-11明确免除中间审批；当前对话直接执行，不另发审批问题。

## Review Focus

- 负速度符号扩展和CRC字节次序：独立规范序列对照。
- 任意CRC初值和所有高/低半字节：固定值和随机word等价。
- 修改initial/keys/epoch仍被拒绝：600tick实际回放回归。
- 独立候选构建不污染正式release：非法构建组合必须在工具启动前失败。
- 探针/游戏不同BIN及串口身份：测量记录SHA、序列和错误，不混用历史结果。

### Task 1: 算法和候选构建

**Files:** src/replay_input.c、tests/test_replay_crc.c（均在sw/efinix_gpu下）；scripts/test-v3-integration.ps1、scripts/test-efinix-software.ps1。

**Interfaces:** 公开replay_*函数及结构保持；REPLAY_CRC_NIBBLE=0/1；构建-ReplayCrcNibble只接受独立Interactive输出。

- [x] 写test_replay_crc：包含真实replay_input.c，独立逐位参考word更新；完全一致。显式REPLAY_CRC_COST_CHECK基准检查小表字循环成本小于参考的一半，不把主机调度时间作为普通回归门槛。
- [x] WSL gcc -O2 -Wall -Wextra -Werror运行该测试，先观察未优化成本断言失败。
- [x] 最小实现64B表和编译选择；完善规范字段/篡改等价。观察GREEN。
- [x] 默认路径与候选分别运行既有test-v3-integration.ps1 -SoftwareOnly，记录全部结果。
- [x] 构建独立正常候选，检查ELF内存和候选选项防误覆盖，记录结果并提交相关文件。

### Task 2: 软核实测和收尾

**Files:** sw/efinix_gpu/tests/test_board_replay_crc.c；最小独立构建脚本；docs/efinix_2d_gpu/replay_crc_20261011.md及证据。

**Interfaces:** 同BIN参考逐位word与实际小表word、相同初始状态/按键；UART报告CRC与CLINT耗时；探针通过后恢复正常菜单候选。

- [x] 创建独立RV32算法探针；先在主机运行相同输入等价检查。
- [x] 用现有官方BSP构建、查内存；探针不修改RTL。
- [x] 检查串口/服务所有者；确认无并行烧录再仅JTAG测量。板卡不可用则记录，不冒称完成。
- [x] 正常候选运行跨600tick；若无法安全测量则保留离线结果，清楚标出缺项。
- [x] 最终独立审查、保存记录、提交本地分支。没有用户推送请求不更新远端main。
