# 独立只读审查与修复

范围55adb2f..f468337，独立reviewer返回Critical0、Important3、Minor0，初始结论request changes。执行者一轮修复到3d3daa0，无第二次独立审查：

1. 旧成绩随新控制会话重新发布：Sapphire性能阶段绑定原控制session，失去租约/换session只该阶段回菜单；显式新挑战才重建私有状态。真实NC过期→runtime→新HELLO测试RED缺API→GREEN；实板释放/新会话/R通过。
2. 重开/换档/能力消失及乱序保留旧best：跨两种数据包使用全局快照顺序，匹配当前target；R立即屏蔽旧结果，等待新的重开快照，清除旧成绩。实际old VERIFIED855仍fresh的失败→27项协议回归GREEN，浏览器GREEN。
3. 普通关闭特性固件收到合法opcode3退出渲染：改为非致命拒绝ACK。真实32B RX→v3_apply的负返回失败→GREEN，后续普通START64继续运行；原CPU绘图未改。

reviewer核查提供的R5实板855证据和时序/CDC，但没有亲自检查物理HDMI、实体断网/重连或超出捕获窗口耐久。执行者保留这些未验边界，不将材料核查称为物理验收；若实际出现画面/重连/耐久问题，当前数据不覆盖它们。最终R6由执行者再次实板：872/3600帧/60.10FPS/零超预算迟到新增下溢错误＋5秒保持。
