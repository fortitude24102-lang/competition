///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:  
  /////////////////
  Axi 8Slave - 1Master Multiplex
  支持2-8端口的AXI_Master 访问 AXI_Slave 的多路复用
  通过宏定义 Axi_Slave 端口个数 
  通过 Cfg_Arb_Type 支持共享访问（0）和优先级访问（1）
  通过 Cfg_Cnl_Mask 支持端口屏蔽，可用于测试和调试

  /////////////////
  相关文件:
  Axi_Mux_Param.vh    -- 放置在工程根目录或修改 include 的路径

  Establishment : Richard Zhu
  Create date   : 2022-09-29
  Versions      : V0.1
  Revision of records:
  Ver0.1

  V1.0

  /////////////////
  --2022-10-12  Axi_Mux_Addr_Ctrl 仿真验证
    修改了通道切换状态机（ Sta_Cnl_Switch ）, 提高了切换效率
  --2022-10-12  Axi_Mux      
    把通道修改改为预定义 ， 删除了原来的 Axi_Mux_2/Axi_Mux_4/Axi_Mux_8 

  V1.1 2022-10-12 
  /////////////////
  /////////////////
  --2022-10-12 Axi_Mux_Rd_Ctrl 仿真验证
    修改了 Info_Fifo 的深度， 使AR总线和R总线尽可能解耦

  V1.2 2022-10-13
  /////////////////

**********************************************************/
///////////////////////////////////////////////////////////

`timescale 1ns/100ps

`define     X2 

`include  "Axi_Mux_Param.vh"


///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:
  Axi 8Slave - 1Master Multiplex
  通过宏定义 Axi_Slave 端口个数

  Establishment : Richard Zhu
  Create date   : 2022-09-29
  Versions      : V0.1
  Revision of records:
  Ver0.1
  
**********************************************************/

module  Axi_Mux
(
  //System Signal
  Sys_Clk         , //System Clock
  Sys_Rst_N       , //System Reset
  //Axi Master Signal
  O_M_AW_ID       , //(O)[WrAddr]Write address ID.
  O_M_AW_ADDR     , //(O)[WrAddr]Write address.
  O_M_AW_LEN      , //(O)[WrAddr]Burst length.
  O_M_AW_SIZE     , //(O)[WrAddr]Burst size.
  O_M_AW_BURST    , //(O)[WrAddr]Burst type.
  O_M_AW_LOCK     , //(O)[WrAddr]Lock type.
  O_M_AW_VALID    , //(O)[WrAddr]Write address valid.
  I_M_AW_READY    , //(I)[WrAddr]Write address ready.
  O_M_W_ID        , //(O)[WrData][WrData]Write ID tag.
  O_M_W_DATA      , //(O)[WrData][WrData]Write data.
  O_M_W_LAST      , //(O)[WrData][WrData]Write last.
  O_M_W_STRB      , //(O)[WrData][WrData]Write strobes.
  O_M_W_VALID     , //(O)[WrData][WrData]Write valid.
  I_M_W_READY     , //(I)[WrData][WrData]Write ready.
  I_M_B_ID        , //(I)[WrResp]Response ID tag.
  I_M_B_VALID     , //(I)[WrResp]Write response valid.
  O_M_B_READY     , //(O)[WrResp]Response ready.
  O_M_AR_ID       , //(O)[RdAddr]Read address ID.
  O_M_AR_ADDR     , //(O)[RdAddr]Read address.
  O_M_AR_LEN      , //(O)[RdAddr]Burst length.
  O_M_AR_SIZE     , //(O)[RdAddr]Burst size.
  O_M_AR_BURST    , //(O)[RdAddr]Burst type.
  O_M_AR_LOCK     , //(O)[RdAddr]Lock type.
  O_M_AR_VALID    , //(O)[RdAddr]Read address valid.
  I_M_AR_READY    , //(I)[RdAddr]Read address ready.
  I_M_R_ID        , //(I)[RdData]Read ID tag.
  I_M_R_DATA      , //(I)[RdData]Read data.
  I_M_R_LAST      , //(I)[RdData]Read last.
  I_M_R_RESP      , //(I)[RdData]Read response.
  I_M_R_VALID     , //(I)[RdData]Read valid.
  O_M_R_READY     , //(O)[RdData]Read ready.
  //Axi Slave 0 Signal
  I_S0_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S0_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S0_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S0_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S0_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S0_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S0_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S0_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S0_W_ID       , //(I)[WrData]Write ID tag.
  I_S0_W_DATA     , //(I)[WrData]Write data.
  I_S0_W_LAST     , //(I)[WrData]Write last.
  I_S0_W_STRB     , //(I)[WrData]Write strobes.
  I_S0_W_VALID    , //(I)[WrData]Write valid.
  O_S0_W_READY    , //(O)[WrData]Write ready.
  O_S0_B_ID       , //(O)[WrResp]Response ID tag.
  O_S0_B_VALID    , //(O)[WrResp]Write response valid.
  I_S0_B_READY    , //(I)[WrResp]Response ready.
  I_S0_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S0_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S0_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S0_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S0_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S0_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S0_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S0_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S0_R_ID       , //(O)[RdData]Read ID tag.
  O_S0_R_DATA     , //(O)[RdData]Read data.
  O_S0_R_LAST     , //(O)[RdData]Read last.
  O_S0_R_RESP     , //(O)[RdData]Read response.
  O_S0_R_VALID    , //(O)[RdData]Read valid.
  I_S0_R_READY    , //(I)[RdData]Read ready.
  //Axi Slave 1 Signal
  I_S1_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S1_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S1_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S1_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S1_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S1_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S1_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S1_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S1_W_ID       , //(I)[WrData]Write ID tag.
  I_S1_W_DATA     , //(I)[WrData]Write data.
  I_S1_W_STRB     , //(I)[WrData]Write strobes.
  I_S1_W_LAST     , //(I)[WrData]Write last.
  I_S1_W_VALID    , //(I)[WrData]Write valid.
  O_S1_W_READY    , //(O)[WrData]Write ready.
  O_S1_B_ID       , //(O)[WrResp]Response ID tag.
  O_S1_B_VALID    , //(O)[WrResp]Write response valid.
  I_S1_B_READY    , //(I)[WrResp]Response ready.
  I_S1_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S1_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S1_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S1_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S1_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S1_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S1_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S1_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S1_R_ID       , //(O)[RdData]Read ID tag.
  O_S1_R_DATA     , //(O)[RdData]Read data.
  O_S1_R_LAST     , //(O)[RdData]Read last.
  O_S1_R_RESP     , //(O)[RdData]Read response.
  O_S1_R_VALID    , //(O)[RdData]Read valid.
  I_S1_R_READY    , //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`ifdef      X3 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 2 Signal
  I_S2_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S2_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S2_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S2_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S2_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S2_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S2_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S2_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S2_W_ID       , //(I)[WrData]Write ID tag.
  I_S2_W_DATA     , //(I)[WrData]Write data.
  I_S2_W_LAST     , //(I)[WrData]Write last.
  I_S2_W_STRB     , //(I)[WrData]Write strobes.
  I_S2_W_VALID    , //(I)[WrData]Write valid.
  O_S2_W_READY    , //(O)[WrData]Write ready.
  O_S2_B_ID       , //(O)[WrResp]Response ID tag.
  O_S2_B_VALID    , //(O)[WrResp]Write response valid.
  I_S2_B_READY    , //(I)[WrResp]Response ready.
  I_S2_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S2_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S2_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S2_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S2_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S2_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S2_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S2_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S2_R_ID       , //(O)[RdData]Read ID tag.
  O_S2_R_DATA     , //(O)[RdData]Read data.
  O_S2_R_LAST     , //(O)[RdData]Read last.
  O_S2_R_RESP     , //(O)[RdData]Read response.
  O_S2_R_VALID    , //(O)[RdData]Read valid.
  I_S2_R_READY    , //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X3
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X4 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 3 Signal
  I_S3_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S3_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S3_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S3_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S3_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S3_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S3_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S3_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S3_W_ID       , //(I)[WrData]Write ID tag.
  I_S3_W_DATA     , //(I)[WrData]Write data.
  I_S3_W_STRB     , //(I)[WrData]Write strobes.
  I_S3_W_LAST     , //(I)[WrData]Write last.
  I_S3_W_VALID    , //(I)[WrData]Write valid.
  O_S3_W_READY    , //(O)[WrData]Write ready.
  O_S3_B_ID       , //(O)[WrResp]Response ID tag.
  O_S3_B_VALID    , //(O)[WrResp]Write response valid.
  I_S3_B_READY    , //(I)[WrResp]Response ready.
  I_S3_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S3_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S3_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S3_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S3_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S3_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S3_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S3_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S3_R_ID       , //(O)[RdData]Read ID tag.
  O_S3_R_DATA     , //(O)[RdData]Read data.
  O_S3_R_LAST     , //(O)[RdData]Read last.
  O_S3_R_RESP     , //(O)[RdData]Read response.
  O_S3_R_VALID    , //(O)[RdData]Read valid.
  I_S3_R_READY    , //(I)[RdData]Read ready.  
