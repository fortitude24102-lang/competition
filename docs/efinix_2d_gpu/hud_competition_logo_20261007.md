# 性能栏右侧竞赛图片

用户提供原图5087×1772，等比例导入200×70 RGB565白底图片；画面960×540，坐标(752,1)，完全落在原72像素HUD内。图片不重新绘制/生成，不改游戏背景、Sprite、CPU场景渲染器、GPU RTL、时钟或原R7素材。素材来源SHA256为28143ccb9222bf9b22c1ef09a7ec6165c4bb27e95c7b8cd9b62293b9d3babcc8。

## 如何显示

- PC仍只提供存储：ASST资源103为competition_logo.rgb565，28000字节，修正版整文件CRC32为b4cc6853；Sapphire启动时复用现有network_asset_fetch加载到DDR 0x02c50000，完整CRC通过才启用。
- 网口资源服务使用sw/efinix_gpu/assets/interactive/manifest.csv，现在包含101背景、102图集、103图片。背景/图集字节与R7完全相同；资源epoch更新为0x00030002。旧服务器没有103、断网或CRC失败只禁用图片，不禁用游戏，也不显示不完整数据。
- 原图、转换结果、CRC头和来源记录在sw/efinix_gpu/assets/hud。运行tools/build_hud_logo.ps1导入，随后运行tools/build_interactive_assets.py生成资源包。不把28000字节图片嵌入固件、BSS或纹理Cache。
- GPU仅在缓存首次构建、图片显隐变化或缓存失效时通过已有Copy更新图片；普通数字变化沿用原字符格更新。CPU只在原来的HUD全软件重建中加入同一张图片，没有优化CPU场景算法。
- 每帧仍只有原960×72的HUD拷贝，不增加独立图片绘图命令。长文字超过图片区左界时先清除图片区，完整显示文字；变短后恢复图片。CPU/GPU切换、双缓冲及部分DMA失败恢复都有对应测试。

## 版权和验证口径

用户提供的竞赛标识保留原权利人权利，不属于项目原创背景/图集的CC0许可；不要把图片再授权成CC0。

本轮RED确认旧HUD右上仍是黑像素，旧资源包只有101/102；GREEN验证新缓存像素、显隐优先级、缓存命中零新增命令、一个数字改变仍504字节/一条Copy、CPU软件重建、A/B显示和失败恢复。8个C/18000帧ROI回归以及生产驱动ASan/UBSan、完整固件链接通过。固件text37712、BSS78956，共116668字节，加4KiB预留栈仍在官方124KiB软件区内；不是动态栈高水位证明。没有重跑未改RTL仿真或综合，也不据此宣称512@60或30分钟耐久通过。

## 蓝底问题的根因与修正

首次上板资源103完整加载、CRC通过，但用户照片显示蓝底和低对比度。逐字检查实际RGB565文件，原本白色的像素是0x00FF而不是0xFFFF：PowerShell的System.Drawing.Color通道是Byte，直接左移会丢弃高位。转换器现先把R/G/B提升为int再打包；不改HDMI、GPU、图片大小或游戏逻辑。PNG预览原先就正确，CRC只能证明传输一致，不能证明编码颜色正确，因此不能用这两项代替像素语义检查。

tools/test_build_hud_logo.ps1用原生转换器生成四条色带，直接读取输出文件，每行比较字面期望白FFFF、红F800、绿07E0、蓝001F，共70行；旧编码RED，修正版GREEN。资源包检查1项、真实UDP服务器检查2项也通过，生成头文件CRC与实际资源一致。此测试不依赖额外图片库。

重新生成的步骤：先执行`powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_hud_logo.ps1`，再执行`python tools/build_interactive_assets.py`；最后重建交互固件。可运行`powershell -NoProfile -ExecutionPolicy Bypass -File tools/test_build_hud_logo.ps1`检查实际编码。**资源服务器在启动时缓存文件**，素材更新后必须重启对应服务，不能只替换磁盘文件；新固件内的CRC也必须与新素材同步。

## 实板结果与边界

初次固件加载发生CPU halt超时，尚未执行load_image；失败日志保留。确认没有并行烧录进程后，仅通过JTAG重载已合格display_reset_20261006_r1位流，随后固件加载恢复。没有写Flash，也不能由恢复成功断言最初halt失败的唯一物理原因。

修正版使用同一已合格位流，仅JTAG热重载固件，并刷新资源服务器的内存缓存。背景101、图集102、图片103都零重试、result=0，图片committed_bytes=28000、enabled=1；V3_READY为build20261007/epoch00030002。启动首窗59.2FPS，随后64请求档稳态短窗60.1FPS、under=0、miss=0。真实HTTP→UDP→FPGA→Sapphire的RIGHT/UP/租约释放分阶段检查通过。没有重新跑CPU600tick慢回放、512档或30分钟耐久。

修正版BIN SHA256：ec966d397e4d085e7fb40eac59a17eb865cd948396bbe1647256343830c0613c；text37712/data0/BSS78956。用户原照片已确认位置，但修正版白底及实际可读性仍待用户目视确认，不能用FPS或完整CRC替代该确认；200×70缩图本身不能保证原图的小英文全部可读。

本地构建和完整原始日志：generated/verification/v3/hud-logo-20261007。提交的[证据包](evidence/hud_logo_20261007.zip)包含旧失败、新编码检查、构建、修正版UART/控制证据和对应固件；不删旧失败，不据此宣称V3封版。GPU/CPU主渲染器、正式RTL、时钟、release/v2均未改。

证据包共26个文件，打包后逐项SHA256核对通过；ZIP SHA256为e9245ea04bfbfb3731662f681dd6ea099c00e4c8c79c635ad156a63d43254b72。修正版UART保留了启动前旧固件尾部，验收仅取本次HUD_LOGO/V3_READY之后的样本，不能把前面的旧样本算作新结果。