//&&&&&&&&&&&&&&&&&&
`endif    //X4
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X5 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 4 Signal
  I_S4_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S4_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S4_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S4_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S4_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S4_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S4_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S4_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S4_W_ID       , //(I)[WrData]Write ID tag.
  I_S4_W_DATA     , //(I)[WrData]Write data.
  I_S4_W_LAST     , //(I)[WrData]Write last.
  I_S4_W_STRB     , //(I)[WrData]Write strobes.
  I_S4_W_VALID    , //(I)[WrData]Write valid.
  O_S4_W_READY    , //(O)[WrData]Write ready.
  O_S4_B_ID       , //(O)[WrResp]Response ID tag.
  O_S4_B_VALID    , //(O)[WrResp]Write response valid.
  I_S4_B_READY    , //(I)[WrResp]Response ready.
  I_S4_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S4_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S4_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S4_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S4_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S4_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S4_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S4_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S4_R_ID       , //(O)[RdData]Read ID tag.
  O_S4_R_DATA     , //(O)[RdData]Read data.
  O_S4_R_LAST     , //(O)[RdData]Read last.
  O_S4_R_RESP     , //(O)[RdData]Read response.
  O_S4_R_VALID    , //(O)[RdData]Read valid.
  I_S4_R_READY    , //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X5
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X6 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 5 Signal
  I_S5_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S5_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S5_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S5_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S5_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S5_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S5_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S5_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S5_W_ID       , //(I)[WrData]Write ID tag.
  I_S5_W_DATA     , //(I)[WrData]Write data.
  I_S5_W_STRB     , //(I)[WrData]Write strobes.
  I_S5_W_LAST     , //(I)[WrData]Write last.
  I_S5_W_VALID    , //(I)[WrData]Write valid.
  O_S5_W_READY    , //(O)[WrData]Write ready.
  O_S5_B_ID       , //(O)[WrResp]Response ID tag.
  O_S5_B_VALID    , //(O)[WrResp]Write response valid.
  I_S5_B_READY    , //(I)[WrResp]Response ready.
  I_S5_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S5_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S5_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S5_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S5_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S5_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S5_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S5_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S5_R_ID       , //(O)[RdData]Read ID tag.
  O_S5_R_DATA     , //(O)[RdData]Read data.
  O_S5_R_LAST     , //(O)[RdData]Read last.
  O_S5_R_RESP     , //(O)[RdData]Read response.
  O_S5_R_VALID    , //(O)[RdData]Read valid.
  I_S5_R_READY    , //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X6
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X7
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 6 Signal
  I_S6_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S6_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S6_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S6_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S6_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S6_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S6_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S6_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S6_W_ID       , //(I)[WrData]Write ID tag.
  I_S6_W_DATA     , //(I)[WrData]Write data.
  I_S6_W_LAST     , //(I)[WrData]Write last.
  I_S6_W_STRB     , //(I)[WrData]Write strobes.
  I_S6_W_VALID    , //(I)[WrData]Write valid.
  O_S6_W_READY    , //(O)[WrData]Write ready.
  O_S6_B_ID       , //(O)[WrResp]Response ID tag.
  O_S6_B_VALID    , //(O)[WrResp]Write response valid.
  I_S6_B_READY    , //(I)[WrResp]Response ready.
  I_S6_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S6_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S6_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S6_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S6_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S6_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S6_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S6_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S6_R_ID       , //(O)[RdData]Read ID tag.
  O_S6_R_DATA     , //(O)[RdData]Read data.
  O_S6_R_LAST     , //(O)[RdData]Read last.
  O_S6_R_RESP     , //(O)[RdData]Read response.
  O_S6_R_VALID    , //(O)[RdData]Read valid.
  I_S6_R_READY    , //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X7
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X8
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 7 Signal
  I_S7_AW_ID      , //(I)[WrAddr]Write address ID.
  I_S7_AW_ADDR    , //(I)[WrAddr]Write address.
  I_S7_AW_LEN     , //(I)[WrAddr]Burst length.
  I_S7_AW_SIZE    , //(I)[WrAddr]Burst size.
  I_S7_AW_BURST   , //(I)[WrAddr]Burst type.
  I_S7_AW_LOCK    , //(I)[WrAddr]Lock type.
  I_S7_AW_VALID   , //(I)[WrAddr]Write address valid.
  O_S7_AW_READY   , //(O)[WrAddr]Write address ready.
  I_S7_W_ID       , //(I)[WrData]Write ID tag.
  I_S7_W_DATA     , //(I)[WrData]Write data.
  I_S7_W_STRB     , //(I)[WrData]Write strobes.
  I_S7_W_LAST     , //(I)[WrData]Write last.
  I_S7_W_VALID    , //(I)[WrData]Write valid.
  O_S7_W_READY    , //(O)[WrData]Write ready.
  O_S7_B_ID       , //(O)[WrResp]Response ID tag.
  O_S7_B_VALID    , //(O)[WrResp]Write response valid.
  I_S7_B_READY    , //(I)[WrResp]Response ready.
  I_S7_AR_ID      , //(I)[RdAddr]Read address ID.
  I_S7_AR_ADDR    , //(I)[RdAddr]Read address.
  I_S7_AR_LEN     , //(I)[RdAddr]Burst length.
  I_S7_AR_SIZE    , //(I)[RdAddr]Burst size.
  I_S7_AR_BURST   , //(I)[RdAddr]Burst type.
  I_S7_AR_LOCK    , //(I)[RdAddr]Lock type.
  I_S7_AR_VALID   , //(I)[RdAddr]Read address valid.
  O_S7_AR_READY   , //(O)[RdAddr]Read address ready.
  O_S7_R_ID       , //(O)[RdData]Read ID tag.
  O_S7_R_DATA     , //(O)[RdData]Read data.
  O_S7_R_LAST     , //(O)[RdData]Read last.
  O_S7_R_RESP     , //(O)[RdData]Read response.
  O_S7_R_VALID    , //(O)[RdData]Read valid.
  I_S7_R_READY    , //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X8
//&&&&&&&&&&&&&&&&&&
  //Config & State
  Cfg_Arb_Type    , //(I)Config Arbitrtion Type
  Cfg_Cnl_Mask    , //(I)Config Channle Mask
  O_AW_Cnl_Num    , //(O)AW Bus State Bus Active Channel
  O_W_Cnl_Num     , //(O)W  Bus State Bus Active Channel
  O_B_Cnl_Num     , //(O)B  Bus State Bus Active Channel
  O_AR_Cnl_Num    , //(O)AR Bus State Bus Active Channel
  O_R_Cnl_Num       //(O)R  Bus State Bus Active Channel
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  //////////////
  //AXI通道个数设置
  localparam    AXI_CHANNEL_NUM     = `Axi_Chnanel_Num ; //Slave的通道个数

  localparam    CHANNEL_CNT_WIDTH   = $clog2( AXI_CHANNEL_NUM ) ; //通道计数的宽度

  //////////////
  //ID 宽度设置
  parameter     SLAVE_ID_WIDTH  =   8 ; //Slave的ID宽度，一般为8
  parameter     ID_MODE_SEL = "Normal"; //"Normal" "Extend"
                //"Normal"  : Slave的ID和Master的ID宽度一致，通道切换处理按顺序执行
                //"Extend"  : Master的ID为Slave ID加通道号，通道切换按Master提供的通道号
                //"Extend" 资源会节省，但是需要连接的AXI支持宽度可调的ID

  localparam    MASTER_ID_WIDTH     = (ID_MODE_SEL    == "Normal" ) //Master的ID宽度
                                    ?  SLAVE_ID_WIDTH
                                    : (SLAVE_ID_WIDTH + CHANNEL_CNT_WIDTH ) ;

  //////////////
  //数据宽度设置
  parameter     AXI_DATA_WIDTH  = 128 ; //AXI数据宽度

  localparam    AXI_BYTE_NUMBER = AXI_DATA_WIDTH / 8      ; //AXI字节个数
  localparam    AXI_DATA_SIZE   = $clog2(AXI_BYTE_NUMBER) ; //AXI字节计数的宽度

  //abbreviation
  //////////////
  localparam    SIW   = SLAVE_ID_WIDTH    ;
  localparam    MIW   = MASTER_ID_WIDTH   ;
  localparam    ADW   = AXI_DATA_WIDTH    ;
  localparam    ABN   = AXI_BYTE_NUMBER   ;
  localparam    ACN   = AXI_CHANNEL_NUM   ;
  localparam    CCW   = CHANNEL_CNT_WIDTH ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  input               Sys_Clk         ;   //System Clock
  input               Sys_Rst_N       ;   //System Reset
  //Axi Master Signal
  output  [MIW-1:0]   O_M_AW_ID       ; //(O)[WrAddr]Write address ID. This signal is the identification tag for the write address group of signals.
  output  [   31:0]   O_M_AW_ADDR     ; //(O)[WrAddr]Write address. The write address gives the address of the first transfer in a write burst transaction.
  output  [    7:0]   O_M_AW_LEN      ; //(O)[WrAddr]Burst length. The burst length gives the exact number of transfers in a burst. This information determines the number of data transfers associated with the address.
  output  [    2:0]   O_M_AW_SIZE     ; //(O)[WrAddr]Burst size. This signal indicates the size of each transfer in the burst.
  output  [    1:0]   O_M_AW_BURST    ; //(O)[WrAddr]Burst type. The burst type and the size information, determine how the address for each transfer within the burst is calculated.
  output  [    1:0]   O_M_AW_LOCK     ; //(O)[WrAddr]Lock type. Provides additional information about the atomic characteristics of the transfer.
  output              O_M_AW_VALID    ; //(O)[WrAddr]Write address valid. This signal indicates that the channel is signaling valid write address and control information.
  input               I_M_AW_READY    ; //(I)[WrAddr]Write address ready. This signal indicates that the slave is ready to accept an address and associated control signals.
  /////////////
  output  [MIW-1:0]   O_M_W_ID        ; //(O)[WrData]Write ID tag. This signal is the ID tag of the write data transfer.
  output  [ADW-1:0]   O_M_W_DATA      ; //(O)[WrData]Write data.
  output              O_M_W_LAST      ; //(O)[WrData]Write last. This signal indicates the last transfer in a write burst.
  output  [ABN-1:0]   O_M_W_STRB      ; //(O)[WrData]Write strobes. This signal indicates which byte lanes hold valid data. There is one write strobe bit for each eight bits of the write data bus.
  output              O_M_W_VALID     ; //(O)[WrData]Write valid. This signal indicates that valid write data and strobes are available.
  input               I_M_W_READY     ; //(I)[WrData]Write ready. This signal indicates that the slave can accept the write data.
  /////////////
  input   [MIW-1:0]   I_M_B_ID        ; //(I)[WrResp]Response ID tag. This signal is the ID tag of the write response.
  input               I_M_B_VALID     ; //(I)[WrResp]Write response valid. This signal indicates that the channel is signaling a valid write response.
  output              O_M_B_READY     ; //(O)[WrResp]Response ready. This signal indicates that the master can accept a write response.
  /////////////
  output  [MIW-1:0]   O_M_AR_ID       ; //(O)[RdAddr]Read address ID. This signal is the identification tag for the read address group of signals.
  output  [   31:0]   O_M_AR_ADDR     ; //(O)[RdAddr]Read address. The read address gives the address of the first transfer in a read burst transaction.
  output  [    7:0]   O_M_AR_LEN      ; //(O)[RdAddr]Burst length. This signal indicates the exact number of transfers in a burst.
  output  [    2:0]   O_M_AR_SIZE     ; //(O)[RdAddr]Burst size. This signal indicates the size of each transfer in the burst.
  output  [    1:0]   O_M_AR_BURST    ; //(O)[RdAddr]Burst type. The burst type and the size information determine how the address for each transfer within the burst is calculated.
  output  [    1:0]   O_M_AR_LOCK     ; //(O)[RdAddr]Lock type. This signal provides additional information about the atomic characteristics of the transfer.
  output              O_M_AR_VALID    ; //(O)[RdAddr]Read address valid. This signal indicates that the channel is signaling valid read address and control information.
  input               I_M_AR_READY    ; //(I)[RdAddr]Read address ready. This signal indicates that the slave is ready to accept an address and associated control signals.
  /////////////
  input   [MIW-1:0]   I_M_R_ID        ; //(I)[RdData]Read ID tag. This signal is the identification tag for the read data group of signals generated by the slave.
  input   [ADW-1:0]   I_M_R_DATA      ; //(I)[RdData]Read data.
  input               I_M_R_LAST      ; //(I)[RdData]Read last. This signal indicates the last transfer in a read burst.
  input   [    1:0]   I_M_R_RESP      ; //(I)[RdData]Read response. This signal indicates the status of the read transfer.
  input               I_M_R_VALID     ; //(I)[RdData]Read valid. This signal indicates that the channel is signaling the required read data.
  output              O_M_R_READY     ; //(O)[RdData]Read ready. This signal indicates that the master can accept the read data and response information.

  //Axi Slave 0 Signal
  input   [SIW-1:0]   I_S0_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S0_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S0_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S0_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S0_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S0_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S0_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S0_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S0_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S0_W_DATA     ; //(I)[WrData]Write data.
  input               I_S0_W_LAST     ; //(I)[WrData]Write last.
  input   [ABN-1:0]   I_S0_W_STRB     ; //(I)[WrData]Write strobes.
  input               I_S0_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S0_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S0_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S0_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S0_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S0_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S0_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S0_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S0_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S0_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S0_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S0_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S0_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S0_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S0_R_DATA     ; //(O)[RdData]Read data.
  output              O_S0_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S0_R_RESP     ; //(O)[RdData]Read response.
  output              O_S0_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S0_R_READY    ; //(I)[RdData]Read ready.
  //Axi Slave 1 Signal
  input   [SIW-1:0]   I_S1_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S1_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S1_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S1_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S1_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S1_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S1_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S1_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S1_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S1_W_DATA     ; //(I)[WrData]Write data.
  input               I_S1_W_LAST     ; //(I)[WrData]Write last.
  input   [ABN-1:0]   I_S1_W_STRB     ; //(I)[WrData]Write strobes.
  input               I_S1_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S1_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S1_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S1_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S1_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S1_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S1_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S1_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S1_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S1_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S1_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S1_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S1_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S1_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S1_R_DATA     ; //(O)[RdData]Read data.
  output              O_S1_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S1_R_RESP     ; //(O)[RdData]Read response.
  output              O_S1_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S1_R_READY    ; //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`ifdef      X3
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 3 Signal
  input   [SIW-1:0]   I_S2_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S2_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S2_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S2_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S2_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S2_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S2_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S2_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S2_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S2_W_DATA     ; //(I)[WrData]Write data.
  input               I_S2_W_LAST     ; //(I)[WrData]Write last.
  input   [ABN-1:0]   I_S2_W_STRB     ; //(I)[WrData]Write strobes.
  input               I_S2_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S2_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S2_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S2_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S2_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S2_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S2_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S2_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S2_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S2_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S2_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S2_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S2_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S2_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S2_R_DATA     ; //(O)[RdData]Read data.
  output              O_S2_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S2_R_RESP     ; //(O)[RdData]Read response.
  output              O_S2_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S2_R_READY    ; //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X3
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X4 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 4 Signal
  input   [SIW-1:0]   I_S3_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S3_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S3_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S3_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S3_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S3_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S3_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S3_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S3_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S3_W_DATA     ; //(I)[WrData]Write data.
  input               I_S3_W_LAST     ; //(I)[WrData]Write last.
  input   [ABN-1:0]   I_S3_W_STRB     ; //(I)[WrData]Write strobes.
  input               I_S3_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S3_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S3_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S3_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S3_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S3_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S3_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S3_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S3_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S3_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S3_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S3_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S3_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S3_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S3_R_DATA     ; //(O)[RdData]Read data.
  output              O_S3_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S3_R_RESP     ; //(O)[RdData]Read response.
  output              O_S3_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S3_R_READY    ; //(I)[RdData]Read ready.  
//&&&&&&&&&&&&&&&&&&
`endif    //X4
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X5 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 4 Signal
  input   [SIW-1:0]   I_S4_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S4_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S4_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S4_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S4_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S4_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S4_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S4_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S4_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S4_W_DATA     ; //(I)[WrData]Write data.
  input               I_S4_W_LAST     ; //(I)[WrData]Write last.
  input   [ABN-1:0]   I_S4_W_STRB     ; //(I)[WrData]Write strobes.
  input               I_S4_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S4_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S4_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S4_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S4_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S4_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S4_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S4_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S4_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S4_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S4_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S4_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S4_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S4_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S4_R_DATA     ; //(O)[RdData]Read data.
  output              O_S4_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S4_R_RESP     ; //(O)[RdData]Read response.
  output              O_S4_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S4_R_READY    ; //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X5
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X6 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 5 Signal
  input   [SIW-1:0]   I_S5_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S5_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S5_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S5_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S5_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S5_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S5_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S5_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S5_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S5_W_DATA     ; //(I)[WrData]Write data.
  input               I_S5_W_STRB     ; //(I)[WrData]Write strobes.
  input   [ABN-1:0]   I_S5_W_LAST     ; //(I)[WrData]Write last.
  input               I_S5_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S5_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S5_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S5_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S5_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S5_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S5_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S5_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S5_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S5_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S5_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S5_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S5_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S5_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S5_R_DATA     ; //(O)[RdData]Read data.
  output              O_S5_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S5_R_RESP     ; //(O)[RdData]Read response.
  output              O_S5_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S5_R_READY    ; //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X6
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X7 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 6 Signal
  input   [SIW-1:0]   I_S6_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S6_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S6_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S6_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S6_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S6_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S6_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S6_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S6_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S6_W_DATA     ; //(I)[WrData]Write data.
  input               I_S6_W_LAST     ; //(I)[WrData]Write last.
  input   [ABN-1:0]   I_S6_W_STRB     ; //(I)[WrData]Write strobes.
  input               I_S6_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S6_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S6_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S6_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S6_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S6_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S6_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S6_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S6_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S6_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S6_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S6_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S6_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S6_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S6_R_DATA     ; //(O)[RdData]Read data.
  output              O_S6_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S6_R_RESP     ; //(O)[RdData]Read response.
  output              O_S6_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S6_R_READY    ; //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X7
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&&&&&&&&&&&
`ifdef      X8 
//&&&&&&&&&&&&&&&&&&
  //Axi Slave 7 Signal
  input   [SIW-1:0]   I_S7_AW_ID      ; //(I)[WrAddr]Write address ID.
  input   [   31:0]   I_S7_AW_ADDR    ; //(I)[WrAddr]Write address.
  input   [    7:0]   I_S7_AW_LEN     ; //(I)[WrAddr]Burst length.
  input   [    2:0]   I_S7_AW_SIZE    ; //(I)[WrAddr]Burst size.
  input   [    1:0]   I_S7_AW_BURST   ; //(I)[WrAddr]Burst type.
  input   [    1:0]   I_S7_AW_LOCK    ; //(I)[WrAddr]Lock type.
  input               I_S7_AW_VALID   ; //(I)[WrAddr]Write address valid.
  output              O_S7_AW_READY   ; //(O)[WrAddr]Write address ready.
  /////////////
  input   [SIW-1:0]   I_S7_W_ID       ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_S7_W_DATA     ; //(I)[WrData]Write data.
  input               I_S7_W_STRB     ; //(I)[WrData]Write strobes.
  input   [ABN-1:0]   I_S7_W_LAST     ; //(I)[WrData]Write last.
  input               I_S7_W_VALID    ; //(I)[WrData]Write valid.
  output              O_S7_W_READY    ; //(O)[WrData]Write ready.
  /////////////
  output  [SIW-1:0]   O_S7_B_ID       ; //(O)[WrResp]Response ID tag.
  output              O_S7_B_VALID    ; //(O)[WrResp]Write response valid.
  input               I_S7_B_READY    ; //(I)[WrResp]Response ready.
  /////////////
  input   [SIW-1:0]   I_S7_AR_ID      ; //(I)[RdAddr]Read address ID.
  input   [   31:0]   I_S7_AR_ADDR    ; //(I)[RdAddr]Read address.
  input   [    7:0]   I_S7_AR_LEN     ; //(I)[RdAddr]Burst length.
  input   [    2:0]   I_S7_AR_SIZE    ; //(I)[RdAddr]Burst size.
  input   [    1:0]   I_S7_AR_BURST   ; //(I)[RdAddr]Burst type.
  input   [    1:0]   I_S7_AR_LOCK    ; //(I)[RdAddr]Lock type.
  input               I_S7_AR_VALID   ; //(I)[RdAddr]Read address valid.
  output              O_S7_AR_READY   ; //(O)[RdAddr]Read address ready.
  /////////////
  output  [SIW-1:0]   O_S7_R_ID       ; //(O)[RdData]Read ID tag.
  output  [ADW-1:0]   O_S7_R_DATA     ; //(O)[RdData]Read data.
  output              O_S7_R_LAST     ; //(O)[RdData]Read last.
  output  [    1:0]   O_S7_R_RESP     ; //(O)[RdData]Read response.
  output              O_S7_R_VALID    ; //(O)[RdData]Read valid.
  input               I_S7_R_READY    ; //(I)[RdData]Read ready.
//&&&&&&&&&&&&&&&&&&
`endif    //X8
//&&&&&&&&&&&&&&&&&&
  //Config & State
  input               Cfg_Arb_Type    ; //(I)Config Arbitrtion Type
                                        //仲裁策略 0:共享;1:优先级（S0为最高优先级）；
  input   [ACN-1:0]   Cfg_Cnl_Mask    ; //(I)Config Channle Mask
                                        //通道掩码 Bit位为0，对应通道不工作
  output  [CCW-1:0]   O_AW_Cnl_Num    ; //(O)AW Bus State Bus Active Channel Number
  output  [CCW-1:0]   O_W_Cnl_Num     ; //(O)W  Bus State Bus Active Channel Number
  output  [CCW-1:0]   O_B_Cnl_Num     ; //(O)B  Bus State Bus Active Channel Number
  output  [CCW-1:0]   O_AR_Cnl_Num    ; //(O)AW Bus State Bus Active Channel Number
  output  [CCW-1:0]   O_R_Cnl_Num     ; //(O)W  Bus State Bus Active Channel Number

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//整理输入信号
//把Slave信号转成数组
//********************************************************/
  /////////////////////////////////////////////////////////
  //Axi Master Signal
  wire              M_AW_Ready  = I_M_AW_READY  ; //(I)[WrAddr]Write address ready.
  wire              M_W_Ready   = I_M_W_READY   ; //(I)[WrData]Write ready.
  wire  [MIW-1:0]   M_B_Id      = I_M_B_ID      ; //(I)[WrResp]Response ID tag.
  wire              M_B_Valid   = I_M_B_VALID   ; //(I)[WrResp]Write response valid.
  wire              M_AR_Ready  = I_M_AR_READY  ; //(I)[RdAddr]Read address ready.
  wire  [MIW-1:0]   M_R_Id      = I_M_R_ID      ; //(I)[RdData]Read ID tag.
  wire  [ADW-1:0]   M_R_Data    = I_M_R_DATA    ; //(I)[RdData]Read data.
  wire              M_R_Last    = I_M_R_LAST    ; //(I)[RdData]Read last.
  wire  [    1:0]   M_R_Resp    = I_M_R_RESP    ; //(I)[RdData]Read response.
  wire              M_R_Valid   = I_M_R_VALID   ; //(I)[RdData]Read valid.

  /////////////////////////////////////////////////////////
  wire  [ACN-1:0]   S_AW_Valid  ; //(I)[WrAddr]Write address valid.
  wire  [ACN-1:0]   S_W_Last    ; //(I)[WrData]Write last.
  wire  [ACN-1:0]   S_W_Valid   ; //(I)[WrData]Write valid.
  wire  [ACN-1:0]   S_B_Ready   ; //(I)[WrResp]Response ready.
  wire  [ACN-1:0]   S_AR_Valid  ; //(I)[RdAddr]Read address valid.
  wire  [ACN-1:0]   S_R_Ready   ; //(I)[RdData]Read ready.

  wire  [SIW-1:0]   S_AW_Id     [ACN-1:0] ; //(I)[WrAddr]Write address ID.
  wire  [   31:0]   S_AW_Addr   [ACN-1:0] ; //(I)[WrAddr]Write address.
  wire  [    7:0]   S_AW_Len    [ACN-1:0] ; //(I)[WrAddr]Burst length.
  wire  [    2:0]   S_AW_Size   [ACN-1:0] ; //(I)[WrAddr]Burst size.
  wire  [    1:0]   S_AW_Burst  [ACN-1:0] ; //(I)[WrAddr]Burst type.
  wire  [    1:0]   S_AW_Lock   [ACN-1:0] ; //(I)[WrAddr]Lock type.
  wire  [SIW-1:0]   S_W_Id      [ACN-1:0] ; //(I)[WrData]Write ID tag.
  wire  [ADW-1:0]   S_W_Data    [ACN-1:0] ; //(I)[WrData]Write data.
  wire  [ABN-1:0]   S_W_Strb    [ACN-1:0] ; //(I)[WrData]Write strobes.
  wire  [SIW-1:0]   S_AR_Id     [ACN-1:0] ; //(I)[RdAddr]Read address ID.
  wire  [   31:0]   S_AR_Addr   [ACN-1:0] ; //(I)[RdAddr]Read address.
  wire  [    7:0]   S_AR_Len    [ACN-1:0] ; //(I)[RdAddr]Burst length.
  wire  [    2:0]   S_AR_Size   [ACN-1:0] ; //(I)[RdAddr]Burst size.
  wire  [    1:0]   S_AR_Burst  [ACN-1:0] ; //(I)[RdAddr]Burst type.
  wire  [    1:0]   S_AR_Lock   [ACN-1:0] ; //(I)[RdAddr]Lock type.

//&&&&&&&&  增加AXI通道需要修改这部分   &&&&&&&&&
//&&&&&&&&  增加AXI通道需要修改这部分   &&&&&&&&&
//&&&&&&&&  增加AXI通道需要修改这部分   &&&&&&&&&
  //S_XXX[n] = Sn_XXX ;
  //     ……       ……
  //S_XXX[1] = S1_XXX ;
  //S_XXX[0] = S0_XXX ;

//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[0]   = I_S0_AW_VALID ;
  assign  S_W_Last  [0]   = I_S0_W_LAST   ;
  assign  S_W_Valid [0]   = I_S0_W_VALID  ;
  assign  S_B_Ready [0]   = I_S0_B_READY  ;
  assign  S_AR_Valid[0]   = I_S0_AR_VALID ;
  assign  S_R_Ready [0]   = I_S0_R_READY  ;  

  assign  S_AW_Id   [0]   = I_S0_AW_ID    ;
  assign  S_AW_Addr [0]   = I_S0_AW_ADDR  ;
  assign  S_AW_Len  [0]   = I_S0_AW_LEN   ;
  assign  S_AW_Size [0]   = I_S0_AW_SIZE  ;
  assign  S_AW_Burst[0]   = I_S0_AW_BURST ;
  assign  S_AW_Lock [0]   = I_S0_AW_LOCK  ;
  assign  S_W_Id    [0]   = I_S0_W_ID     ;
  assign  S_W_Data  [0]   = I_S0_W_DATA   ;
  assign  S_W_Strb  [0]   = I_S0_W_STRB   ;
  assign  S_AR_Id   [0]   = I_S0_AR_ID    ;
  assign  S_AR_Addr [0]   = I_S0_AR_ADDR  ;
  assign  S_AR_Len  [0]   = I_S0_AR_LEN   ;
  assign  S_AR_Size [0]   = I_S0_AR_SIZE  ;
  assign  S_AR_Burst[0]   = I_S0_AR_BURST ;
  assign  S_AR_Lock [0]   = I_S0_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[1]   = I_S1_AW_VALID ;
  assign  S_W_Last  [1]   = I_S1_W_LAST   ;
  assign  S_W_Valid [1]   = I_S1_W_VALID  ;
  assign  S_B_Ready [1]   = I_S1_B_READY  ;
  assign  S_AR_Valid[1]   = I_S1_AR_VALID ;
  assign  S_R_Ready [1]   = I_S1_R_READY  ;  

  assign  S_AW_Id   [1]   = I_S1_AW_ID    ;
  assign  S_AW_Addr [1]   = I_S1_AW_ADDR  ;
  assign  S_AW_Len  [1]   = I_S1_AW_LEN   ;
  assign  S_AW_Size [1]   = I_S1_AW_SIZE  ;
  assign  S_AW_Burst[1]   = I_S1_AW_BURST ;
  assign  S_AW_Lock [1]   = I_S1_AW_LOCK  ;
  assign  S_W_Id    [1]   = I_S1_W_ID     ;
  assign  S_W_Data  [1]   = I_S1_W_DATA   ;
  assign  S_W_Strb  [1]   = I_S1_W_STRB   ;
  assign  S_AR_Id   [1]   = I_S1_AR_ID    ;
  assign  S_AR_Addr [1]   = I_S1_AR_ADDR  ;
  assign  S_AR_Len  [1]   = I_S1_AR_LEN   ;
  assign  S_AR_Size [1]   = I_S1_AR_SIZE  ;
  assign  S_AR_Burst[1]   = I_S1_AR_BURST ;
  assign  S_AR_Lock [1]   = I_S1_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&  
`ifdef      X3  
//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[2]   = I_S2_AW_VALID ;
  assign  S_W_Last  [2]   = I_S2_W_LAST   ;
  assign  S_W_Valid [2]   = I_S2_W_VALID  ;
  assign  S_B_Ready [2]   = I_S2_B_READY  ;
  assign  S_AR_Valid[2]   = I_S2_AR_VALID ;
  assign  S_R_Ready [2]   = I_S2_R_READY  ;  

  assign  S_AW_Id   [2]   = I_S2_AW_ID    ;
  assign  S_AW_Addr [2]   = I_S2_AW_ADDR  ;
  assign  S_AW_Len  [2]   = I_S2_AW_LEN   ;
  assign  S_AW_Size [2]   = I_S2_AW_SIZE  ;
  assign  S_AW_Burst[2]   = I_S2_AW_BURST ;
  assign  S_AW_Lock [2]   = I_S2_AW_LOCK  ;
  assign  S_W_Id    [2]   = I_S2_W_ID     ;
  assign  S_W_Data  [2]   = I_S2_W_DATA   ;
  assign  S_W_Strb  [2]   = I_S2_W_STRB   ;
  assign  S_AR_Id   [2]   = I_S2_AR_ID    ;
  assign  S_AR_Addr [2]   = I_S2_AR_ADDR  ;
  assign  S_AR_Len  [2]   = I_S2_AR_LEN   ;
  assign  S_AR_Size [2]   = I_S2_AR_SIZE  ;
  assign  S_AR_Burst[2]   = I_S2_AR_BURST ;
  assign  S_AR_Lock [2]   = I_S2_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&  
`endif    //X3  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X4  
//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[3]   = I_S3_AW_VALID ;
  assign  S_W_Last  [3]   = I_S3_W_LAST   ;
  assign  S_W_Valid [3]   = I_S3_W_VALID  ;
  assign  S_B_Ready [3]   = I_S3_B_READY  ;
  assign  S_AR_Valid[3]   = I_S3_AR_VALID ;
  assign  S_R_Ready [3]   = I_S3_R_READY  ;  

  assign  S_AW_Id   [3]   = I_S3_AW_ID    ;
  assign  S_AW_Addr [3]   = I_S3_AW_ADDR  ;
  assign  S_AW_Len  [3]   = I_S3_AW_LEN   ;
  assign  S_AW_Size [3]   = I_S3_AW_SIZE  ;
  assign  S_AW_Burst[3]   = I_S3_AW_BURST ;
  assign  S_AW_Lock [3]   = I_S3_AW_LOCK  ;
  assign  S_W_Id    [3]   = I_S3_W_ID     ;
  assign  S_W_Data  [3]   = I_S3_W_DATA   ;
  assign  S_W_Strb  [3]   = I_S3_W_STRB   ;
  assign  S_AR_Id   [3]   = I_S3_AR_ID    ;
  assign  S_AR_Addr [3]   = I_S3_AR_ADDR  ;
  assign  S_AR_Len  [3]   = I_S3_AR_LEN   ;
  assign  S_AR_Size [3]   = I_S3_AR_SIZE  ;
  assign  S_AR_Burst[3]   = I_S3_AR_BURST ;
  assign  S_AR_Lock [3]   = I_S3_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&  
`endif    //X4  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X5  
//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[4]   = I_S4_AW_VALID ;
  assign  S_W_Last  [4]   = I_S4_W_LAST   ;
  assign  S_W_Valid [4]   = I_S4_W_VALID  ;
  assign  S_B_Ready [4]   = I_S4_B_READY  ;
  assign  S_AR_Valid[4]   = I_S4_AR_VALID ;
  assign  S_R_Ready [4]   = I_S4_R_READY  ;  

  assign  S_AW_Id   [4]   = I_S4_AW_ID    ;
  assign  S_AW_Addr [4]   = I_S4_AW_ADDR  ;
  assign  S_AW_Len  [4]   = I_S4_AW_LEN   ;
  assign  S_AW_Size [4]   = I_S4_AW_SIZE  ;
  assign  S_AW_Burst[4]   = I_S4_AW_BURST ;
  assign  S_AW_Lock [4]   = I_S4_AW_LOCK  ;
  assign  S_W_Id    [4]   = I_S4_W_ID     ;
  assign  S_W_Data  [4]   = I_S4_W_DATA   ;
  assign  S_W_Strb  [4]   = I_S4_W_STRB   ;
  assign  S_AR_Id   [4]   = I_S4_AR_ID    ;
  assign  S_AR_Addr [4]   = I_S4_AR_ADDR  ;
  assign  S_AR_Len  [4]   = I_S4_AR_LEN   ;
  assign  S_AR_Size [4]   = I_S4_AR_SIZE  ;
  assign  S_AR_Burst[4]   = I_S4_AR_BURST ;
  assign  S_AR_Lock [4]   = I_S4_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&  
`endif    //X5  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X6  
//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[5]   = I_S5_AW_VALID ;
  assign  S_W_Last  [5]   = I_S5_W_LAST   ;
  assign  S_W_Valid [5]   = I_S5_W_VALID  ;
  assign  S_B_Ready [5]   = I_S5_B_READY  ;
  assign  S_AR_Valid[5]   = I_S5_AR_VALID ;
  assign  S_R_Ready [5]   = I_S5_R_READY  ;  

  assign  S_AW_Id   [5]   = I_S5_AW_ID    ;
  assign  S_AW_Addr [5]   = I_S5_AW_ADDR  ;
  assign  S_AW_Len  [5]   = I_S5_AW_LEN   ;
  assign  S_AW_Size [5]   = I_S5_AW_SIZE  ;
  assign  S_AW_Burst[5]   = I_S5_AW_BURST ;
  assign  S_AW_Lock [5]   = I_S5_AW_LOCK  ;
  assign  S_W_Id    [5]   = I_S5_W_ID     ;
  assign  S_W_Data  [5]   = I_S5_W_DATA   ;
  assign  S_W_Strb  [5]   = I_S5_W_STRB   ;
  assign  S_AR_Id   [5]   = I_S5_AR_ID    ;
  assign  S_AR_Addr [5]   = I_S5_AR_ADDR  ;
  assign  S_AR_Len  [5]   = I_S5_AR_LEN   ;
  assign  S_AR_Size [5]   = I_S5_AR_SIZE  ;
  assign  S_AR_Burst[5]   = I_S5_AR_BURST ;
  assign  S_AR_Lock [5]   = I_S5_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&  
`endif    //X6  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X7  
//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[6]   = I_S6_AW_VALID ;
  assign  S_W_Last  [6]   = I_S6_W_LAST   ;
  assign  S_W_Valid [6]   = I_S6_W_VALID  ;
  assign  S_B_Ready [6]   = I_S6_B_READY  ;
  assign  S_AR_Valid[6]   = I_S6_AR_VALID ;
  assign  S_R_Ready [6]   = I_S6_R_READY  ;  

  assign  S_AW_Id   [6]   = I_S6_AW_ID    ;
  assign  S_AW_Addr [6]   = I_S6_AW_ADDR  ;
  assign  S_AW_Len  [6]   = I_S6_AW_LEN   ;
  assign  S_AW_Size [6]   = I_S6_AW_SIZE  ;
  assign  S_AW_Burst[6]   = I_S6_AW_BURST ;
  assign  S_AW_Lock [6]   = I_S6_AW_LOCK  ;
  assign  S_W_Id    [6]   = I_S6_W_ID     ;
  assign  S_W_Data  [6]   = I_S6_W_DATA   ;
  assign  S_W_Strb  [6]   = I_S6_W_STRB   ;
  assign  S_AR_Id   [6]   = I_S6_AR_ID    ;
  assign  S_AR_Addr [6]   = I_S6_AR_ADDR  ;
  assign  S_AR_Len  [6]   = I_S6_AR_LEN   ;
  assign  S_AR_Size [6]   = I_S6_AR_SIZE  ;
  assign  S_AR_Burst[6]   = I_S6_AR_BURST ;
  assign  S_AR_Lock [6]   = I_S6_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&  
`endif    //X7  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X8  
//&&&&&&&&&&&&&&&&&&  
  assign  S_AW_Valid[7]   = I_S7_AW_VALID ;
  assign  S_W_Last  [7]   = I_S7_W_LAST   ;
  assign  S_W_Valid [7]   = I_S7_W_VALID  ;
  assign  S_B_Ready [7]   = I_S7_B_READY  ;
  assign  S_AR_Valid[7]   = I_S7_AR_VALID ;
  assign  S_R_Ready [7]   = I_S7_R_READY  ;  

  assign  S_AW_Id   [7]   = I_S7_AW_ID    ;
  assign  S_AW_Addr [7]   = I_S7_AW_ADDR  ;
  assign  S_AW_Len  [7]   = I_S7_AW_LEN   ;
  assign  S_AW_Size [7]   = I_S7_AW_SIZE  ;
  assign  S_AW_Burst[7]   = I_S7_AW_BURST ;
  assign  S_AW_Lock [7]   = I_S7_AW_LOCK  ;
  assign  S_W_Id    [7]   = I_S7_W_ID     ;
  assign  S_W_Data  [7]   = I_S7_W_DATA   ;
  assign  S_W_Strb  [7]   = I_S7_W_STRB   ;
  assign  S_AR_Id   [7]   = I_S7_AR_ID    ;
  assign  S_AR_Addr [7]   = I_S7_AR_ADDR  ;
  assign  S_AR_Len  [7]   = I_S7_AR_LEN   ;
  assign  S_AR_Size [7]   = I_S7_AR_SIZE  ;
  assign  S_AR_Burst[7]   = I_S7_AR_BURST ;
  assign  S_AR_Lock [7]   = I_S7_AR_LOCK  ;
//&&&&&&&&&&&&&&&&&&
`endif    //X8
//&&&&&&&&&&&&&&&&&&
//&&&&&&&&  增加AXI通道需要修改这部分   &&&&&&&&&
//&&&&&&&&  增加AXI通道需要修改这部分   &&&&&&&&&
//&&&&&&&&  增加AXI通道需要修改这部分   &&&&&&&&&

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//处理写操作控制信号
//********************************************************/
  /////////////////////////////////////////////////////////
  //Axi Master Signal
  wire                M_AW_Valid    ; //[WrAddr]Write address valid.
  wire                M_W_Valid     ; //[WrData]Write valid.
  wire                M_W_Last      ; //[WrData]Write last.
  wire                M_B_Ready     ; //[WrResp]Response ready.
  //Axi Slave Signal
  wire    [ACN-1:0]   S_AW_Ready    ; //[WrAddr]Write address ready.
  wire    [ACN-1:0]   S_W_Ready     ; //[WrData]Write ready.
  wire    [ACN-1:0]   S_B_Valid     ; //[WrResp]Write response valid.
  //Config & State
  wire                AW_Cnl_End    ; //AW Bus Active Channel Operate End
  wire    [CCW-1:0]   AW_Cnl_Num    ; //AW Bus State Bus Active Channel
  wire    [ACN-1:0]   AW_Cnl_List   ; //AW Bus Active Channel List
  wire                W_Cnl_End     ; //W  Bus Active Channel Operate End
  wire    [CCW-1:0]   W_Cnl_Num     ; //W  Bus State Bus Active Channel
  wire    [ACN-1:0]   W_Cnl_List    ; //W  Bus Active Channel List
  wire                B_Cnl_End     ; //B  Bus Active Channel Operate End
  wire    [CCW-1:0]   B_Cnl_Num     ; //B  Bus State Bus Active Channel
  wire    [ACN-1:0]   B_Cnl_List    ; //B  Bus Active Channel List

  defparam  U1_Axi_Mux_Wr_Ctrl.AXI_CHANNEL_NUM  = AXI_CHANNEL_NUM ;
  defparam  U1_Axi_Mux_Wr_Ctrl.SLAVE_ID_WIDTH   = SLAVE_ID_WIDTH  ;
  defparam  U1_Axi_Mux_Wr_Ctrl.ID_MODE_SEL      = ID_MODE_SEL     ;

  Axi_Mux_Wr_Ctrl   U1_Axi_Mux_Wr_Ctrl
  (
    //System Signal
    .Sys_Clk          ( Sys_Clk       ) , //(I)System Clock
    .Sys_Rst_N        ( Sys_Rst_N     ) , //(I)System Reset
    //Axi Master Signal
    .O_M_AW_VALID     ( M_AW_Valid    ) , //(O)[WrAddr]Write address valid.
    .I_M_AW_READY     ( M_AW_Ready    ) , //(I)[WrAddr]Write address ready.
    .O_M_W_VALID      ( M_W_Valid     ) , //(O)[WrData][WrData]Write valid.
    .I_M_W_READY      ( M_W_Ready     ) , //(I)[WrData][WrData]Write ready.
    .O_M_W_LAST       ( M_W_Last      ) , //(O)[WrData][WrData]Write last.
    .I_M_B_ID         ( M_B_Id        ) , //(I)[WrResp]Response ID tag.
    .I_M_B_VALID      ( M_B_Valid     ) , //(I)[WrResp]Write response valid.
    .O_M_B_READY      ( M_B_Ready     ) , //(O)[WrResp]Response ready.
    //Axi Slave Signal
    .I_S_AW_VALID     ( S_AW_Valid    ) , //(I)[WrAddr]Write address valid.
    .O_S_AW_READY     ( S_AW_Ready    ) , //(O)[WrAddr]Write address ready.
    .I_S_W_VALID      ( S_W_Valid     ) , //(I)[WrData]Write valid.
    .O_S_W_READY      ( S_W_Ready     ) , //(O)[WrData]Write ready.
    .I_S_W_LAST       ( S_W_Last      ) , //(I)[WrData]Write last.
    .O_S_B_VALID      ( S_B_Valid     ) , //(O)[WrResp]Write response valid.
    .I_S_B_READY      ( S_B_Ready     ) , //(I)[WrResp]Response ready.
    //Config & State
    .Cfg_Arb_Type     ( Cfg_Arb_Type  ) , //(I)Config Arbitrtion Type
    .Cfg_Cnl_Mask     ( Cfg_Cnl_Mask  ) , //(I)Config Channle Mask
    .O_AW_Cnl_End     ( AW_Cnl_End    ) , //(O)AW Bus Active Channel Operate End
    .O_AW_Cnl_Num     ( AW_Cnl_Num    ) , //(O)AW Bus State Bus Active Channel
    .O_AW_Cnl_List    ( AW_Cnl_List   ) , //(O)AW Bus Active Channel List
    .O_W_Cnl_End      ( W_Cnl_End     ) , //(O)W  Bus Active Channel Operate End
    .O_W_Cnl_Num      ( W_Cnl_Num     ) , //(O)W  Bus State Bus Active Channel
    .O_W_Cnl_List     ( W_Cnl_List    ) , //(O)W  Bus Active Channel List
    .O_B_Cnl_End      ( B_Cnl_End     ) , //(O)B  Bus Active Channel Operate End
    .O_B_Cnl_Num      ( B_Cnl_Num     ) , //(O)B  Bus State Bus Active Channel
    .O_B_Cnl_List     ( B_Cnl_List    )   //(O)B  Bus Active Channel List
  );

  /////////////////////////////////////////////////////////
  wire  [CCW-1:0]   O_AW_Cnl_Num  = AW_Cnl_Num  ; //(O)AW Bus State Bus Active Channel
  wire  [CCW-1:0]   O_W_Cnl_Num   = W_Cnl_Num   ; //(O)W  Bus State Bus Active Channel
  wire  [CCW-1:0]   O_B_Cnl_Num   = B_Cnl_Num   ; //(O)B  Bus State Bus Active Channel

  /////////////////////////////////////////////////////////
  wire              O_M_AW_VALID  = M_AW_Valid  ; //(O)[WrAddr]Write address valid.
  wire              O_M_W_VALID   = M_W_Valid   ; //(O)[WrData]Write valid.
  wire              O_M_W_LAST    = M_W_Last    ; //(O)[WrData]Write last.
  wire              O_M_B_READY   = M_B_Ready   ; //(O)[WrResp]Response ready.

  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

//222222222222222222222222222222222222222222222222222222222
//处理AXI写操作参数、状态和数据
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [   31:0]   M_AW_Addr   ; //[WrAddr]Write address.
  wire  [    7:0]   M_AW_Len    ; //[WrAddr]Burst length.
  wire  [    2:0]   M_AW_Size   ; //[WrAddr]Burst size.
  wire  [    1:0]   M_AW_Burst  ; //[WrAddr]Burst type.
  wire  [    1:0]   M_AW_Lock   ; //[WrAddr]Lock type.

  assign  M_AW_Addr   = S_AW_Addr [AW_Cnl_Num] ;
  assign  M_AW_Len    = S_AW_Len  [AW_Cnl_Num] ;
  assign  M_AW_Size   = S_AW_Size [AW_Cnl_Num] ;
  assign  M_AW_Burst  = S_AW_Burst[AW_Cnl_Num] ;
  assign  M_AW_Lock   = S_AW_Lock [AW_Cnl_Num] ;

  /////////////////////////////////////////////////////////
  wire  [ADW-1:0]   M_W_Data    ; //[WrData]Write data.
  wire  [ABN-1:0]   M_W_Strb    ; //[WrData]Write strobes.

  assign  M_W_Data    = S_W_Data  [ W_Cnl_Num ] ;
  assign  M_W_Strb    = S_W_Strb  [ W_Cnl_Num ] ;
  /////////////////////////////////////////////////////////
  wire  [SIW-1:0]   S_B_Id  [ACN-1:0] ; //(O)[WrResp]Response ID tag.

  genvar  i ;
  generate
    for (i=0;i<AXI_CHANNEL_NUM;i=i+1)
    begin
      assign    S_B_Id[i]  = M_B_Id[SIW-1:0]  ;
    end
  endgenerate

  /////////////////////////////////////////////////////////
  //Axi Master Signal
  wire  [   31:0]   O_M_AW_ADDR    = M_AW_Addr  ; //(O)[WrAddr]Write address.
  wire  [    7:0]   O_M_AW_LEN     = M_AW_Len   ; //(O)[WrAddr]Burst length.
  wire  [    2:0]   O_M_AW_SIZE    = M_AW_Size  ; //(O)[WrAddr]Burst size.
  wire  [    1:0]   O_M_AW_BURST   = M_AW_Burst ; //(O)[WrAddr]Burst type.
  wire  [    1:0]   O_M_AW_LOCK    = M_AW_Lock  ; //(O)[WrAddr]Lock type.
  /////////////
  wire  [ADW-1:0]   O_M_W_DATA     = M_W_Data   ; //(O)[WrData]Write data.
  wire  [ABN-1:0]   O_M_W_STRB     = M_W_Strb   ; //(O)[WrData]Write strobes.

  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222

//333333333333333333333333333333333333333333333333333333333
//处理AXI读操作参数、状态和数据
//********************************************************/
  /////////////////////////////////////////////////////////
  wire                M_AR_Valid    ; //(O)[RdAddr]Read address valid.
  wire                M_R_Ready     ; //(O)[RdData]Read ready.
  wire    [ACN-1:0]   S_AR_Ready    ; //(O)[RdAddr]Read address ready.
  wire    [ACN-1:0]   S_R_Valid     ; //(O)[RdData]Read valid.
  wire    [ACN-1:0]   S_R_Last      ; //(O)[RdData]Read last.
  //Config & State
  wire                AR_Cnl_End    ; //(O)AW Bus Active Channel Operate End
  wire    [CCW-1:0]   AR_Cnl_Num    ; //(O)AW Bus State Bus Active Channel
  wire    [ACN-1:0]   AR_Cnl_List   ; //(O)AW Bus Active Channel List
  wire                R_Cnl_End     ; //(O)W  Bus Active Channel Operate End
  wire    [CCW-1:0]   R_Cnl_Num     ; //(O)W  Bus State Bus Active Channel
  wire    [ACN-1:0]   R_Cnl_List    ; //(O)W  Bus Active Channel List

  defparam  U3_Axi_Mux_Rd_Ctrl.AXI_CHANNEL_NUM  = AXI_CHANNEL_NUM ;
  defparam  U3_Axi_Mux_Rd_Ctrl.SLAVE_ID_WIDTH   = SLAVE_ID_WIDTH  ;
  defparam  U3_Axi_Mux_Rd_Ctrl.ID_MODE_SEL      = ID_MODE_SEL     ;

  Axi_Mux_Rd_Ctrl   U3_Axi_Mux_Rd_Ctrl
  (
    //System Signal
    .Sys_Clk          ( Sys_Clk       ) , //(I)System Clock
    .Sys_Rst_N        ( Sys_Rst_N     ) , //(I)System Reset
    //Axi Master Signal
    .O_M_AR_VALID     ( M_AR_Valid    ) , //(O)[RdAddr]Read address valid.
    .I_M_AR_READY     ( M_AR_Ready    ) , //(I)[RdAddr]Read address ready.
    .I_M_R_ID         ( M_R_Id        ) , //(I)[RdData]Read ID tag.
    .I_M_R_VALID      ( M_R_Valid     ) , //(I)[RdData]Read valid.
    .O_M_R_READY      ( M_R_Ready     ) , //(O)[RdData]Read ready.
    .I_M_R_LAST       ( M_R_Last      ) , //(I)[RdData]Read last.
    //Axi Slave Signal
    .I_S_AR_VALID     ( S_AR_Valid    ) , //(I)[RdAddr]Read address valid.
    .O_S_AR_READY     ( S_AR_Ready    ) , //(O)[RdAddr]Read address ready.
    .O_S_R_VALID      ( S_R_Valid     ) , //(O)[RdData]Read valid.
    .I_S_R_READY      ( S_R_Ready     ) , //(I)[RdData]Read ready.
    .O_S_R_LAST       ( S_R_Last      ) , //(O)[RdData]Read last.
    //Config & State
    .Cfg_Arb_Type     ( Cfg_Arb_Type  ) , //(I)Config Arbitrtion Type
    .Cfg_Cnl_Mask     ( Cfg_Cnl_Mask  ) , //(I)Config Channle Mask
    .O_AR_Cnl_End     ( AR_Cnl_End    ) , //(O)AR Bus Active Channel Operate End
    .O_AR_Cnl_Num     ( AR_Cnl_Num    ) , //(O)AR Bus State Bus Active Channel
    .O_AR_Cnl_List    ( AR_Cnl_List   ) , //(O)AR Bus Active Channel List
    .O_R_Cnl_End      ( R_Cnl_End     ) , //(O)R  Bus Active Channel Operate End
    .O_R_Cnl_Num      ( R_Cnl_Num     ) , //(O)R  Bus State Bus Active Channel
    .O_R_Cnl_List     ( R_Cnl_List    )   //(O)R  Bus Active Channel List
  );

  /////////////////////////////////////////////////////////
  wire  [CCW-1:0]   O_AR_Cnl_Num  = AR_Cnl_Num  ; //(O)AW Bus State Bus Active Channel
  wire  [CCW-1:0]   O_R_Cnl_Num   = R_Cnl_Num   ; //(O)W  Bus State Bus Active Channel
  
  /////////////////////////////////////////////////////////
  wire              O_M_AR_VALID  = M_AR_Valid  ; //(O)[WrAddr]Write address valid.
  wire              O_M_R_READY   = M_R_Ready   ; //(O)[RdData]Response ready.

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333

//444444444444444444444444444444444444444444444444444444444
//处理AXI读操作参数、状态和数据
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [   31:0]   M_AR_Addr   ; //[WrAddr]Write address.
  wire  [    7:0]   M_AR_Len    ; //[WrAddr]Burst length.
  wire  [    2:0]   M_AR_Size   ; //[WrAddr]Burst size.
  wire  [    1:0]   M_AR_Burst  ; //[WrAddr]Burst type.
  wire  [    1:0]   M_AR_Lock   ; //[WrAddr]Lock type.

  assign  M_AR_Addr   = S_AR_Addr [AR_Cnl_Num] ;
  assign  M_AR_Len    = S_AR_Len  [AR_Cnl_Num] ;
  assign  M_AR_Size   = S_AR_Size [AR_Cnl_Num] ;
  assign  M_AR_Burst  = S_AR_Burst[AR_Cnl_Num] ;
  assign  M_AR_Lock   = S_AR_Lock [AR_Cnl_Num] ;

  /////////////////////////////////////////////////////////
  wire  [SIW-1:0]   S_R_Id  [ACN-1:0] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   S_R_Data[ACN-1:0] ; //(O)[RdData]Read data.
  wire  [    1:0]   S_R_Resp[ACN-1:0] ; //(O)[RdData]Read response.

  genvar  j ;
  generate
    for (j=0;j<AXI_CHANNEL_NUM;j=j+1)
    begin
      assign  S_R_Id  [j]   = M_R_Id[SIW-1:0] ;
      assign  S_R_Data[j]   = M_R_Data        ;
      assign  S_R_Resp[j]   = M_R_Resp        ;
    end
  endgenerate
  
  /////////////////////////////////////////////////////////
  //Axi Master Signal
  wire  [   31:0]   O_M_AR_ADDR     = M_AR_Addr   ; 
  wire  [    7:0]   O_M_AR_LEN      = M_AR_Len    ; 
  wire  [    2:0]   O_M_AR_SIZE     = M_AR_Size   ; 
  wire  [    1:0]   O_M_AR_BURST    = M_AR_Burst  ; 
  wire  [    1:0]   O_M_AR_LOCK     = M_AR_Lock   ; 

  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444

//555555555555555555555555555555555555555555555555555555555
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [MIW-1:0]   M_AW_Id     ; //[WrAddr]Write address ID.
  wire  [MIW-1:0]   M_W_Id      ; //[WrData]Write ID tag.
  wire  [MIW-1:0]   M_AR_Id     ; //[WrAddr]Write address ID.

  generate
    if (ID_MODE_SEL == "Normal")  
    begin
      assign  M_AW_Id   =               S_AW_Id[AW_Cnl_Num]   ;
      assign  M_W_Id    =               S_W_Id [ W_Cnl_Num]   ;
      assign  M_AR_Id   =               S_AR_Id[AR_Cnl_Num]   ;
    end
    else                          
    begin
      assign  M_AW_Id   = {AW_Cnl_Num , S_AW_Id[AW_Cnl_Num] } ;
      assign  M_W_Id    = { W_Cnl_Num , S_W_Id [ W_Cnl_Num] } ;
      assign  M_AR_Id   = {AR_Cnl_Num , S_AR_Id[AR_Cnl_Num] } ;
    end
  endgenerate

  /////////////////////////////////////////////////////////
  wire  [MIW-1:0]   O_M_AW_ID      = M_AW_Id    ; //(O)[WrAddr]Write address ID.
  wire  [MIW-1:0]   O_M_W_ID       = M_W_Id     ; //(O)[WrData]Write ID tag.
  wire  [MIW-1:0]   O_M_AR_ID      = M_AR_Id    ; //(O)[RdAddr]Read address ID. 

  /////////////////////////////////////////////////////////

//666666666666666666666666666666666666666666666666666666666
//
//********************************************************/
  /////////////////////////////////////////////////////////
  //&&&&&&&&  增加AXI通道需要修改这部分   &&&&&&&&&  
  //O_Sn_X_XXX = S_X_Xxx[n] ;

//&&&&&&&&&&&&&&&&&&  
  wire              O_S0_AW_READY   = S_AW_Ready[0] ; //(O)[WrAddr]Write address ready.
  wire              O_S0_W_READY    = S_W_Ready [0] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S0_B_ID       = S_B_Id    [0] ; //(O)[WrResp]Response ID tag.
  wire              O_S0_B_VALID    = S_B_Valid [0] ; //(O)[WrResp]Write response valid.
  wire              O_S0_AR_READY   = S_AR_Ready[0] ; //(O)[WrAddr]Write address ready.
  wire              O_S0_R_VALID    = S_R_Valid [0] ; //(O)[RdData]Write response valid.
  wire              O_S0_R_LAST     = S_R_Last  [0] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S0_R_ID       = S_R_Id    [0] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S0_R_DATA     = S_R_Data  [0] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S0_R_RESP     = S_R_Resp  [0] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
  wire              O_S1_AW_READY   = S_AW_Ready[1] ; //(O)[WrAddr]Write address ready.
  wire              O_S1_W_READY    = S_W_Ready [1] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S1_B_ID       = S_B_Id    [1] ; //(O)[WrResp]Response ID tag.
  wire              O_S1_B_VALID    = S_B_Valid [1] ; //(O)[WrResp]Write response valid.
  wire              O_S1_AR_READY   = S_AR_Ready[1] ; //(O)[WrAddr]Write address ready.
  wire              O_S1_R_VALID    = S_R_Valid [1] ; //(O)[RdData]Write response valid.
  wire              O_S1_R_LAST     = S_R_Last  [1] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S1_R_ID       = S_R_Id    [1] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S1_R_DATA     = S_R_Data  [1] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S1_R_RESP     = S_R_Resp  [1] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
`ifdef      X3  
//&&&&&&&&&&&&&&&&&&  
  wire              O_S2_AW_READY   = S_AW_Ready[2] ; //(O)[WrAddr]Write address ready.
  wire              O_S2_W_READY    = S_W_Ready [2] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S2_B_ID       = S_B_Id    [2] ; //(O)[WrResp]Response ID tag.
  wire              O_S2_B_VALID    = S_B_Valid [2] ; //(O)[WrResp]Write response valid.
  wire              O_S2_AR_READY   = S_AR_Ready[2] ; //(O)[WrAddr]Write address ready.
  wire              O_S2_R_VALID    = S_R_Valid [2] ; //(O)[RdData]Write response valid.
  wire              O_S2_R_LAST     = S_R_Last  [2] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S2_R_ID       = S_R_Id    [2] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S2_R_DATA     = S_R_Data  [2] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S2_R_RESP     = S_R_Resp  [2] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
`endif    //X3  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X4  
//&&&&&&&&&&&&&&&&&&  
  wire              O_S3_AW_READY   = S_AW_Ready[3] ; //(O)[WrAddr]Write address ready.
  wire              O_S3_W_READY    = S_W_Ready [3] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S3_B_ID       = S_B_Id    [3] ; //(O)[WrResp]Response ID tag.
  wire              O_S3_B_VALID    = S_B_Valid [3] ; //(O)[WrResp]Write response valid.
  wire              O_S3_AR_READY   = S_AR_Ready[3] ; //(O)[WrAddr]Write address ready.
  wire              O_S3_R_VALID    = S_R_Valid [3] ; //(O)[RdData]Write response valid.
  wire              O_S3_R_LAST     = S_R_Last  [3] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S3_R_ID       = S_R_Id    [3] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S3_R_DATA     = S_R_Data  [3] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S3_R_RESP     = S_R_Resp  [3] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
`endif    //X4  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X5  
//&&&&&&&&&&&&&&&&&&  
  wire              O_S4_AW_READY   = S_AW_Ready[4] ; //(O)[WrAddr]Write address ready.
  wire              O_S4_W_READY    = S_W_Ready [4] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S4_B_ID       = S_B_Id    [4] ; //(O)[WrResp]Response ID tag.
  wire              O_S4_B_VALID    = S_B_Valid [4] ; //(O)[WrResp]Write response valid.
  wire              O_S4_AR_READY   = S_AR_Ready[4] ; //(O)[WrAddr]Write address ready.
  wire              O_S4_R_VALID    = S_R_Valid [4] ; //(O)[RdData]Write response valid.
  wire              O_S4_R_LAST     = S_R_Last  [4] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S4_R_ID       = S_R_Id    [4] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S4_R_DATA     = S_R_Data  [4] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S4_R_RESP     = S_R_Resp  [4] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
`endif    //X5  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X6  
//&&&&&&&&&&&&&&&&&&  
  wire              O_S5_AW_READY   = S_AW_Ready[5] ; //(O)[WrAddr]Write address ready.
  wire              O_S5_W_READY    = S_W_Ready [5] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S5_B_ID       = S_B_Id    [5] ; //(O)[WrResp]Response ID tag.
  wire              O_S5_B_VALID    = S_B_Valid [5] ; //(O)[WrResp]Write response valid.
  wire              O_S5_AR_READY   = S_AR_Ready[5] ; //(O)[WrAddr]Write address ready.
  wire              O_S5_R_VALID    = S_R_Valid [5] ; //(O)[RdData]Write response valid.
  wire              O_S5_R_LAST     = S_R_Last  [5] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S5_R_ID       = S_R_Id    [5] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S5_R_DATA     = S_R_Data  [5] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S5_R_RESP     = S_R_Resp  [5] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
`endif    //X6  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X7  
//&&&&&&&&&&&&&&&&&&  
  wire              O_S6_AW_READY   = S_AW_Ready[6] ; //(O)[WrAddr]Write address ready.
  wire              O_S6_W_READY    = S_W_Ready [6] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S6_B_ID       = S_B_Id    [6] ; //(O)[WrResp]Response ID tag.
  wire              O_S6_B_VALID    = S_B_Valid [6] ; //(O)[WrResp]Write response valid.
  wire              O_S6_AR_READY   = S_AR_Ready[6] ; //(O)[WrAddr]Write address ready.
  wire              O_S6_R_VALID    = S_R_Valid [6] ; //(O)[RdData]Write response valid.
  wire              O_S6_R_LAST     = S_R_Last  [6] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S6_R_ID       = S_R_Id    [6] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S6_R_DATA     = S_R_Data  [6] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S6_R_RESP     = S_R_Resp  [6] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
`endif    //X7  
//&&&&&&&&&&&&&&&&&&  
//&&&&&&&&&&&&&&&&&&  
`ifdef      X8  
//&&&&&&&&&&&&&&&&&&  
  wire              O_S7_AW_READY   = S_AW_Ready[7] ; //(O)[WrAddr]Write address ready.
  wire              O_S7_W_READY    = S_W_Ready [7] ; //(O)[WrData]Write ready.
  wire  [SIW-1:0]   O_S7_B_ID       = S_B_Id    [7] ; //(O)[WrResp]Response ID tag.
  wire              O_S7_B_VALID    = S_B_Valid [7] ; //(O)[WrResp]Write response valid.
  wire              O_S7_AR_READY   = S_AR_Ready[7] ; //(O)[WrAddr]Write address ready.
  wire              O_S7_R_VALID    = S_R_Valid [7] ; //(O)[RdData]Write response valid.
  wire              O_S7_R_LAST     = S_R_Last  [7] ; //(O)[RdData]Read last.
  wire  [SIW-1:0]   O_S7_R_ID       = S_R_Id    [7] ; //(O)[RdData]Read ID tag.
  wire  [ADW-1:0]   O_S7_R_DATA     = S_R_Data  [7] ; //(O)[RdData]Read data.
  wire  [    1:0]   O_S7_R_RESP     = S_R_Resp  [7] ; //(O)[RdData]Read response.
//&&&&&&&&&&&&&&&&&&  
`endif    //X8  
//&&&&&&&&&&&&&&&&&&  
  /////////////////////////////////////////////////////////
//666666666666666666666666666666666666666666666666666666666

endmodule

///////////////////////////////////////////////////////////







///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:
  AXI写操作控制，操作AW、W、B总线的控制总线

  Establishment : Richard Zhu
  Create date   : 2022-09-29
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Axi_Mux_Wr_Ctrl
(
  //System Signal
  Sys_Clk         , //System Clock
  Sys_Rst_N       , //System Reset
  //Axi Master Signal
  O_M_AW_VALID    , //(O)[WrAddr]Write address valid.
  I_M_AW_READY    , //(I)[WrAddr]Write address ready.
  O_M_W_VALID     , //(O)[WrData][WrData]Write valid.
  I_M_W_READY     , //(I)[WrData][WrData]Write ready.
  O_M_W_LAST      , //(O)[WrData][WrData]Write last.
  I_M_B_ID        , //(I)[WrResp]Response ID tag.
  I_M_B_VALID     , //(I)[WrResp]Write response valid.
  O_M_B_READY     , //(O)[WrResp]Response ready.
  //Axi Slave Signal
  I_S_AW_VALID    , //(I)[WrAddr]Write address valid.
  O_S_AW_READY    , //(O)[WrAddr]Write address ready.
  I_S_W_VALID     , //(I)[WrData]Write valid.
  O_S_W_READY     , //(O)[WrData]Write ready.
  I_S_W_LAST      , //(I)[WrData]Write last.
  O_S_B_VALID     , //(O)[WrResp]Write response valid.
  I_S_B_READY     , //(I)[WrResp]Response ready.
  //Config & State
  Cfg_Arb_Type    , //(I)Config Arbitrtion Type
  Cfg_Cnl_Mask    , //(I)Config Channle Mask
  O_AW_Cnl_End    , //(O)AW Bus Active Channel Operate End
  O_AW_Cnl_Num    , //(O)AW Bus State Bus Active Channel
  O_AW_Cnl_List   , //(O)AW Bus Active Channel List
  O_W_Cnl_End     , //(O)W  Bus Active Channel Operate End
  O_W_Cnl_Num     , //(O)W  Bus State Bus Active Channel
  O_W_Cnl_List    , //(O)W  Bus Active Channel List
  O_B_Cnl_End     , //(O)B  Bus Active Channel Operate End
  O_B_Cnl_Num     , //(O)B  Bus State Bus Active Channel
  O_B_Cnl_List      //(O)B  Bus Active Channel List
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  //////////////
  //AXI通道个数设置
  parameter     AXI_CHANNEL_NUM     = 2 ; //Slave的通道个数

  localparam    CHANNEL_CNT_WIDTH   = $clog2( AXI_CHANNEL_NUM )           ; //通道计数的宽度
  localparam    INFO_FIFO_WIDTH     = AXI_CHANNEL_NUM + CHANNEL_CNT_WIDTH ; //信息FIFO的数据宽度

  //////////////
  //ID 宽度设置
  parameter     SLAVE_ID_WIDTH  =   8 ; //Slave的ID宽度，一般为8
  parameter     ID_MODE_SEL = "Normal"; //"Normal" "Extend"
                //"Normal"  : Slave的ID和Master的ID宽度一致，通道切换处理按顺序执行
                //"Extend"  : Master的ID为Slave ID加通道号，通道切换按Master提供的通道号
                //"Extend" 资源会节省，但是需要连接的AXI支持宽度可调的ID

  localparam    MASTER_ID_WIDTH     = (ID_MODE_SEL    == "Normal" ) //Master的ID宽度
                                    ?  SLAVE_ID_WIDTH
                                    : (SLAVE_ID_WIDTH + CHANNEL_CNT_WIDTH ) ;

  //abbreviation
  //////////////
  localparam    SIW   = SLAVE_ID_WIDTH      ;
  localparam    MIW   = MASTER_ID_WIDTH     ;
  localparam    ACN   = AXI_CHANNEL_NUM     ;
  localparam    CCW   = CHANNEL_CNT_WIDTH   ;
  localparam    IFW   = INFO_FIFO_WIDTH     ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  input               Sys_Clk         ;   //System Clock
  input               Sys_Rst_N       ;   //System Reset
  //Axi Master Signal
  output              O_M_AW_VALID    ; //(O)[WrAddr]Write address valid.
  input               I_M_AW_READY    ; //(I)[WrAddr]Write address ready.
  output              O_M_W_VALID     ; //(O)[WrData]Write valid.
  input               I_M_W_READY     ; //(I)[WrData]Write ready.
  output              O_M_W_LAST      ; //(O)[WrData]Write last.
  input   [MIW-1:0]   I_M_B_ID        ; //(I)[WrResp]Response ID tag.
  input               I_M_B_VALID     ; //(I)[WrResp]Write response valid.
  output              O_M_B_READY     ; //(O)[WrResp]Response ready.

  //Axi Slave Signal
  input   [ACN-1:0]   I_S_AW_VALID    ; //(I)[WrAddr]Write address valid.
  output  [ACN-1:0]   O_S_AW_READY    ; //(O)[WrAddr]Write address ready.
  input   [ACN-1:0]   I_S_W_VALID     ; //(I)[WrData]Write valid.
  output  [ACN-1:0]   O_S_W_READY     ; //(O)[WrData]Write ready.
  input   [ACN-1:0]   I_S_W_LAST      ; //(I)[WrData]Write last.
  output  [ACN-1:0]   O_S_B_VALID     ; //(O)[WrResp]Write response valid.
  input   [ACN-1:0]   I_S_B_READY     ; //(I)[WrResp]Response ready.
  //Config & State
  input               Cfg_Arb_Type    ; //(I)Config Arbitrtion Type
                                        //仲裁策略 0:共享;1:优先级（S0为最高优先级）；
  input   [ACN-1:0]   Cfg_Cnl_Mask    ; //(I)Config Channle Mask
                                        //通道掩码 Bit位为0，对应通道不工作
  output              O_AW_Cnl_End    ; //(O)AW Bus Active Channel Operate End
  output  [CCW-1:0]   O_AW_Cnl_Num    ; //(O)AW Bus State Bus Active Channel
  output  [ACN-1:0]   O_AW_Cnl_List   ; //(O)AW Bus Active Channel List
  output              O_W_Cnl_End     ; //(O)W  Bus Active Channel Operate End
  output  [CCW-1:0]   O_W_Cnl_Num     ; //(O)W  Bus State Bus Active Channel
  output  [ACN-1:0]   O_W_Cnl_List    ; //(O)W  Bus Active Channel List
  output              O_B_Cnl_End     ; //(O)B  Bus Active Channel Operate End
  output  [CCW-1:0]   O_B_Cnl_Num     ; //(O)B  Bus State Bus Active Channel
  output  [ACN-1:0]   O_B_Cnl_List    ; //(O)B  Bus Active Channel List

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//整理输入信号
//********************************************************/
  /////////////////////////////////////////////////////////
  //Axi Slave Signal
  wire              M_AW_Ready  = I_M_AW_READY  ; //(I)[WrAddr]Write address ready.
  wire              M_W_Ready   = I_M_W_READY   ; //(I)[WrData]Write ready.
  wire  [MIW-1:0]   M_B_Id      = I_M_B_ID      ; //(I)[WrResp]Response ID tag.
  wire              M_B_Valid   = I_M_B_VALID   ; //(I)[WrResp]Write response valid.

  /////////////////////////////////////////////////////////
  //Axi Slave Signal
  wire  [ACN-1:0]   S_AW_Valid  = I_S_AW_VALID  ; //(I)[WrAddr]Write address valid.
  wire  [ACN-1:0]   S_W_Valid   = I_S_W_VALID   ; //(I)[WrData]Write valid.
  wire  [ACN-1:0]   S_W_Last    = I_S_W_LAST    ; //(I)[WrData]Write last.
  wire  [ACN-1:0]   S_B_Ready   = I_S_B_READY   ; //(I)[WrResp]Response ready.

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//处理AW总线控制信号
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              AW_Cnl_Sw_En    ; //AW总线通道切换允许，该信号有效，才能进行通道切换
  wire              AW_Act_Cnl_End  ; //AW总线激活通道操作完成
  wire  [CCW-1:0]   AW_Act_Cnl_Num  ; //AW总线激活通道编号
  wire  [ACN-1:0]   AW_Act_Cnl_List ; //AW总线激活通道列表，对应激活通道的Bit为1

  wire              M_AW_Valid      ; //[WrAddr]Write address valid.
  wire  [ACN-1:0]   S_AW_Ready      ; //[WrAddr]Write address ready.

  defparam  U1_Axi_Mux_Addr_Ctrl.AXI_CHANNEL_NUM  = AXI_CHANNEL_NUM ;

  Axi_Mux_Addr_Ctrl U1_Axi_Mux_Addr_Ctrl
  (
    //System Signal
    .Sys_Clk        ( Sys_Clk         ) , //System Clock
    .Sys_Rst_N      ( Sys_Rst_N       ) , //System Reset
    //AXI Bus Siganl
    .O_M_A_VALID    ( M_AW_Valid      ) , //(O)address valid.
    .I_M_A_READY    ( M_AW_Ready      ) , //(I)address ready.
    .I_S_A_VALID    ( S_AW_Valid      ) , //(I)address valid.
    .O_S_A_READY    ( S_AW_Ready      ) , //(O)address ready.
    //Config & State
    .Cfg_Arb_Type   ( Cfg_Arb_Type    ) , //(I)Config Arbitrtion Type
    .Cfg_Cnl_Mask   ( Cfg_Cnl_Mask    ) , //(I)Config Channle Mask
    .I_Cnl_Sw_En    ( AW_Cnl_Sw_En    ) , //(I)Channle Swith Enable
    .O_Act_Cnl_End  ( AW_Act_Cnl_End  ) , //(O)Active Channel Operate End
    .O_Act_Cnl_Num  ( AW_Act_Cnl_Num  ) , //(O)State Bus Active Channel
    .O_Act_Cnl_List ( AW_Act_Cnl_List )   //(O)Active Channel List
  );

  /////////////////////////////////////////////////////////
  wire              O_AW_Cnl_End  = AW_Act_Cnl_End  ; //(O)AW Bus Active Channel Operate End
  wire  [CCW-1:0]   O_AW_Cnl_Num  = AW_Act_Cnl_Num  ; //(O)AW Bus State Bus Active Channel
  wire  [ACN-1:0]   O_AW_Cnl_List = AW_Act_Cnl_List ; //(O)AW Bus Active Channel List

  wire              O_M_AW_VALID  = M_AW_Valid      ; //(O)[WrAddr]Write address valid.
  wire  [ACN-1:0]   O_S_AW_READY  = S_AW_Ready      ; //(O)[WrAddr]Write address ready.

  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

//222222222222222222222222222222222222222222222222222222222
//缓存AW总线处理激活通道
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              AW2W_Wr_En      ; //(I) FIFO Write Enable
  wire  [IFW-1:0]   AW2W_Wr_Info    ; //(I) FIFO Write Data
  wire              AW2W_Rd_En      ; //(I) FIFO Read Enable

  wire  [IFW-1:0]   AW2W_Rd_Info    ; //(O) FIFO Read Data
  wire  [    3:0]   AW2W_Number     ; //(O) FIFO Data Number
  wire              AW2W_Full       ; //(O) FIFO Write Full
  wire              AW2W_Empty      ; //(O) FIFO Write Empty
  wire              AW2W_Error      ; //(O) Fifo Error

  assign    AW2W_Wr_En              = AW_Act_Cnl_End  ;
  assign    AW2W_Wr_Info[IFW-1:ACN] = AW_Act_Cnl_Num  ;
  assign    AW2W_Wr_Info[ACN-1:  0] = AW_Act_Cnl_List ;

  defparam  U2_AW2W_Info_Fifo.OUT_REG      = "No"             ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam  U2_AW2W_Info_Fifo.DATA_WIDTH   = INFO_FIFO_WIDTH  ; //Data Width
  defparam  U2_AW2W_Info_Fifo.DATA_DEPTH   = 8                ; //Address Width

  Info_Fifo_Axi_Mux   U2_AW2W_Info_Fifo
  (
    .Sys_Clk        ( Sys_Clk         ) , //System Clock
    .Sync_Clr       ( ~Sys_Rst_N      ) , //Sync Reset
    .I_Wr_En        ( AW2W_Wr_En      ) , //(I) FIFO Write Enable
    .I_Wr_Data      ( AW2W_Wr_Info    ) , //(I) FIFO Write Data
    .I_Rd_En        ( AW2W_Rd_En      ) , //(I) FIFO Read Enable
    .O_Rd_Data      ( AW2W_Rd_Info    ) , //(O) FIFO Read Data
    .O_Data_Num     ( AW2W_Number     ) , //(O) FIFO Data Number
    .O_Wr_Full      ( AW2W_Full       ) , //(O) FIFO Write Full
    .O_Rd_Empty     ( AW2W_Empty      ) , //(O) FIFO Write Empty
    .O_Fifo_Err     ( AW2W_Error      )   //(O) Fifo Error
  );

  /////////////////////////////////////////////////////////
  assign  AW_Cnl_Sw_En  = (~AW2W_Full)  ; //当信息FIFO存满以后，停止AW总线操作

  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222

//333333333333333333333333333333333333333333333333333333333
//处理W总线的控制信号
//********************************************************/
  /////////////////////////////////////////////////////////
  wire    M_W_Valid   ;
  wire    M_W_Last    ;

  wire    M_W_End       = ( M_W_Valid   & M_W_Ready & M_W_Last ) ;
  wire    W_Act_Cnl_End = M_W_End ;

  assign  AW2W_Rd_En =   M_W_End  ;

  /////////////////////////////////////////////////////////
  wire                W_Info_Val  ; //(I)Info Input Valid
  wire                W_Cnl_End   ; //(I)Active Channel Operate End
  wire    [IFW-1:0]   W_Info_In   ; //(I)Info Input

  wire                W_Cnl_Act   ; //(O)Channel Info Active
  wire    [IFW-1:0]   W_Info_Out  ; //(O)Info Output

  assign  W_Cnl_End   = W_Act_Cnl_End ; //(I)Active Channel Operate End
  assign  W_Info_In   = AW2W_Rd_Info  ; //(I)Info Input

  defparam  U3_W_Info_Process.AXI_CHANNEL_NUM  = AXI_CHANNEL_NUM ;

  Axi_Mux_Info    U3_W_Info_Process
  (
    .Sys_Clk      ( Sys_Clk     ) , //(I)System Clock
    .Sys_Rst_N    ( Sys_Rst_N   ) , //(I)System Reset
    .I_Info_Val   ( W_Info_Val  ) , //(I)Info Input Valid
    .I_Cnl_End    ( W_Cnl_End   ) , //(I)Active Channel Operate End
    .I_Info_In    ( W_Info_In   ) , //(I)Info Input
    .O_Cnl_Act    ( W_Cnl_Act   ) , //(O)Channel Info Active
    .O_Info_Out   ( W_Info_Out  )  //(O)Info Output
  );

  /////////////////////////////////////////////////////////
  wire  [CCW-1:0]  W_Act_Cnl_Num  = W_Info_Out[IFW-1:ACN] ; //W总线激活通道编号
  wire  [ACN-1:0]  W_Act_Cnl_List = W_Info_Out[ACN-1:  0] ; //W总线激活通道列表，激活通道对应Bit为1

  /////////////////////////////////////////////////////////
  assign          M_W_Valid   = |(S_W_Valid       & W_Act_Cnl_List ) ;
  assign          M_W_Last    = |(S_W_Last        & W_Act_Cnl_List ) ;

  wire  [ACN-1:0] S_W_Ready   = ({ACN{M_W_Ready}} & W_Act_Cnl_List ) ;

  /////////////////////////////////////////////////////////
  wire              O_W_Cnl_End   = W_Act_Cnl_End   ; //(O)W  Bus Active Channel Operate End
  wire  [CCW-1:0]   O_W_Cnl_Num   = W_Act_Cnl_Num   ; //(O)W  Bus State Bus Active Channel
  wire  [ACN-1:0]   O_W_Cnl_List  = W_Act_Cnl_List  ; //(O)W  Bus Active Channel List

  wire              O_M_W_VALID   = M_W_Valid       ; //(O)[WrData]Write valid.
  wire              O_M_W_LAST    = M_W_Last        ; //(O)[WrData]Write last.
  wire  [ACN-1:0]   O_S_W_READY   = S_W_Ready       ; //(O)[WrData]Write ready.

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333

//444444444444444444444444444444444444444444444444444444444
//缓存W总线处理的激活通道
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              W2B_Wr_En     ; //(I) FIFO Write Enable
  wire  [IFW-1:0]   W2B_Wr_Info   ; //(I) FIFO Write Data
  wire              W2B_Rd_En     ; //(I) FIFO Read Enable
  wire  [IFW-1:0]   W2B_Rd_Info   ; //(O) FIFO Read Data
  wire  [    3:0]   W2B_Number    ; //(O) FIFO Data Number
  wire              W2B_Full      ; //(O) FIFO Write Full
  wire              W2B_Empty     ; //(O) FIFO Write Empty
  wire              W2B_Error     ; //(O) Fifo Error

  assign    W2B_Wr_En     = W_Act_Cnl_End ;
  assign    W2B_Wr_Info   = W_Info_Out    ;

  defparam  U4_W2B_Info_Fifo.OUT_REG      = "No"             ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam  U4_W2B_Info_Fifo.DATA_WIDTH   = INFO_FIFO_WIDTH  ; //Data Width
  defparam  U4_W2B_Info_Fifo.DATA_DEPTH   = 8                ; //Address Width

  Info_Fifo_Axi_Mux   U4_W2B_Info_Fifo
  (
    .Sys_Clk      ( Sys_Clk       ) , //System Clock
    .Sync_Clr     ( ~Sys_Rst_N    ) , //Sync Reset
    .I_Wr_En      ( W2B_Wr_En     ) , //(I) FIFO Write Enable
    .I_Wr_Data    ( W2B_Wr_Info   ) , //(I) FIFO Write Data
    .I_Rd_En      ( W2B_Rd_En     ) , //(I) FIFO Read Enable
    .O_Rd_Data    ( W2B_Rd_Info   ) , //(O) FIFO Read Data
    .O_Data_Num   ( W2B_Number    ) , //(O) FIFO Data Number
    .O_Wr_Full    ( W2B_Full      ) , //(O) FIFO Write Full
    .O_Rd_Empty   ( W2B_Empty     ) , //(O) FIFO Write Empty
    .O_Fifo_Err   ( W2B_Error     )   //(O) Fifo Error
  );

  /////////////////////////////////////////////////////////
  assign  W_Info_Val = (~W2B_Full) & (~AW2W_Empty)  ;

  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444

//555555555555555555555555555555555555555555555555555555555
//处理B总线的控制信号
//********************************************************/
  /////////////////////////////////////////////////////////
  wire    M_B_Ready ;

  wire    M_B_End       = (M_B_Ready  & M_B_Valid) ;
  wire    B_Act_Cnl_End = M_B_End ;

  assign  W2B_Rd_En     = M_B_End ;

  /////////////////////////////////////////////////////////
  wire                B_Info_Val  ; //(I)Info Input Valid
  wire                B_Cnl_End   ; //(I)Active Channel Operate End
  wire    [IFW-1:0]   B_Info_In   ; //(I)Info Input
  wire                B_Cnl_Act   ; //(O)Channel Info Active
  wire    [IFW-1:0]   B_Info_Out  ; //(O)Info Output

  assign    B_Info_Val  = (~W2B_Empty)  ; //(I)Info Input Valid
  assign    B_Cnl_End   = B_Act_Cnl_End ; //(I)Active Channel Operate End
  assign    B_Info_In   = W2B_Rd_Info   ; //(I)Info Input

  defparam  U5_B_Info_Process.AXI_CHANNEL_NUM  = AXI_CHANNEL_NUM ;

  Axi_Mux_Info    U5_B_Info_Process
  (
    .Sys_Clk      ( Sys_Clk     ) , //(I)System Clock
    .Sys_Rst_N    ( Sys_Rst_N   ) , //(I)System Reset
    .I_Info_Val   ( B_Info_Val  ) , //(I)Info Input Valid
    .I_Cnl_End    ( B_Cnl_End   ) , //(I)Active Channel Operate End
    .I_Info_In    ( B_Info_In   ) , //(I)Info Input
    .O_Cnl_Act    ( B_Cnl_Act   ) , //(O)Channel Info Active
    .O_Info_Out   ( B_Info_Out  )   //(O)Info Output
  );

  /////////////////////////////////////////////////////////
  wire  [CCW-1:0]  B_Act_Cnl_Num  ; //B总线激活通道编号
  wire  [ACN-1:0]  B_Act_Cnl_List ; //B总线激活通道列表，激活通道对应Bit为1

  //ID_MODE_SEL为"Normal", B总线处理顺序按AW和W处理的顺序
  //ID_MODE_SEL为"Extend", B总线处理顺序按Master B_ID的通道信息来处理
  genvar  i ;
  generate
    if ((ID_MODE_SEL    == "Normal" ))
    begin
      assign  B_Act_Cnl_Num  = B_Info_Out[IFW-1:ACN] ;
      assign  B_Act_Cnl_List = B_Info_Out[ACN-1:  0] ;
    end
    else
    begin
      assign B_Act_Cnl_Num  = M_B_Id[MIW-1:SIW] ;
      for (i=0;i<AXI_CHANNEL_NUM;i=i+1)
      begin
        assign B_Act_Cnl_List[i] = ( i ==  M_B_Id[MIW-1:SIW] ) ;
      end
    end
  endgenerate

  /////////////////////////////////////////////////////////
  assign          M_B_Ready   = |(S_B_Ready & B_Act_Cnl_List) ;

  wire  [ACN-1:0] S_B_Valid   = ({ACN{M_B_Valid}} & B_Act_Cnl_List )  ;

  /////////////////////////////////////////////////////////
  wire              O_B_Cnl_End   = B_Act_Cnl_End   ; //(O)B  Bus Active Channel Operate End
  wire  [CCW-1:0]   O_B_Cnl_Num   = B_Act_Cnl_Num   ; //(O)B  Bus State Bus Active Channel
  wire  [ACN-1:0]   O_B_Cnl_List  = B_Act_Cnl_List  ; //(O)B  Bus Active Channel List

  wire              O_M_B_READY   = M_B_Ready       ; //(O)[WrResp]Response ready.
  wire  [ACN-1:0]   O_S_B_VALID   = S_B_Valid       ; //(O)[WrResp]Write response valid.

  /////////////////////////////////////////////////////////
//555555555555555555555555555555555555555555555555555555555

endmodule

///////////////////////////////////////////////////////////







///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:
  AXI读操作控制; 操作AR、R总线的控制信号

  Establishment : Richard Zhu
  Create date   : 2022-09-29
  Versions      : V0.1
  Revision of records:
  Ver0.1

  --2022-10-12 Axi_Mux_Rd_Ctrl
    修改了 Info_Fifo 的深度， 使AR总线和R总线尽可能解耦

**********************************************************/
module  Axi_Mux_Rd_Ctrl
(
  //System Signal
  Sys_Clk         , //System Clock
  Sys_Rst_N       , //System Reset
  //Axi Master Signal
  O_M_AR_VALID    , //(O)[RdAddr]Read address valid.
  I_M_AR_READY    , //(I)[RdAddr]Read address ready.
  I_M_R_ID        , //(I)[RdData]Read ID tag.
  I_M_R_VALID     , //(I)[RdData]Read valid.
  O_M_R_READY     , //(O)[RdData]Read ready.
  I_M_R_LAST      , //(I)[RdData]Read last.
  //Axi Slave Signal
  I_S_AR_VALID    , //(I)[RdAddr]Read address valid.
  O_S_AR_READY    , //(O)[RdAddr]Read address ready.
  O_S_R_VALID     , //(O)[RdData]Read valid.
  I_S_R_READY     , //(I)[RdData]Read ready.
  O_S_R_LAST      , //(O)[RdData]Read last.
  //Config & State
  Cfg_Arb_Type    , //(I)Config Arbitrtion Type
  Cfg_Cnl_Mask    , //(I)Config Channle Mask
  O_AR_Cnl_End    , //(O)AR Bus Active Channel Operate End
  O_AR_Cnl_Num    , //(O)AR Bus State Bus Active Channel
  O_AR_Cnl_List   , //(O)AR Bus Active Channel List
  O_R_Cnl_End     , //(O)R  Bus Active Channel Operate End
  O_R_Cnl_Num     , //(O)R  Bus State Bus Active Channel
  O_R_Cnl_List      //(O)R  Bus Active Channel List
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  //////////////
  //AXI通道个数设置
  parameter     AXI_CHANNEL_NUM     = 2 ; //Slave的通道个数

  localparam    CHANNEL_CNT_WIDTH   = $clog2( AXI_CHANNEL_NUM )           ; //通道计数的宽度
  localparam    INFO_FIFO_WIDTH     = AXI_CHANNEL_NUM + CHANNEL_CNT_WIDTH ; //信息FIFO的数据宽度

  //////////////
  //ID 宽度设置
  parameter     SLAVE_ID_WIDTH  =   8 ; //Slave的ID宽度，一般为8
  parameter     ID_MODE_SEL = "Normal"; //"Normal" "Extend"
                //"Normal"  : Slave的ID和Master的ID宽度一致，通道切换处理按顺序执行
                //"Extend"  : Master的ID为Slave ID加通道号，通道切换按Master提供的通道号
                //"Extend" 资源会节省，但是需要连接的AXI支持宽度可调的ID

  localparam    MASTER_ID_WIDTH     = (ID_MODE_SEL    == "Normal" ) //Master的ID宽度
                                    ?  SLAVE_ID_WIDTH
                                    : (SLAVE_ID_WIDTH + CHANNEL_CNT_WIDTH ) ;

  //abbreviation
  //////////////
  localparam    SIW   = SLAVE_ID_WIDTH      ;
  localparam    MIW   = MASTER_ID_WIDTH     ;
  localparam    ACN   = AXI_CHANNEL_NUM     ;
  localparam    CCW   = CHANNEL_CNT_WIDTH   ;
  localparam    IFW   = INFO_FIFO_WIDTH     ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  input               Sys_Clk         ;   //System Clock
  input               Sys_Rst_N       ;   //System Reset
  //Axi Master Signal
  output              O_M_AR_VALID    ; //(O)[RdAddr]Read address valid.
  input               I_M_AR_READY    ; //(I)[RdAddr]Read address ready.
  input   [MIW-1:0]   I_M_R_ID        ; //(I)[RdData]Read ID tag.
  input               I_M_R_VALID     ; //(I)[RdData]Read valid.
  output              O_M_R_READY     ; //(O)[RdData]Read ready.
  input               I_M_R_LAST      ; //(I)[RdData]Read last.
  //Axi Slave Signal
  input   [ACN-1:0]   I_S_AR_VALID    ; //(I)[RdAddr]Read address valid.
  output  [ACN-1:0]   O_S_AR_READY    ; //(O)[RdAddr]Read address ready.
  output  [ACN-1:0]   O_S_R_VALID     ; //(O)[RdData]Read valid.
  input   [ACN-1:0]   I_S_R_READY     ; //(I)[RdData]Read ready.
  output  [ACN-1:0]   O_S_R_LAST      ; //(O)[RdData]Read last.
  //Config & State
  input               Cfg_Arb_Type    ; //(I)Config Arbitrtion Type
                                        //仲裁策略 0:共享;1:优先级（S0为最高优先级）；
  input   [ACN-1:0]   Cfg_Cnl_Mask    ; //(I)Config Channle Mask
                                        //通道掩码 Bit位为0，对应通道不工作
  output              O_AR_Cnl_End    ; //(O)AW Bus Active Channel Operate End
  output  [CCW-1:0]   O_AR_Cnl_Num    ; //(O)AW Bus State Bus Active Channel
  output  [ACN-1:0]   O_AR_Cnl_List   ; //(O)AW Bus Active Channel List
  output              O_R_Cnl_End     ; //(O)W  Bus Active Channel Operate End
  output  [CCW-1:0]   O_R_Cnl_Num     ; //(O)W  Bus State Bus Active Channel
  output  [ACN-1:0]   O_R_Cnl_List    ; //(O)W  Bus Active Channel List

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//整理输入信号
//********************************************************/
  /////////////////////////////////////////////////////////
  //Axi Slave Signal
  wire              M_AR_Ready    = I_M_AR_READY  ; //(I)[RdAddr]Read address ready.
  wire  [MIW-1:0]   M_R_Id        = I_M_R_ID      ; //(I)[RdData]Read ID tag.
  wire              M_R_Valid     = I_M_R_VALID   ; //(I)[RdData]Read valid.
  wire              M_R_Last      = I_M_R_LAST    ; //(I)[RdData]Read last.

  /////////////////////////////////////////////////////////
  //Axi Slave Signal
  wire  [ACN-1:0]   S_AR_Valid    = I_S_AR_VALID  ; //(I)[RdAddr]Read address valid.
  wire  [ACN-1:0]   S_R_Ready     = I_S_R_READY   ; //(I)[RdData]Read ready.

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//处理AR总线控制信号
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              AR_Cnl_Sw_En    ; //AR总线通道切换允许，该信号有效，才能进行通道切换
  wire              AR_Act_Cnl_End  ; //AR总线激活通道操作完成
  wire  [CCW-1:0]   AR_Act_Cnl_Num  ; //AR总线激活通道编号
  wire  [ACN-1:0]   AR_Act_Cnl_List ; //AR总线激活通道列表，对应激活通道的Bit为1

  wire              M_AR_Valid      ; //(O)[RdAddr]Read address valid.
  wire  [ACN-1:0]   S_AR_Ready      ; //(O)[RdAddr]Read address ready.

  defparam  U1_Axi_Mux_AR_Ctrl.AXI_CHANNEL_NUM  = AXI_CHANNEL_NUM ;

  Axi_Mux_Addr_Ctrl U1_Axi_Mux_AR_Ctrl
  (
    //System Signal
    .Sys_Clk          ( Sys_Clk         ) , //System Clock
    .Sys_Rst_N        ( Sys_Rst_N       ) , //System Reset
    //AXI Bus Siganl
    .O_M_A_VALID      ( M_AR_Valid      ) , //(O)address valid.
    .I_M_A_READY      ( M_AR_Ready      ) , //(I)address ready.
    .I_S_A_VALID      ( S_AR_Valid      ) , //(I)address valid.
    .O_S_A_READY      ( S_AR_Ready      ) , //(O)address ready.
    //Config & State
    .Cfg_Arb_Type     ( Cfg_Arb_Type    ) , //(I)Config Arbitrtion Type
    .Cfg_Cnl_Mask     ( Cfg_Cnl_Mask    ) , //(I)Config Channle Mask
    .I_Cnl_Sw_En      ( AR_Cnl_Sw_En    ) , //(I)Channle Swith Enable
    .O_Act_Cnl_End    ( AR_Act_Cnl_End  ) , //(O)Active Channel Operate End
    .O_Act_Cnl_Num    ( AR_Act_Cnl_Num  ) , //(O)State Bus Active Channel
    .O_Act_Cnl_List   ( AR_Act_Cnl_List )   //(O)Active Channel List
  );

  /////////////////////////////////////////////////////////
  wire              O_AR_Cnl_End  = AR_Act_Cnl_End  ; //(O)AW Bus Active Channel Operate End
  wire  [CCW-1:0]   O_AR_Cnl_Num  = AR_Act_Cnl_Num  ; //(O)AW Bus State Bus Active Channel
  wire  [ACN-1:0]   O_AR_Cnl_List = AR_Act_Cnl_List ; //(O)AW Bus Active Channel List

  wire              O_M_AR_VALID  = M_AR_Valid      ; //(O)[WrAddr]Write address valid.
  wire  [ACN-1:0]   O_S_AR_READY  = S_AR_Ready      ; //(O)[WrAddr]Write address ready.

  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

//222222222222222222222222222222222222222222222222222222222
//缓存AR总线处理激活通道
//********************************************************/
  /////////////////////////////////////////////////////////

  /////////////////////////////////////////////////////////
  wire              AR2R_Wr_En        ; //(I) FIFO Write Enable
  wire  [IFW-1:0]   AR2R_Wr_Info      ; //(I) FIFO Write Data
  wire              AR2R_Rd_En        ; //(I) FIFO Read Enable
  wire  [IFW-1:0]   AR2R_Rd_Info      ; //(O) FIFO Read Data
  wire  [    4:0]   AR2R_Number       ; //(O) FIFO Data Number
  wire              AR2R_Full         ; //(O) FIFO Write Full
  wire              AR2R_Empty        ; //(O) FIFO Write Empty
  wire              AR2R_Error        ; //(O) Fifo Error

  assign      AR2R_Wr_En              = AR_Act_Cnl_End  ; //AR总线激活通道操作完成
  assign      AR2R_Wr_Info[IFW-1:ACN] = AR_Act_Cnl_Num  ; //AR总线激活通道编号
  assign      AR2R_Wr_Info[ACN-1:  0] = AR_Act_Cnl_List ; //AR总线激活通道列表，对应激活通道的Bit为1

  defparam  U2_AR2R_Info_Fifo.OUT_REG      = "No"             ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam  U2_AR2R_Info_Fifo.DATA_WIDTH   = INFO_FIFO_WIDTH  ; //Data Width
  defparam  U2_AR2R_Info_Fifo.DATA_DEPTH   = 16               ; //Address Width

  Info_Fifo_Axi_Mux   U2_AR2R_Info_Fifo
  (
    .Sys_Clk        ( Sys_Clk         ) , //System Clock
    .Sync_Clr       ( ~Sys_Rst_N      ) , //Sync Reset
    .I_Wr_En        ( AR2R_Wr_En      ) , //(I) FIFO Write Enable
    .I_Wr_Data      ( AR2R_Wr_Info    ) , //(I) FIFO Write Data
    .I_Rd_En        ( AR2R_Rd_En      ) , //(I) FIFO Read Enable
    .O_Rd_Data      ( AR2R_Rd_Info    ) , //(O) FIFO Read Data
    .O_Data_Num     ( AR2R_Number     ) , //(O) FIFO Data Number
    .O_Wr_Full      ( AR2R_Full       ) , //(O) FIFO Write Full
    .O_Rd_Empty     ( AR2R_Empty      ) , //(O) FIFO Write Empty
    .O_Fifo_Err     ( AR2R_Error      )   //(O) Fifo Error
  );

  /////////////////////////////////////////////////////////
  assign  AR_Cnl_Sw_En  = (ID_MODE_SEL == "Normal") ? (~AR2R_Full) : 1'h1 ; //当信息FIFO存满以后，停止AR总线操作

  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222

//333333333333333333333333333333333333333333333333333333333
//处理R总线控制信号
//********************************************************/
  /////////////////////////////////////////////////////////
  wire    M_R_Ready ;

  wire    M_R_End         = (M_R_Ready  & M_R_Valid & M_R_Last) ;
  wire    R_Act_Cnl_End   = M_R_End ;

  assign  AR2R_Rd_En      = M_R_End ;

  /////////////////////////////////////////////////////////
  wire                R_Info_Val  ; //(I)Info Input Valid
  wire                R_Cnl_End   ; //(I)Active Channel Operate End
  wire    [IFW-1:0]   R_Info_In   ; //(I)Info Input
  wire                R_Cnl_Act   ; //(O)Channel Info Active
  wire    [IFW-1:0]   R_Info_Out  ; //(O)Info Output

  assign  R_Info_Val  = (~AR2R_Empty) ; //信息FIFO非空，数据有效
  assign  R_Cnl_End   = R_Act_Cnl_End ; //激活通道操作结束
  assign  R_Info_In   = AR2R_Rd_Info  ; //AR2R的读信息为R处理的信息输入

  defparam  U3_R_Info_Process.AXI_CHANNEL_NUM  = AXI_CHANNEL_NUM ;

  Axi_Mux_Info    U3_R_Info_Process
  (
    .Sys_Clk      ( Sys_Clk     ) , //(I)System Clock
    .Sys_Rst_N    ( Sys_Rst_N   ) , //(I)System Reset
    .I_Info_Val   ( R_Info_Val  ) , //(I)Info Input Valid
    .I_Cnl_End    ( R_Cnl_End   ) , //(I)Active Channel Operate End
    .I_Info_In    ( R_Info_In   ) , //(I)Info Input
    .O_Cnl_Act    ( R_Cnl_Act   ) , //(O)Channel Info Active
    .O_Info_Out   ( R_Info_Out  )   //(O)Info Output
  );

  /////////////////////////////////////////////////////////
  wire  [CCW-1:0]  R_Act_Cnl_Num  ; //AR总线激活通道编号
  wire  [ACN-1:0]  R_Act_Cnl_List ; //AR总线激活通道列表，对应激活通道的Bit为1

  //ID_MODE_SEL为"Normal", B总线处理顺序按AW和W处理的顺序
  //ID_MODE_SEL为"Extend", B总线处理顺序按Master B_ID的通道信息来处理
  genvar  i ;
  generate
    if (ID_MODE_SEL == "Normal" )
    begin
      assign  R_Act_Cnl_Num  = R_Info_Out[IFW-1:ACN] ;
      assign  R_Act_Cnl_List = R_Info_Out[ACN-1:  0] ;
    end
    else
    begin
      assign R_Act_Cnl_Num  = M_R_Id[MIW-1:SIW] ;
      for (i=0;i<AXI_CHANNEL_NUM;i=i+1)
      begin
        assign R_Act_Cnl_List[i] = ( i ==  M_R_Id[MIW-1:SIW] ) ;
      end
    end
  endgenerate

  /////////////////////////////////////////////////////////
  assign          M_R_Ready   = | (R_Act_Cnl_List & S_R_Ready         ) ;

  wire  [ACN-1:0] S_R_Valid   =   (R_Act_Cnl_List & {ACN{M_R_Valid}}  ) ;
  wire  [ACN-1:0] S_R_Last    =   (R_Act_Cnl_List & {ACN{M_R_Last }}  ) ;

  /////////////////////////////////////////////////////////
  wire              O_R_Cnl_End   = R_Act_Cnl_End   ; //(O)R  Bus Active Channel Operate End
  wire  [CCW-1:0]   O_R_Cnl_Num   = R_Act_Cnl_Num   ; //(O)R  Bus State Bus Active Channel
  wire  [ACN-1:0]   O_R_Cnl_List  = R_Act_Cnl_List  ; //(O)R  Bus Active Channel List

  wire              O_M_R_READY   = M_R_Ready       ; //(O)[RdData]Response ready.
  wire  [ACN-1:0]   O_S_R_VALID   = S_R_Valid       ; //(O)[RdData]Write response valid.
  wire  [ACN-1:0]   O_S_R_LAST    = S_R_Last        ; //(O)[RdData]Read last.

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333

endmodule

///////////////////////////////////////////////////////////









///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2022-09-24
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/
module  Info_Fifo_Axi_Mux
(
  Sys_Clk     , //System Clock
  Sync_Clr    , //Sync Reset
  I_Wr_En     , //(I) FIFO Write Enable
  I_Wr_Data   , //(I) FIFO Write Data
  I_Rd_En     , //(I) FIFO Read Enable
  O_Rd_Data   , //(I) FIFO Read Data
  O_Data_Num  , //(I) FIFO Data Number
  O_Wr_Full   , //(O) FIFO Write Full
  O_Rd_Empty  , //(O) FIFO Write Empty
  O_Fifo_Err    //Fifo Error
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  parameter   OUT_REG       = "No"  ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  parameter   DATA_WIDTH    = 32    ; //Data Width
  parameter   DATA_DEPTH    = 8     ; //Address Width
  parameter   INITIAL_VALUE = 8'h0  ;

  localparam  ADDR_WIDTH    = $clog2(DATA_DEPTH)  ;
  localparam  SRL8_NUMBER   = (DATA_DEPTH / 8) + (((DATA_DEPTH % 8) == 0) ? 0 : 1 ) ;


  localparam  DW  = DATA_WIDTH    ;
  localparam  AW  = ADDR_WIDTH    ;
  localparam  SN  = SRL8_NUMBER   ;

  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  input             Sys_Clk     ; //System Clock
  input             Sync_Clr    ; //Sync Reset
  input             I_Wr_En     ; //(I) Write Enable
  input   [DW-1:0]  I_Wr_Data   ; //(I) Write Data
  input             I_Rd_En     ; //(I) Read Enable
  output  [DW-1:0]  O_Rd_Data   ; //(O) Read Data
  output  [AW  :0]  O_Data_Num  ; //(O) Ram Data Number
  output            O_Wr_Full   ; //(O) FIFO Write Full
  output            O_Rd_Empty  ; //(O) FIFO Write Empty
  output            O_Fifo_Err  ; //(O) FIFO Error

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//整理输入信号
//********************************************************/
  /////////////////////////////////////////////////////////
  wire            Wr_En     = I_Wr_En     ; //Write Enable
  wire  [DW-1:0]  Wr_Data   = I_Wr_Data   ; //Write Data
  wire            Rd_En     = I_Rd_En     ; //Read Enable

  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   Wr_Full     = 1'h0  ;
  reg   Rd_Empty    = 1'h1  ;

  wire  Fifo_Wr_En  = Wr_En & ( ~Wr_Full  ) ;
  wire  Fifo_Rd_En  = Rd_En & ( ~Rd_Empty ) ;

  /////////////////////////////////////////////////////////
  reg   [AW:0]  Data_Num  = {AW+1{1'h0}}  ;

  always @(posedge Sys_Clk)
  begin
    if (Sync_Clr)           Data_Num  <= {AW+1{1'h0}} ;
    else if (Fifo_Wr_En ^ Fifo_Rd_En)
    begin
      if (Fifo_Wr_En)       Data_Num  <= Data_Num + {{AW{1'h0}},1'h1} ;
      else if (Fifo_Rd_En)  Data_Num  <= Data_Num - {{AW{1'h0}},1'h1} ;
    end
  end

  /////////////////////////////////////////////////////////
  wire    [AW  :0]  Out_Sel  ;

  assign  Out_Sel = (|Data_Num)   ? ( DATA_DEPTH  - Data_Num) : {AW+1{1'h0}} ;

  /////////////////////////////////////////////////////////
  wire    [AW:0]    O_Data_Num  = Data_Num  ; //(O)Data Number In Fifo

  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////

//111111111111111111111111111111111111111111111111111111111

//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [   2:0]  Shift_Out_Sel   = Out_Sel[2:0]  ;
  wire            Shift_Clk_En    = Fifo_Wr_En    ;

  wire  [DW-1:0]  Shift_Data_In   [SN-1:0]  ;
  wire  [DW-1:0]  Shift_Data_Out  [SN-1:0]  ;
  wire  [DW-1:0]  Shift_Q7_Out    [SN  :0]  ; //(O)Shift Output

  genvar  i , j ;
  generate
    for (i=0; i<SRL8_NUMBER ; i=i+1)
    begin : U_SRL8_D
      if (i==SRL8_NUMBER-1) assign  Shift_Data_In[i]  = ~Wr_Data          ;
      else                  assign  Shift_Data_In[i]  = Shift_Q7_Out[i+1] ;

      for (j=0; j<DATA_WIDTH; j=j+1)
      begin : U_SRL8_W
        EFX_SRL8
        #(
            .CLK_POLARITY ( 1'b1            ) , // clk polarity
            .CE_POLARITY  ( 1'b1            ) , // clk polarity
            .INIT         ( INITIAL_VALUE   )   // 8-bit initial value
        )
        srl8_inst
        (
            .A      ( Shift_Out_Sel         ) ,   // 3-bit address select for Q
            .D      ( Shift_Data_In [i][j]  ) ,   // 1-bit data-in
            .CLK    ( Sys_Clk               ) ,   // clock
            .CE     ( Shift_Clk_En          ) ,   // clock enable
            .Q      ( Shift_Data_Out[i][j]  ) ,   // 1-bit data output
            .Q7     ( Shift_Q7_Out  [i][j]  )     // 1-bit last shift register output
        );
      end
    end
  endgenerate

//222222222222222222222222222222222222222222222222222222222

//333333333333333333333333333333333333333333333333333333333
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [DW-1:0]  Data_Out  = {DW{1'h0}}  ;
  reg   [DW-1:0]  Shift_Out = {DW{1'h0}}  ;

  always @(posedge  Sys_Clk )
  begin
    if (Sync_Clr)               Data_Out  <=  {DW{1'h0}}  ;
    else if (SRL8_NUMBER == 1)  Data_Out  <=  Shift_Data_Out[0][DW-1:0]  ;
    else
    begin
      if (Out_Sel != 0 )        Data_Out  <=  Shift_Data_Out[Out_Sel[AW-1:3]][DW-1:0]  ;
      else if (Shift_Clk_En)    Data_Out  <=  Wr_Data     ;
      else                      Data_Out  <=  Shift_Data_Out[Out_Sel[AW-1:3]][DW-1:0]  ;
    end
  end

  /////////////////////////////////////////////////////////
  reg  [DW-1:0]  Rd_Data   ;

  always @ ( * )
  begin
    if (OUT_REG == "Yes")           Rd_Data = Data_Out  ;
    else if ( (SRL8_NUMBER <= 1) )  Rd_Data = Shift_Data_Out[              0][DW-1:0] ;
    else                            Rd_Data = Shift_Data_Out[Out_Sel[AW:3]][DW-1:0] ;
  end

  /////////////////////////////////////////////////////////
  wire  [DW-1:0]  O_Rd_Data   = Rd_Data ; //(O) Read Data

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333

//444444444444444444444444444444444444444444444444444444444
//
//********************************************************/
  /////////////////////////////////////////////////////////
  localparam  [AW:0]  FULL_ENTER      = DATA_DEPTH  - {{AW{1'h0}},1'h1} ;
  localparam  [AW:0]  EMPTY_ENTER     = {{AW{1'h0}} , 1'h1  }  ;

  /////////////////////////////////////////////////////////
  always @(posedge Sys_Clk)
  begin
    if (Sync_Clr)           Wr_Full   <=  1'h0 ;
    else if (Fifo_Rd_En)    Wr_Full   <=  1'h0 ;
    else if (Fifo_Wr_En)    Wr_Full   <=  (Data_Num == FULL_ENTER)  ;
  end

  /////////////////////////////////////////////////////////
  always @(posedge Sys_Clk)
  begin
    if (Sync_Clr)           Rd_Empty  <=  1'h1 ;
    else if (Fifo_Wr_En)    Rd_Empty  <=  1'h0 ;
    else if (Fifo_Rd_En)    Rd_Empty  <=  (Data_Num == EMPTY_ENTER) ;
  end

  /////////////////////////////////////////////////////////
  reg   Fifo_Err  = 1'h0 ;

  always @(posedge Sys_Clk)   Fifo_Err  <=  (Rd_En & Rd_Empty) | (Wr_En & Wr_Full) ;

  /////////////////////////////////////////////////////////
  assign    O_Wr_Full   = Wr_Full   ; //(O) FIFO Write Full
  assign    O_Rd_Empty  = Rd_Empty  ; //(O) FIFO Write Empty
  assign    O_Fifo_Err  = Fifo_Err  ; //(O) Fifo Error

  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444

endmodule

///////////////////////////////////////////////////////////








///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:
  处理Addr总线（AW、AR）的控制信号；
  根据仲裁策略，确定当前处理的通道编号和列表

  Establishment : Richard Zhu
  Create date   : 2022-09-29
  Versions      : V0.1
  Revision of records:
  Ver0.1

  --2022-10-12  Axi_Mux_Addr_Ctrl
    修改了通道切换状态机（ Sta_Cnl_Switch ）, 提高了切换效率
**********************************************************/
module  Axi_Mux_Addr_Ctrl
(
  //System Signal
  Sys_Clk         , //System Clock
  Sys_Rst_N       , //System Reset
  //AXI Bus Siganl
  O_M_A_VALID     , //(O)address valid.
  I_M_A_READY     , //(I)address ready.
  I_S_A_VALID     , //(I)address valid.
  O_S_A_READY     , //(O)address ready.
  //Config & State
  Cfg_Arb_Type    , //(I)Config Arbitrtion Type
  Cfg_Cnl_Mask    , //(I)Config Channle Mask
  I_Cnl_Sw_En     , //(I)Channle Swith Enable
  O_Act_Cnl_End   , //(O)Active Enable
  O_Act_Cnl_Num   , //(O)Active Channel Number
  O_Act_Cnl_List    //(O)Active Channel List
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  //////////////
  //AXI通道个数设置
  parameter     AXI_CHANNEL_NUM     = 2 ; //Slave的通道个数

  localparam    CHANNEL_CNT_WIDTH   = $clog2( AXI_CHANNEL_NUM ) ; //通道计数的宽度

  //abbreviation
  //////////////
  localparam    ACN   = AXI_CHANNEL_NUM     ;
  localparam    CCW   = CHANNEL_CNT_WIDTH   ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  input               Sys_Clk         ; //System Clock
  input               Sys_Rst_N       ; //System Reset
  //Axi Master Signal   
  output              O_M_A_VALID     ; //(O)address valid.
  input               I_M_A_READY     ; //(I)address ready.

  //Axi Slave Signal    
  input   [ACN-1:0]   I_S_A_VALID     ; //(I)address valid.
  output  [ACN-1:0]   O_S_A_READY     ; //(O)address ready.
  //Config & State    
  input               Cfg_Arb_Type    ; //(I)Config Arbitrtion Type
                                        //仲裁策略 0:共享;1:优先级（S0为最高优先级）；
  input   [ACN-1:0]   Cfg_Cnl_Mask    ; //(I)Config Channle Mask
                                        //通道掩码 Bit位为0，对应通道不工作
  input               I_Cnl_Sw_En     ; //(I)Channle Swith Enable
  output              O_Act_Cnl_End   ; //(O)Active Enable
  output  [CCW-1:0]   O_Act_Cnl_Num   ; //(O)State Bus Active Channel
  output  [ACN-1:0]   O_Act_Cnl_List  ; //(O)Active Channel List

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//输入数据处理
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              M_A_Ready   = I_M_A_READY   ; //(I)[RdAddr]Read address ready.
  wire  [ACN-1:0]   S_A_Valid   = I_S_A_VALID   ; //(I)[RdAddr]Read address valid.

  wire              Cnl_Sw_En   = I_Cnl_Sw_En   ; //(I)Channle Swith Enable
  
  /////////////////////////////////////////////////////////
  //通过掩码确定有效Valid信号
  wire  [ACN-1:0]   Effe_S_Val  = S_A_Valid & Cfg_Cnl_Mask  ;

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              M_A_Valid   ; //(O)address valid.
  wire  [ACN-1:0]   S_A_Ready   ; //(O)address ready.
  
  wire              M_A_End     = ( M_A_Ready   & M_A_Valid ) ; 

  /////////////////////////////////////////////////////////
  reg               Sta_Cnl_Switch      = 2'h0                  ; //通道切换状态机
  reg   [CCW-1:0]   Channel_Cnt         = {CCW{1'h0}}           ; //通道计数器
  reg   [ACN-1:0]   Channel_List        = {{ACN-1{1'h0}},1'h1}  ; //通道列表，每Bit表示一个通道

  wire              Act_Cnl_Hit         ; //通道激活
  wire              Cnl_Search_En       ; //通道搜索允许

  localparam        S_ADDR_IDLE = 1'h0  ; //空闲状态
  localparam        S_ADDR_ACT  = 1'h1  ; //激活状态

  always @ (posedge Sys_Clk or negedge Sys_Rst_N)
  begin
    if (~Sys_Rst_N)   
    begin
      Sta_Cnl_Switch  <=  S_ADDR_IDLE ;
      Channel_List    <=  {{ACN-1{1'h0}},1'h1} ;
      Channel_Cnt     <=  {CCW{1'h0}} ;
    end
    else 
    begin
      case  (Sta_Cnl_Switch)
        //空闲状态
        S_ADDR_IDLE : 
        begin
          if (Act_Cnl_Hit)      Sta_Cnl_Switch  <=  S_ADDR_ACT  ;
          if (Cfg_Arb_Type & Act_Cnl_Hit)
          begin
            Channel_Cnt     <=  {CCW{1'h0}} ;
            Channel_List    <=  {{ACN-1{1'h0}},1'h1} ;
          end
          else if (Cnl_Search_En)
          begin   
            if (Channel_List[ACN-1])  
            begin
              Channel_Cnt   <=  {CCW{1'h0}} ;
              Channel_List  <=  {{ACN-1{1'h0}},1'h1} ;
            end
            else  
            begin
              Channel_Cnt   <=  Channel_Cnt + {{CCW-1{1'h0}},1'h1} ;
              Channel_List  <=  {Channel_List[ACN-2:0] ,Channel_List[ACN-1] } ;
            end    
          end
        end 
        //激活状态
        S_ADDR_ACT  : 
        begin
          if (M_A_End)              Sta_Cnl_Switch  <=  S_ADDR_IDLE ;
          if ((~Act_Cnl_Hit) & Cnl_Search_En)
          begin
            if (Channel_List[ACN-1])  
            begin
              Channel_Cnt   <=  {CCW{1'h0}} ;
              Channel_List  <=  {{ACN-1{1'h0}},1'h1} ;
            end
            else  
            begin
              Channel_Cnt   <=  Channel_Cnt + {{CCW-1{1'h0}},1'h1} ;
              Channel_List  <=  {Channel_List[ACN-2:0] ,Channel_List[ACN-1] } ;
            end
          end          
        end 
      endcase  
    end
  end

  /////////////////////////////////////////////////////////
  reg   [CCW-1:0]   Act_Cnl_Num  = {CCW{1'h0}} ; //当前激活的通道编号    

  always @ (posedge Sys_Clk or negedge Sys_Rst_N)
  begin
    if (~Sys_Rst_N)           Act_Cnl_Num <= {CCW{1'h0}}  ;
    else if (Act_Cnl_Hit & (Sta_Cnl_Switch == S_ADDR_IDLE))   
    begin
      Act_Cnl_Num  <= Channel_Cnt  ;
    end
  end  

  /////////////////////////////////////////////////////////      
  reg   [ACN-1:0]   Act_Cnl_List = {ACN{1'h0}} ; //当前激活的通道列表      

  always @ (posedge Sys_Clk or negedge Sys_Rst_N)
  begin
    if (~Sys_Rst_N)       Act_Cnl_List <= {ACN{1'h0}} ;
    else
    begin
      case  (Sta_Cnl_Switch)
        S_ADDR_IDLE : if (Act_Cnl_Hit)  Act_Cnl_List <= Channel_List ;
        S_ADDR_ACT  : if (M_A_End)      Act_Cnl_List <= {ACN{1'h0}}  ;
      endcase
    end
  end  

  /////////////////////////////////////////////////////////
  //精确控制通道搜寻
  
  assign  Cnl_Search_En = |(Effe_S_Val  & (~Act_Cnl_List) ) ;
  assign  Act_Cnl_Hit   = |(Effe_S_Val  & (~Act_Cnl_List)   & Channel_List  ) ;  //通道激活

  /////////////////////////////////////////////////////////
  assign    M_A_Valid = |(Act_Cnl_List  & S_A_Valid       ) ;
  assign    S_A_Ready =  (Act_Cnl_List  & {ACN{M_A_Ready}}) ;

  /////////////////////////////////////////////////////////
  wire              O_M_A_VALID     = M_A_Valid     ; //(O)[RdAddr]Read address valid.
  wire  [ACN-1:0]   O_S_A_READY     = S_A_Ready     ; //(O)[RdAddr]Read address ready.

  wire              O_Act_Cnl_End   = M_A_End       ; //(O)Active Enable
  wire  [CCW-1:0]   O_Act_Cnl_Num   = Act_Cnl_Num   ; //(O)State Bus Active Channel
  wire  [ACN-1:0]   O_Act_Cnl_List  = Act_Cnl_List  ; //(O)Active Channel List
  
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

endmodule

///////////////////////////////////////////////////////////








///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:
  根据前一级总线处理顺序处理控制信号

  Establishment : Richard Zhu
  Create date   : 2022-09-29
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Axi_Mux_Info
(
  Sys_Clk     , //(I)System Clock
  Sys_Rst_N   , //(I)System Reset
  I_Info_Val  , //(I)Info Input Valid 
  I_Cnl_End   , //(I)Channel End
  I_Info_In   , //(I)Info Input 
  O_Cnl_Act   , //(O)Channel Info Active
  O_Info_Out    //(O)Info Output 
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  //AXI通道个数设置
  parameter     AXI_CHANNEL_NUM     = 2 ; //Slave的通道个数

  localparam    CHANNEL_CNT_WIDTH   = $clog2( AXI_CHANNEL_NUM )           ; //通道计数的宽度
  localparam    INFO_FIFO_WIDTH     = AXI_CHANNEL_NUM + CHANNEL_CNT_WIDTH ; //信息FIFO的数据宽度

  //abbreviation
  //////////////
  localparam    ACN   = AXI_CHANNEL_NUM     ;
  localparam    CCW   = CHANNEL_CNT_WIDTH   ;
  localparam    IFW   = INFO_FIFO_WIDTH     ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  //System Signal
  input               Sys_Clk     ; //(I)System Clock
  input               Sys_Rst_N   ; //(I)System Reset
  input               I_Info_Val  ; //(I)Info Input Valid 
  input               I_Cnl_End   ; //(I)Channel End
  input   [IFW-1:0]   I_Info_In   ; //(I)Info Input 
  output              O_Cnl_Act   ; //(O)Channel Info Active
  output  [IFW-1:0]   O_Info_Out  ; //(O)Info Output 
  
  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//输入数据处理
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              Info_Val  = I_Info_Val  ; //(I)Info Input Valid 
  wire              Cnl_End   = I_Cnl_End   ; //(I)Active Channel Operate End

  wire  [CCW-1:0]   Next_Cnl_Num  = I_Info_In[IFW-1:ACN]; //总线激活通道编号
  wire  [ACN-1:0]   Next_Cnl_List = I_Info_In[ACN-1:  0]; //总线激活通道列表，对应激活通道的Bit为1

  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg     Sta_Cnl_Sw   = 1'h0 ;   //通道切换状态机
  
  localparam    S_WR_IDLE   = 1'h0  ;  //空闲状态
  localparam    S_WR_ACT    = 1'h1  ;  //激活状态

  always @ (posedge Sys_Clk or negedge Sys_Rst_N)
  begin
    if (~Sys_Rst_N)     Sta_Cnl_Sw <=  1'h0  ;
    else 
    begin
      case (Sta_Cnl_Sw)
        S_WR_IDLE : if (Info_Val)   Sta_Cnl_Sw <=  S_WR_ACT  ;
        S_WR_ACT  : if (Cnl_End)    Sta_Cnl_Sw <=  S_WR_IDLE ;
      endcase
    end
  end

  wire    Cnl_Act   = Sta_Cnl_Sw ^ S_WR_IDLE ;

  /////////////////////////////////////////////////////////
  reg   [CCW-1:0]   Act_Cnl_Num   = {CCW{1'h0}} ; //总线激活通道编号   
  reg   [ACN-1:0]   Act_Cnl_List  = {ACN{1'h0}} ; //总线激活通道列表，对应激活通道的Bit为1

  always @ (posedge Sys_Clk or negedge Sys_Rst_N)
  begin
    if (~Sys_Rst_N)       Act_Cnl_Num   <=  {CCW{1'h0}} ;
    else if (Info_Val & (Sta_Cnl_Sw==S_WR_IDLE))   
    begin
      Act_Cnl_Num   <=  Next_Cnl_Num  ;
    end
  end
  always @ (posedge Sys_Clk or negedge Sys_Rst_N)
  begin
    if (~Sys_Rst_N)       Act_Cnl_List  <=  {CCW{1'h0}}     ;
    else 
    begin
      case (Sta_Cnl_Sw)
        S_WR_IDLE : if (Info_Val)   Act_Cnl_List  <=  Next_Cnl_List ;
        S_WR_ACT  : if (Cnl_End)    Act_Cnl_List  <=  {CCW{1'h0}}   ;      
      endcase
    end      
  end

  /////////////////////////////////////////////////////////   
  wire  [IFW-1:0]   Info_Out  ; //(O)Info Output 

  assign  Info_Out[IFW-1:ACN] = Act_Cnl_Num  ;  //总线激活通道编号  
  assign  Info_Out[ACN-1:  0] = Act_Cnl_List ;  //总线激活通道列表，对应激活通道的Bit为1 

  /////////////////////////////////////////////////////////
  wire              O_Cnl_Act   = Cnl_Act   ; //(O)Channel Info Active
  wire  [IFW-1:0]   O_Info_Out  = Info_Out  ; //(O)Info Output 

  /////////////////////////////////////////////////////////  
//111111111111111111111111111111111111111111111111111111111

endmodule

///////////////////////////////////////////////////////////





//Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim//
//Debug_Debug_Debug_Debug_Debug_Debug_Debug_Debug_Debug////
//FUNCTION_FUNCTION_FUNCTION_FUNCTION_FUNCTION_FUNCTION////
//
///////////////////////////////////////////////////////////
  //
  ////////////////////////////////////////
  ////////////////////////////////////////

//Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim_Sim//
//Debug_Debug_Debug_Debug_Debug_Debug_Debug_Debug_Debug////
//FUNCTION_FUNCTION_FUNCTION_FUNCTION_FUNCTION_FUNCTION////

