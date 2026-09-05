
`timescale 1ns/100ps


//////////////////////   Ddr_Write   //////////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2021-03-01
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Write
(
  Clk_TxCmd       , //Clock Tx Command
  Clk_TxDqs       , //Clock Tx DQS
  Clk_TxDq        , //Clock Tx DQ
  Clk_Core        , //Clock Core
  Clk_Axi         , //Clock Axi
  Rst_TxCmd       , //Reset In Clock Tx Command
  Rst_TxDqs       , //Reset In Clock Tx DQS
  Rst_TxDq        , //Reset In Clock Tx DQ
  Rst_Core        , //Reset In Clock Core
  Rst_Axi         , //Reset In Clock Axi
  //Axi Interfac
  I_AW_ID         , //(I)[WrAddr]Write address ID.
  I_AW_ADDR       , //(I)[WrAddr]Write address.
  I_AW_LEN        , //(I)[WrAddr]Burst length.
  I_AW_SIZE       , //(I)[WrAddr]Burst size.
  I_AW_BURST      , //(I)[WrAddr]Burst type.
  I_AW_LOCK       , //(I)[WrAddr]Lock type.
  I_AW_VALID      , //(I)[WrAddr]Write address valid.
  O_AW_READY      , //(O)[WrAddr]Write address ready.

  I_W_ID          , //(I)[WrData]Write ID tag.
  I_W_DATA        , //(O)[WrData]Write data.
  I_W_STRB        , //(I)[WrData]Write strobes.
  I_W_LAST        , //(I)[WrData]Write last.
  I_W_VALID       , //(I)[WrData]Write valid.
  O_W_READY       , //(I)[WrData]Write ready.

  O_B_ID          , //(O)[WrResp]Response ID tag.
  O_B_VALID       , //(O)[WrResp]Write response valid.
  I_B_READY       , //(I)[WrResp]Response ready.
  //Test Interface 
  I_WrLevel_En    , //(I)Write Leveling Enable  
  I_Test_Mode     , //(I)[Clk_Axi ] Test Mode 
  I_T_AW_Wr_En    , //(I)[Clk Axi ] Test AWBus Write Enable
  I_T_AW_Wr_D     , //(I)[Clk Axi ] Test AWBus Write Data
  O_T_AW_Ready    , //(O)[Clk Core] Test AWBus Write Ready
  O_T_AW_Idle     , //(O)[Clk Axi ] Test AWBus Idle 
  I_T_W_Wr_En     , //(I)[Clk Axi ] Test WBus Write Enable
  I_T_W_Wr_D      , //(I)[Clk Axi ] Test WBus Write Data
  O_T_W_Ready     , //(O)[Clk Axi ] Test WBus Write Ready
  O_T_W_Idle      , //(O)[Clk Core] Test AWBus Idle 
  //Controller Interface
  Cfg_Wr_Latency  , //(I)Config Write Latency
  I_Phy_Cmd_Write , //(I)Command Write
  I_Phy_Cmd_Valid , //(I)Command Valid
  I_Phy_Command   , //(I)Phy Command
  O_W_Data_Empty  , //(O)Read Fifo Empty
  O_W_Buff_Last   , //(O)DDR Address Bus Buffer Last 
  
  I_Axi_Wr_Pause  , //(I)[Clk_Core] Axi Write Pause 
  I_Ddr_Wr_Pause  , //(I)[Clk_Core] DDR Write Pause 
  I_AW_Addr_RdEn  , //(I)[Clk_Core] AWBus Read Address Enable
  O_AW_Addr_Num   , //(O)[Clk_Core] AWBus Address Number     
  O_AW_Addr_Empty , //(O)[Clk_Core] AWBus Buffer Empty 
  O_AW_Addr_Last  , //(O)[Clk_Core] AWBus Buffer Last 
  O_AW_Ddr_Addr   , //(O)[Clk_Core] AWBus Address Output 
  O_AW_Burst_RdEn , //(O)[Clk_Core] AWBus Burst Read Enable    
  O_AW_Burst_Last , //(O)[Clk_Core] AWBus Burst Last
  O_AW_Burst_Done , //(O)[Clk_Core] AWBus Burst Done 
  O_AW_Next_Param , //(O)[Clk_Core] AWBus Next Parameter      
  O_AW_Curr_Param , //(O)[Clk_Core] AWBus Current Parameter
  O_AW_Err_Flag   , //(O)[Clk_Core] AWBus Error Flag
  //DDR Interface
  I_Ddr_Cs_In     , //(I)DDR CS Capture By Clk_TxDq
  O_Ddr_Odt       , //(O)DDR ODT
  O_Ddr_Dm_Hi     , //(O)DDR Data Mask Output (HI)
  O_Ddr_Dm_Lo     , //(O)DDR Data Mask Output (LO)
  O_Ddr_Dq_Hi     , //(O)DDR DQ Data Input (HI)
  O_Ddr_Dq_Lo     , //(O)DDR DQ Data Input (LO)
  O_Ddr_Dq_Oe     ,  //(O)DDR DQ Data Output Enable
  O_Ddr_Dqs_Hi    , //(O)DDR DQS output
  O_Ddr_Dqs_Lo    , //(O)DDR DQS output
  O_Ddr_Dqs_Oe      //(O)DDR DQS
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  parameter   AXI_ID_WIDTH        = 8   ;   //AXI4总线ID的宽度
  parameter   AXI_DATA_WIDTH      = 128 ;   //AXI4总线数据的宽度
  parameter   DDR_DATA_WIDTH      = 16  ;   //DDR总线数据的宽度

  parameter   WR_DATA_FIFO_DEPTH  = 512 ;   //写数据FIFO深度
  parameter   WR_BURST_QUEUE_NUM  = 16  ;   //写最大地址队列深度

  parameter   RD_DATA_FIFO_DEPTH  = 512 ;   //读数据FIFO深度
  parameter   RD_BURST_QUEUE_NUM  = 16  ;   //读最大地址队列深度

  parameter   SECTION_MIN_LEN     = 32  ;   //最小切片长度，单位是AXI的Busrt个数
                                            //存储容量小于该值，将不进行下一步操作

  /////////////
  localparam  DDR_BUS_DATA_WIDTH  = DDR_DATA_WIDTH * 2        ; //内部数据总线的宽度，为DDR数据总线的2倍
  localparam  DDR_BUS_BYTE_NUM    = DDR_BUS_DATA_WIDTH  / 8   ; //内部数据总线字节个数
  localparam  DDR_BUS_BYTE_SIZE   = $clog2(DDR_BUS_BYTE_NUM)  ; //内部数据尺寸，即为字节计数器宽度

  localparam  AXI_BYTE_NUMBER     = AXI_DATA_WIDTH  / 8       ; //AXI4数据总线字节个数
  localparam  AXI_BYTE_SIZE       = $clog2(AXI_BYTE_NUMBER)   ; //AXI4数据尺寸，即为字节计数器宽度

  localparam  DDR_BYTE_NUMBER     = DDR_DATA_WIDTH  / 8       ; //DDR数据总线字节个数
  localparam  DDR_BYTE_SIZE       = $clog2(DDR_BYTE_NUMBER)   ; //DDR数据尺寸，即为字节计数器宽度
   
  localparam  DDR_BURST_WIDTH     = DDR_DATA_WIDTH  * 8       ; //DDR每次Burst的数据宽度,Burst=8
  /////////////   DM、DQS宽度
  localparam  AXI_DM_WIDTH        = AXI_BYTE_NUMBER           ; //AXI侧掩码宽度
  localparam  DDR_DM_WIDTH        = DDR_BYTE_NUMBER           ; //DDR侧掩码宽度
  localparam  DDR_BUS_DM_WIDTH    = DDR_BUS_BYTE_NUM          ; //DDR内部掩码宽度
    
  /////////////   内部存储有关    
  localparam  BUFF_FIFO_DATA_WIDTH_RITIO  = AXI_DATA_WIDTH  / DDR_BUS_DATA_WIDTH      ; //Buffer/FIFO的数据宽度比
  localparam  BUFF_FIFO_WIDTH_RITIO_SIZE  = $clog2(BUFF_FIFO_DATA_WIDTH_RITIO)        ; //Buffer/FIFO的数据宽度比的计数器宽度

  localparam  WR_DATA_BUFF_WIDTH        = AXI_DATA_WIDTH      + AXI_DM_WIDTH      + 1 ; //写缓存的宽度；
  localparam  WR_DATA_FIFO_WIDTH        = DDR_BUS_DATA_WIDTH  + DDR_BUS_DM_WIDTH  + 1 ; //写FIFO的宽度
  localparam  WR_DATA_FIFO_ADDR_WIDTH   = $clog2(WR_DATA_FIFO_DEPTH)                       ; //写FIFO地址宽度
  localparam  WR_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO                  ; //写缓存个数
  localparam  WR_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                  ; //写缓存个数计数器宽度

  localparam  RD_DATA_BUFF_WIDTH        = DDR_BUS_DATA_WIDTH                          ; //读缓存的宽度
  localparam  RD_DATA_FIFO_WIDTH        = DDR_BUS_DATA_WIDTH  + 1                     ; //读FIFO的宽度
  localparam  RD_DATA_FIFO_ADDR_WIDTH   = $clog2(RD_DATA_FIFO_DEPTH)                       ; //读FIFO地址宽度  
  localparam  RD_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO * 2              ; //读缓存个数，读缓存采用乒乓结构，要多用一倍的资源
  localparam  RD_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                  ; //读缓存个数计数器宽度

  localparam  ADDR_BUS_BUFF_WIDTH       = AXI_ID_WIDTH + 32 + 8 + 3                   ; //地址总线缓存数据宽度；包括ID/ADDR/LEN/SIZE
  
  localparam  WR_ADDR_QUEUE_NUM         = WR_DATA_BUFF_NUMBER * 2                     ; //写总线地址最大缓存个数
  localparam  RD_ADDR_QUEUE_NUM         = RD_DATA_BUFF_NUMBER * 2                     ; //读总线地址最大缓存个数

  /////////////   缩写               
  localparam  AIW   = AXI_ID_WIDTH              ; //AXI总线ID的宽度  
  localparam  ADW   = AXI_DATA_WIDTH            ; //AXI总线数据的宽度
  localparam  ADS   = AXI_BYTE_SIZE             ; //AXI数据尺寸，即为字节计数器宽度
  localparam  AMW   = AXI_DM_WIDTH              ; //AXI侧掩码宽度
  localparam  ABN   = AXI_BYTE_NUMBER           ; //AXI侧字节个数

  localparam  DDW   = DDR_DATA_WIDTH            ; //DDR总线数据的宽度
  localparam  DDS   = DDR_BYTE_SIZE             ; //DDR数据尺寸，即为字节计数器宽度
  localparam  DMW   = DDR_DM_WIDTH              ; //DDR侧掩码宽度
  localparam  DBN   = DDR_BYTE_NUMBER           ; //DDR侧字节个数

  localparam  BDW   = DDR_BUS_DATA_WIDTH        ; //内部数据总线的宽度，为DDR数据总线的2倍
  localparam  BDS   = DDR_BUS_BYTE_SIZE         ; //内部数据尺寸，即为字节计数器宽度
  localparam  BMW   = DDR_BUS_DM_WIDTH          ; //DDR内部掩码宽度
  localparam  BBN   = DDR_BUS_BYTE_NUM          ; //DDR内字节个数

  localparam  DBW   = DDR_BURST_WIDTH           ; //DDR每次Burst的数据宽度

  localparam  WBW   = WR_DATA_BUFF_WIDTH        ; //写缓存的宽度
  localparam  WFW   = WR_DATA_FIFO_WIDTH        ; //写FIFO的宽度
  localparam  WFS   = WR_DATA_FIFO_ADDR_WIDTH   ; //写FIFO地址宽度
  localparam  WBN   = WR_DATA_BUFF_NUMBER       ; //写缓存个数
  localparam  WBS   = WR_DATA_BUFF_NUMBER_SIZE  ; //写缓存个数计数器宽度

  localparam  RBW   = RD_DATA_BUFF_WIDTH        ; //读缓存的宽度
  localparam  RFW   = RD_DATA_FIFO_WIDTH        ; //读FIFO的宽度
  localparam  RFS   = RD_DATA_FIFO_ADDR_WIDTH   ; //读FIFO地址宽度  
  localparam  RBN   = RD_DATA_BUFF_NUMBER       ; //读缓存个数，读缓存采用乒乓结构，要多用一倍的资源
  localparam  RBS   = RD_DATA_BUFF_NUMBER_SIZE  ; //读缓存个数计数器宽度

  localparam  ABW   = ADDR_BUS_BUFF_WIDTH       ; //地址总线缓存数据宽度；包括ID/ADDR/LEN/SIZE  
  /////////////////////////////////////////////////////////

  // Port Define
  /////////////////////////////////////////////////////////
  input                     Clk_TxCmd       ; //Clock Tx Command
  input                     Clk_TxDqs       ; //Clock Tx DQS
  input                     Clk_TxDq        ; //Clock Tx DQ
  input                     Clk_Core        ; //Clock Core
  input                     Clk_Axi         ; //Clock Axi
  input                     Rst_TxCmd       ; //Reset In Clock Tx Command
  input                     Rst_TxDqs       ; //Reset In Clock Tx DQS
  input                     Rst_TxDq        ; //Reset In Clock Tx DQ
  input                     Rst_Core        ; //Reset In Clock Core
  input                     Rst_Axi         ; //Reset In Clock Axi
  //Axi Interfac
  input         [AIW-1:0]   I_AW_ID         ; //(I)[WrAddr]Write address ID.
  input         [   31:0]   I_AW_ADDR       ; //(I)[WrAddr]Write address.
  input         [    7:0]   I_AW_LEN        ; //(I)[WrAddr]Burst length.
  input         [    2:0]   I_AW_SIZE       ; //(I)[WrAddr]Burst size.
  input         [    1:0]   I_AW_BURST      ; //(I)[WrAddr]Burst type.
  input         [    1:0]   I_AW_LOCK       ; //(I)[WrAddr]Lock type.
  input                     I_AW_VALID      ; //(I)[WrAddr]Write address valid.
  output  wire              O_AW_READY      ; //(O)[WrAddr]Write address ready.
  input         [AIW-1:0]   I_W_ID          ; //(I)[WrData]Write ID tag.
  input         [AMW-1:0]   I_W_STRB        ; //(I)[WrData]Write strobes.
  input                     I_W_LAST        ; //(I)[WrData]Write last.
  input                     I_W_VALID       ; //(I)[WrData]Write valid.
  input         [ADW-1:0]   I_W_DATA        ; //(O)[WrData]Write data.
  output  wire              O_W_READY       ; //(I)[WrData]Write ready.
  output  wire  [AIW-1:0]   O_B_ID          ; //(O)[WrResp]Response ID tag.
  output  wire              O_B_VALID       ; //(O)[WrResp]Write response valid.
  input                     I_B_READY       ; //(I)[WrResp]Response ready.
  //Test Interface 
  input   wire              I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  input   wire              I_T_AW_Wr_En    ; //(I)[Clk Axi ] 测试AWBUS写允许
  input   wire  [ABW-1:0]   I_T_AW_Wr_D     ; //(I)[Clk Axi ] 测试AWBUS写数据
  output  wire              O_T_AW_Ready    ; //(O)[Clk Axi ] 测试AWBUS准备好，可以接收指令
  output  wire              O_T_AW_Idle     ; //(O)[Clk Core] 测试AWBUS空闲，表示完成所有指令
  input   wire              I_T_W_Wr_En     ; //(I)[Clk Axi ] 测试WBUS写允许
  input   wire  [WBW-1:0]   I_T_W_Wr_D      ; //(I)[Clk Axi ] 测试WBUS写数据
  output  wire              O_T_W_Ready     ; //(O)[Clk Axi ] 测试WBUS准备好，可以接收指令
  output  wire              O_T_W_Idle      ; //(O)[Clk Core] 测试WBUS空闲，表示完成所有指令
  //Controller Interface
  input   wire  [    2:0]   Cfg_Wr_Latency  ; //(I)[Clk_Core] 配置写指令到发送数据的潜伏期
  input   wire              I_Phy_Cmd_Write ; //(I)[Clk_Cmd ] 发出的写命令
  input   wire              I_Phy_Cmd_Valid ; //(I)[Clk_Cmd ] 命令有效，CS为低
  input   wire              I_WrLevel_En    ; //(I)[Clk_Core] 写均衡（Write Leveling）允许
  input   wire  [    4:0]   I_Phy_Command   ; //(I)[Clk_Cmd ] 从接口命令（RST/CS/RAS/CAS/WE）
  output  wire              O_W_Data_Empty  ; //(O)[Clk_TxDq] 写数据缓存空
  output  wire              O_W_Buff_Last   ; //(O)[Clk_TxDq] 写数据总线缓存数据不超过一个
  
  input   wire              I_Axi_Wr_Pause  ; //(I)[Clk_Core] Axi写暂停
  input   wire              I_Ddr_Wr_Pause  ; //(I)[Clk_Core] DDR写暂停
  input   wire              I_AW_Addr_RdEn  ; //(I)[Clk_Core] 写地址总线取地址允许
  output  wire  [   15:0]   O_AW_Addr_Num   ; //(O)[Clk_Core] 未操作的写地址个数
  output  wire              O_AW_Addr_Empty ; //(O)[Clk_Core] 写地址总线无操作地址 
  output  wire              O_AW_Addr_Last  ; //(O)[Clk_Core] 最后一个地址
  output  wire  [   31:0]   O_AW_Ddr_Addr   ; //(O)[Clk_Core] DDR的写地址      
  output  wire              O_AW_Burst_RdEn ; //(O)[Clk_Core] 读参数允许   
  output  wire              O_AW_Burst_Last ; //(O)[Clk_Core] 当前Burst最后一个操作
  output  wire              O_AW_Burst_Done ; //(O)[Clk_Core] 指示刚刚完成一个写Burst
  output  wire  [ABW-1:0]   O_AW_Next_Param ; //(O)[Clk_Core] 写地址总线的下一个参数
  output  wire  [ABW  :0]   O_AW_Curr_Param ; //(O)[Clk_Core] 写地址总线的当前参数
  output  wire  [    3:0]   O_AW_Err_Flag   ; //(O)[Clk_Core] 写地址总线的错误标志
                                              //[0] : 地址满写      [1] : 地址空读     
                                              //[2] : 参数缓存满写  [3] : 参数缓存空读 

  //DDR Interface
  input   wire  [    1:0]   I_Ddr_Cs_In     ; //(I)[Clk_TxDq] 通过Clk_TxDq采集Cs的结果
  output  wire              O_Ddr_Odt       ; //(O)DDR ODT
  output  wire  [DMW-1:0]   O_Ddr_Dm_Hi     ; //(O)DDR Data Mask Output (HI)
  output  wire  [DMW-1:0]   O_Ddr_Dm_Lo     ; //(O)DDR Data Mask Output (LO)
  output  wire  [DDW-1:0]   O_Ddr_Dq_Hi     ; //(O)DDR DQ Data Input (HI)
  output  wire  [DDW-1:0]   O_Ddr_Dq_Lo     ; //(O)DDR DQ Data Input (LO)
  output  wire  [DDW-1:0]   O_Ddr_Dq_Oe     ;  //(O)DDR DQ Data Output Enable
  output  wire  [DMW-1:0]   O_Ddr_Dqs_Hi    ; //(O)DDR DQS output
  output  wire  [DMW-1:0]   O_Ddr_Dqs_Lo    ; //(O)DDR DQS output
  output  wire  [DMW-1:0]   O_Ddr_Dqs_Oe    ; //(O)DDR DQS
  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [AIW-1:0]   Axi_AW_ID         = I_AW_ID         ; //(I)[WrAddr]Write address ID.
  wire  [   31:0]   Axi_AW_ADDR       = I_AW_ADDR       ; //(I)[WrAddr]Write address.
  wire  [    7:0]   Axi_AW_LEN        = I_AW_LEN        ; //(I)[WrAddr]Burst length.
  wire  [    2:0]   Axi_AW_SIZE       = I_AW_SIZE       ; //(I)[WrAddr]Burst size.
  wire  [    1:0]   Axi_AW_BURST      = I_AW_BURST      ; //(I)[WrAddr]Burst type.
  wire  [    1:0]   Axi_AW_LOCK       = I_AW_LOCK       ; //(I)[WrAddr]Lock type.
  wire              Axi_AW_VALID      = I_AW_VALID      ; //(I)[WrAddr]Write address valid.
  wire  [AIW-1:0]   Axi_W_ID          = I_W_ID          ; //(I)[WrData]Write ID tag.
  wire  [AMW-1:0]   Axi_W_STRB        = I_W_STRB        ; //(I)[WrData]Write strobes.
  wire              Axi_W_LAST        = I_W_LAST        ; //(I)[WrData]Write last.
  wire              Axi_W_VALID       = I_W_VALID       ; //(I)[WrData]Write valid.
  wire  [ADW-1:0]   Axi_W_DATA        = I_W_DATA        ; //(O)[WrData]Write data.
  wire              Axi_B_READY       = I_B_READY       ; //(I)[WrResp]Response ready.
  
  wire              Test_Mode         = I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效

  //Controller Interface  
  wire  [    3:0]   Conf_Wr_Latcy     = Cfg_Wr_Latency  ; //(I)Config Write Latency
  wire  [    1:0]   Ddr_Cs_In         = I_Ddr_Cs_In     ; //(I)DDR CS Capture By Clk_TxDq
  wire              Phy_Cmd_Write     = I_Phy_Cmd_Write ; //(I)Command Write
  wire              Phy_Cmd_Valid     = I_Phy_Cmd_Valid ; //(I)Command Valid
  wire              Wr_Level_En       = I_WrLevel_En    ; //(I)[Clk_Core] 写均衡（Write Leveling）允许
  wire  [    4:0]   Phy_Command       = I_Phy_Command   ; //(I)[Clk_Cmd ] 从接口命令（RST/CS/RAS/CAS/WE）
  wire              AWBus_Addr_RdEn   = I_AW_Addr_RdEn  ; //(I)Read Address Enable

  wire              Axi_Wr_Pause      = I_Axi_Wr_Pause  ; //(I)[Clk_Core] Axi写暂停
  wire              Ddr_Wr_Pause      = I_Ddr_Wr_Pause  ; //(I)[Clk_Core] DDR写暂停
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//////////////////////   Ddr_Write   //////////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire                Axi_AWBus_Pause   ; //(I)[Clk_Axi ] Axi 地址总线操作暂停 
  wire                Axi_AWBus_WrEn    ; //(O)[Clk_Axi ] AXI 地址总线写允许(AXI时钟域)

  wire                AWBus_Addr_Empty  ; //(O)[Clk_Core] ABus地址空      

  defparam  U1_Ddr_AWBus_Control.AXI_ID_WIDTH      = AXI_ID_WIDTH       ; //AXI4总线ID的宽度
  defparam  U1_Ddr_AWBus_Control.AXI_DATA_WIDTH    = AXI_DATA_WIDTH     ; //AXI4总线数据的宽度
  defparam  U1_Ddr_AWBus_Control.DDR_DATA_WIDTH    = DDR_DATA_WIDTH     ; //DDR总线数据的宽度
  defparam  U1_Ddr_AWBus_Control.ADDR_QUEUE_NUM    = WR_ADDR_QUEUE_NUM  ; //最大地址队列个数
  defparam  U1_Ddr_AWBus_Control.BURST_QUEUE_NUM   = WR_BURST_QUEUE_NUM ; //最大地址队列深度

  Ddr_Addr_Bus_Control  U1_Ddr_AWBus_Control
  (
    //System Signal
    .Clk_Core         ( Clk_Core          ) , //System Clock
    .Clk_Axi          ( Clk_Axi           ) , //System Clock
    .Rst_Core         ( Rst_Core          ) , //(I)Sync Reset
    .Rst_Axi          ( Rst_Axi           ) , //(I)Sync Reset
    //Axi Signal          
    .I_A_ID           ( I_AW_ID           ) , //(I)[Addr]Write address ID.
    .I_A_ADDR         ( I_AW_ADDR         ) , //(I)[Addr]Write address.
    .I_A_LEN          ( I_AW_LEN          ) , //(I)[Addr]Burst length.
    .I_A_SIZE         ( I_AW_SIZE         ) , //(I)[Addr]Burst size.
    .I_A_BURST        ( I_AW_BURST        ) , //(I)[Addr]Burst type.
    .I_A_LOCK         ( I_AW_LOCK         ) , //(I)[Addr]Lock type.
    .I_A_VALID        ( I_AW_VALID        ) , //(I)[Addr]Write address valid.
    .O_A_READY        ( O_AW_READY        ) , //(O)[Addr]Write address ready.
    //Test Interface 
    .I_Test_Mode      ( I_Test_Mode       ) , //(I)[Clk_Axi ] Test Mode 
    .I_T_A_Wr_En      ( I_T_AW_Wr_En      ) , //(I)[Clk Axi ] Test ABus Write Enable
    .I_T_A_Wr_D       ( I_T_AW_Wr_D       ) , //(I)[Clk Axi ] Test ABus Write Data
    .O_T_A_Ready      ( O_T_AW_Ready      ) , //(O)[Clk Axi ] Test ABus Write Buffer Full
    //DDR Controller Siganl    
    .I_Axi_Op_Pause   ( Axi_AWBus_Pause   ) , //(I)[Clk_Axi ] DDR Operate Pause 
    .O_Axi_A_WrEn     ( Axi_AWBus_WrEn    ) , //(O)[Clk_Axi ] Axi ABus Write Enable
    .I_A_Addr_RdEn    ( I_AW_Addr_RdEn    ) , //(I)[Clk_Core] AWBus Read Address Enable
    .O_A_Addr_Num     ( O_AW_Addr_Num     ) , //(O)[Clk_Core] AWBus Address Number     
    .O_A_Addr_Empty   ( AWBus_Addr_Empty  ) , //(O)[Clk_Core] AWBus Buffer Empty 
    .O_A_Addr_Last    ( O_AW_Addr_Last    ) , //(O)[Clk_Core] AWBus Buffer Last 
    .O_A_Ddr_Addr     ( O_AW_Ddr_Addr     ) , //(O)[Clk_Core] AWBus Address Output 
    .O_A_Burst_RdEn   ( O_AW_Burst_RdEn   ) , //(O)[Clk_Core] AWBus Burst Read Enable    
    .O_A_Burst_Last   ( O_AW_Burst_Last   ) , //(O)[Clk_Core] AWBus Burst Last
    .O_A_Next_Param   ( O_AW_Next_Param   ) , //(O)[Clk_Core] AWBus Next Parameter      
    .O_A_Curr_Param   ( O_AW_Curr_Param   ) , //(O)[Clk_Core] AWBus Current Parameter
    .O_A_Err_Flag     ( O_AW_Err_Flag     )   //(O)[Clk_Core] AWBus Error Flag
  ) ;
  
  /////////////////////////////////////////////////////////
  wire   AWBus_Bst_Last   = O_AW_Burst_Last ;
  wire   AWBus_Addr_Last  = O_AW_Addr_Last  ;

  /////////////////////////////////////////////////////////
  wire    Ddr_AWBus_Pause ;
  reg     AW_Burst_Done   = 1'h0  ;

  always  @(posedge  Clk_Core)  
  begin
    if (Rst_Core)                 AW_Burst_Done <=  1'h0 ;
    else if (~Ddr_AWBus_Pause)    AW_Burst_Done <=  1'h0 ;
    else if (AWBus_Bst_Last)      AW_Burst_Done <=  1'h1 ;
  end
  
  wire  Write_Pause = AW_Burst_Done ;

  /////////////////////////////////////////////////////////
  reg   AW_Addr_Empty = 1'h0  ;
    
  always  @( * )  AW_Addr_Empty <=  AWBus_Addr_Empty  | Write_Pause ;

  /////////////////////////////////////////////////////////
  assign    O_AW_Addr_Empty   = AW_Addr_Empty     ; //(O)[Clk_Core] 写地址总线无操作地址 
  assign    O_AW_Burst_Done   = AW_Burst_Done     ; //(O)[Clk_Core] 指示刚刚完成一个写Burst
  assign    O_T_AW_Idle       = AWBus_Addr_Empty  ; //(O)[Clk Core] 测试AWBUS空闲，表示完成所有指令
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
//////////////////////   Ddr_Write   //////////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  /////////////////////////////////////////////////////////  
  //AXI BBus Signal
  wire              Ddr_BBus_Busy     ; //(O)DDR侧B总线忙，表示AXI的B接口拥塞，需要暂停DDR写操作
  wire              Axi_BBus_Busy     ; //(O)AXI侧B总线忙，表示IDFiFo满，需要暂停接收AXI的AW接口

  defparam   U2_BBus_Process.AXI_ID_WIDTH       =  AXI_ID_WIDTH    ;
  defparam   U2_BBus_Process.WR_BURST_QUEUE_NUM =  WR_BURST_QUEUE_NUM   ;

  BBus_Process  U2_BBus_Process
  (
    //System Signal
    .Clk_Core         ( Clk_Core        ) , //System Clock
    .Clk_Axi          ( Clk_Axi         ) , //System Clock
    .Rst_Core         ( Rst_Core        ) , //(I)Sync Reset
    .Rst_Axi          ( Rst_Axi         ) , //(I)Sync Reset
    //AXI BBus Signal
    .I_AW_ID          ( I_AW_ID         ) , //(I)[WrAddr]Write address ID.
    .O_B_ID           ( O_B_ID          ) , //(O)[WrResp]Response ID tag.
    .O_B_VALID        ( O_B_VALID       ) , //(O)[WrResp]Write response valid.
    .I_B_READY        ( I_B_READY       ) , //(I)[WrResp]Response ready.
    //Ddr Siganl
    .I_Test_Mode      ( I_Test_Mode     ) , //(I)[Clk_Axi ] Test Mode 
    .I_AW_Bst_Last    ( AWBus_Bst_Last  ) , //(I)DDR AWBus Last Operate
    .I_Axi_AW_WrEn    ( Axi_AWBus_WrEn  ) , //(I)Axi AWBus Write Enable
    .O_Ddr_B_Busy     ( Ddr_BBus_Busy   ) , //(O)DDR BBus Busy
    .O_Axi_B_Busy     ( Axi_BBus_Busy   )   //(O)AXI BBus Busy
  );

  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222
//////////////////////   Ddr_Write   //////////////////////
//333333333333333333333333333333333333333333333333333333333
//
//********************************************************/
  /////////////////////////////////////////////////////////  
  //把取地址信号（ AWBus_Addr_RdEn ）转到 Clk_TxDq时钟域
  reg   [1:0]   Addr_RdEn_Reg   = 2'h0  ;

  always  @(posedge  Clk_TxDq )  Addr_RdEn_Reg  <=  {Addr_RdEn_Reg[0] , AWBus_Addr_RdEn} ;  
  
  wire  TxDq_Addr_RdEn    = (Addr_RdEn_Reg  ==  2'h1) ;

  /////////////////////////////////////////////////////////
  //记录取地址和读数据的数量差；监控取地址到读出数据的流程是否正常
  wire          Ddr_WBus_RdEn ;         //(I)DDR Write Bus Read Enable
  reg   [3:0]   WBus_A2D_Cnt  = 4'h0  ; //WBUS地址到数据的操作计数器                    
  
  always  @(posedge  Clk_TxDq ) 
  begin 
    if (Rst_TxDq)             WBus_A2D_Cnt  <=  4'h0  ;
    else if (TxDq_Addr_RdEn ^ Ddr_WBus_RdEn)   
    begin
      if (TxDq_Addr_RdEn)     WBus_A2D_Cnt  <=  WBus_A2D_Cnt  - 4'h1  ;
      else if (Ddr_WBus_RdEn) WBus_A2D_Cnt  <=  WBus_A2D_Cnt  + {3'h0,WBus_A2D_Cnt[3]}  ;
    end
  end

  wire  [3:0]   WBus_A2D_Num    = (4'h0 - WBus_A2D_Cnt) ; //WBus地址到数据未完成个数
  wire          WBus_A2D_Done   = ( ~ WBus_A2D_Cnt[3] ) ; //WBus地址到数据的操作全部完成

  /////////////////////////////////////////////////////////  
  wire      Cmd_Write_In  = (~WBus_A2D_Done)  & Phy_Cmd_Write ;

  /////////////////////////////////////////////////////////  
  wire   [3:0]  Calc_WrD_Dly  = Conf_Wr_Latcy - 4'h5  ;
  wire   [2:0]  Conf_WrD_Dly  = Calc_WrD_Dly[2:0]     ; //(I)Config Write Data Delay
  wire          WD_Fifo_Rd_En ; //(O)Write Fifo Read Enable
  
  Ddr_Wr_Data_Ctrl  U2_Ddr_Wr_Data_Ctrl
  (  
    .Clk_TxDq         ( Clk_TxDq        ) , //(I)Tx Dq Clock
    .Rst_TxDq         ( Rst_TxDq        ) , //(I)Tx DQ Reset
    .Cfg_WrD_Dly      ( Conf_WrD_Dly    ) , //(I)Config Write Data Delay
    .I_Ddr_Cs_In      ( I_Ddr_Cs_In     ) , //(I)DDR CS Capture By Clk_TxDq
    .I_Phy_Cmd_Write  ( Cmd_Write_In    ) , //(I)Command Write 
    .I_Phy_Cmd_Valid  ( I_Phy_Cmd_Valid ) , //(I)Command Valid 
    .O_Fifo_Rd_En     ( WD_Fifo_Rd_En   )   //(O)Write Fifo Read Enable
  );

  /////////////////////////////////////////////////////////
  reg   DBG_WBus_A2D_Err  = 1'h0  ;
  
  always  @(posedge  Clk_TxDq ) 
  begin 
    if (Rst_TxDq)         DBG_WBus_A2D_Err  <=  4'h0  ;
    else if (TxDq_Addr_RdEn ^ Ddr_WBus_RdEn)
    begin
      if (TxDq_Addr_RdEn)     DBG_WBus_A2D_Err  <=  ( WBus_A2D_Cnt  == 4'h8 ) ;
      else if (Ddr_WBus_RdEn) DBG_WBus_A2D_Err  <=  ( ~ WBus_A2D_Cnt[3]     ) ;
    end
  end
  /////////////////////////////////////////////////////////  
//333333333333333333333333333333333333333333333333333333333
//////////////////////   Ddr_Write   //////////////////////
//444444444444444444444444444444444444444444444444444444444
//
//********************************************************/
  /////////////////////////////////////////////////////////    
  
  /////////////////////////////////////////////////////////    
  assign              Ddr_WBus_RdEn   = WD_Fifo_Rd_En ; //(I)DDR Write Bus Read Enable
  
  wire                Ddr_WBus_Empty  ; //(O)DDR Write Bus Read Empty
  wire                Ddr_WBus_DVal   ; //(O)DDR Write Bus Data Valid 
  wire  [BDW-1:0]     Ddr_WBus_Data   ; //(O)DDR Write Bus Data
  wire  [BMW-1:0]     Ddr_WBus_Strb   ; //(O)DDR Write Bus Data Strobes(Byte valid)
  wire                Ddr_WBus_Last   ; //(O)DDR Write Bus Data Last

  wire                Axi_WBus_Pause  ; //(I)[Clk_Axi ] Axi 写总线操作暂停   

  defparam  U3_Ddr_WrData_Fifo.AXI_ID_WIDTH       = AXI_ID_WIDTH        ; //AXI4总线ID的宽度
  defparam  U3_Ddr_WrData_Fifo.AXI_DATA_WIDTH     = AXI_DATA_WIDTH      ; //AXI4总线数据的宽度
  defparam  U3_Ddr_WrData_Fifo.DDR_DATA_WIDTH     = DDR_DATA_WIDTH      ; //AXI4总线数据的宽度
  defparam  U3_Ddr_WrData_Fifo.WR_DATA_FIFO_DEPTH = WR_DATA_FIFO_DEPTH  ; //写数据FIFO深度

  Ddr_WrData_Fifo   U3_Ddr_WrData_Fifo
  (
    .Clk_TxDq         ( Clk_TxDq        ) , //Clock Tx DQ
    .Clk_Axi          ( Clk_Axi         ) , //Clock Axi
    .Rst_TxDq         ( Rst_TxDq        ) , //Reset In Clock Tx DQ
    .Rst_Axi          ( Rst_Axi         ) , //Reset In Clock Axi
    //AXI WBus Signal 
    .I_W_ID           ( I_W_ID          ) , //(I)[WrData]Write ID tag.
    .I_W_DATA         ( I_W_DATA        ) , //(O)[WrData]Write data.
    .I_W_STRB         ( I_W_STRB        ) , //(I)[WrData]Write strobes.
    .I_W_LAST         ( I_W_LAST        ) , //(I)[WrData]Write last.
    .I_W_VALID        ( I_W_VALID       ) , //(I)[WrData]Write valid.
    .O_W_READY        ( O_W_READY       ) , //(I)[WrData]Write ready.
    //Test Interface
    .I_WrLevel_En     ( Wr_Level_En     ) , //(I)[Clk_Core] Write Leveling Enable  
    .I_Test_Mode      ( I_Test_Mode     ) , //(I)[Clk_Axi ] Test Mode 
    .I_T_W_Wr_En      ( I_T_W_Wr_En     ) , //(I)[Clk Axi ] Test WBus Write Enable
    .I_T_W_Wr_D       ( I_T_W_Wr_D      ) , //(I)[Clk Axi ] Test WBus Write Data
    .O_T_W_Ready      ( O_T_W_Ready     ) , //(O)[Clk Axi ] Test WBus Write Buffer Full
    //DDR Signal  
    .I_Axi_W_Pause    ( Axi_WBus_Pause  ) , //(O)[Clk_Axi ] Axi WBus Write Pause
    .O_Axi_W_WrEn     ( Axi_WBus_WrEn   ) , //(O)[Clk_Axi ] Axi WBus Write Enable    
    .I_Ddr_W_RdEn     ( Ddr_WBus_RdEn   ) , //(I)DDR Write Bus Read Enable
    .O_Ddr_W_Empty    ( Ddr_WBus_Empty  ) , //(O)DDR Write Bus Read Empty
    .O_Ddr_W_DVal     ( Ddr_WBus_DVal   ) , //(O)DDR Write Bus Data Valid 
    .O_Ddr_W_Data     ( Ddr_WBus_Data   ) , //(O)DDR Write Bus Data
    .O_Ddr_W_Strb     ( Ddr_WBus_Strb   ) , //(O)DDR Write Bus Data Strobes(Byte valid)
    .O_Ddr_W_Last     ( Ddr_WBus_Last   ) ,  //(O)DDR Write Bus Data Last
    //DDR Interface
    .O_Ddr_Dm_Hi      ( O_Ddr_Dm_Hi     ) , //(O)DDR Data Mask Output (HI)
    .O_Ddr_Dm_Lo      ( O_Ddr_Dm_Lo     ) , //(O)DDR Data Mask Output (LO)
    .O_Ddr_Dq_Hi      ( O_Ddr_Dq_Hi     ) , //(O)DDR DQ Data Input (HI)
    .O_Ddr_Dq_Lo      ( O_Ddr_Dq_Lo     ) , //(O)DDR DQ Data Input (LO)
    .O_Ddr_Dq_Oe      ( O_Ddr_Dq_Oe     )    //(O)DDR DQ Data Output Enable
  );

  assign  Axi_AWBus_Pause = Axi_Wr_Pause  | Axi_BBus_Busy ;
  assign  Ddr_AWBus_Pause = Ddr_Wr_Pause  | Ddr_BBus_Busy ;

  assign  Axi_WBus_Pause  = Axi_Wr_Pause  ;

  /////////////////////////////////////////////////////////  
  //在取地址时同时计算写数据缓存的数据个数
  wire          DW_Wr_En      = Axi_WBus_WrEn  ; //(I)[Clk_Axi  ] AXI Data Write Enable

  wire  [9:0]   DW_Data_Num   ; //(O)[Clk_RxCmd] Data Number In Fifo    
  wire          DW_RdWr_Err   ; //(O)[Clk_RxCmd] Fifo Read Write Error  

  Wr_Data_Num   U3_Wr_Data_Num  
  (
    .Clk_Core     ( Clk_Core        ) , //(I)[Clk_Core ] Clock Core           
    .Clk_Axi      ( Clk_Axi         ) , //(I)[Clk_Axi  ] AXi Data Write Clock 
    .Clk_TxCmd    ( Clk_TxCmd       ) , //(I)[Clk_RxCmd] Clock Tx Command     
    .Rst_TxCmd    ( Rst_TxCmd       ) , //(I)[Clk_RxCmd] Reset Tx Command     

    .I_DW_Wr_En   ( DW_Wr_En        ) , //(I)[Clk_Axi  ] AXI Data Write Enable  
    .I_AW_Rd_En   ( I_AW_Addr_RdEn  ) , //(I)[Clk_Core ] AXI Address Read Enable
    .O_Data_Num   ( DW_Data_Num     ) , //(O)[Clk_RxCmd] Data Number In Fifo    
    .O_RdWr_Err   ( DW_RdWr_Err     ) , //(O)[Clk_RxCmd] Fifo Read Write Error  
    .O_DW_Empty   ( O_W_Data_Empty  )   //(O)[Clk_Core ] Data Write Fifo Empty  
  );

  /////////////////////////////////////////////////////////
  reg   WBus_Buff_Last  = 1'h0  ;

  always @(posedge Clk_TxCmd) WBus_Buff_Last  <= ~|DW_Data_Num[9:1] ;
  
  /////////////////////////////////////////////////////////
  assign    O_W_Buff_Last   = WBus_Buff_Last  ; //(O)DDR 写数据总线缓存数据不超过一个
  assign    O_T_W_Idle      = Ddr_WBus_Empty  ; //(O)[Clk Core] 测试WBUS空闲，表示完成所有指令
  /////////////////////////////////////////////////////////  
//444444444444444444444444444444444444444444444444444444444
//////////////////////   Ddr_Write   //////////////////////
//555555555555555555555555555555555555555555555555555555555
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire   [3:0]    Calc_Dqs_Dly    = Conf_Wr_Latcy - 4'h5  ;
  wire   [2:0]    Conf_Dqs_Dly    = Calc_Dqs_Dly[2:0]     ; //(I)Config Tx Dqs Delay

  /////////////////////////////////////////////////////////
  wire            Ddr_Dqs_Last    ; //(O)DDR Dqs Last
  wire    [1:0]   Ddr_Dqs_Out     ; //(O)DDR DQS Output 
  wire            Ddr_Dqs_OE      ; //(O)DDR DQS Output Enable

  Ddr_Wr_Dqs  U5_Ddr_Wr_Dqs
  (
    .Sys_Clk          ( Clk_TxDqs       ) , //System Clock
    .I_Sync_Clr       ( Rst_TxDqs       ) , //Sync Reset
    .Cfg_Dqs_Delay    ( Conf_Dqs_Dly    ) , //(I)Config Tx Dqs Delay
    .I_Phy_Cmd_Write  ( I_Phy_Cmd_Write ) , //(I)Command Write 
    .I_WrLevel_En     ( Wr_Level_En     ) , //(I)Write Leveling Enable  
    .O_Ddr_Dqs_Last   ( Ddr_Dqs_Last    ) , //(O)DDR Dqs Last
    .O_Ddr_Dqs_Out    ( Ddr_Dqs_Out     ) , //(O)DDR DQS Output 
    .O_Ddr_Dqs_OE     ( Ddr_Dqs_OE      )   //(O)DDR DQS Output Enable
  );

  /////////////////////////////////////////////////////////
  wire    [3:0]   Calc_Odt_Dly    = Conf_Wr_Latcy - 4'h4  ;
  wire    [2:0]   Conf_Odt_Dly    = Calc_Odt_Dly[2:0]     ; //(I)Config ODT Delay
  wire            Ddr_Odt_Last    ; //(O)DDR Odt Last 
  wire            Ddr_Odt_Out     ; //(O)DDR ODT Output 

  Ddr_Odt_Ctrl  U5_Ddr_Odt_Ctrl
  (
    .Sys_Clk          ( Clk_TxCmd       ) , //System Clock
    .I_Sync_Clr       ( Rst_TxCmd       ) , //Sync Reset
    .Cfg_Odt_Delay    ( Conf_Odt_Dly    ) , //(I)Config Write Latency
    .I_Phy_Cmd_Write  ( I_Phy_Cmd_Write ) , //(I)Command Write 
    .I_WrLevel_En     ( Wr_Level_En     ) , //(I)Write Leveling Enable  
    .O_Ddr_Odt_Last   ( Ddr_Odt_Last    ) , //(O)DDR Odt Last 
    .O_Ddr_Odt_Out    ( Ddr_Odt_Out     )   //(O)DDR ODT Output 
  );

  /////////////////////////////////////////////////////////
  assign    O_Ddr_Odt     = Ddr_Odt_Out           ; //(O)DDR ODT
  assign    O_Ddr_Dqs_Hi  = {DMW{Ddr_Dqs_Out[0]}} ; //(O)DDR DQS output
  assign    O_Ddr_Dqs_Lo  = {DMW{Ddr_Dqs_Out[1]}} ; //(O)DDR DQS output
  assign    O_Ddr_Dqs_Oe  = {DMW{Ddr_Dqs_OE}}     ; //(O)DDR DQS
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
//555555555555555555555555555555555555555555555555555555555
//////////////////////   Ddr_Write   //////////////////////

endmodule

///////////////////////////////////////////////////////////







///////////////////   Ddr_WrData_Fifo   ///////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2023-08-10
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_WrData_Fifo
(
  Clk_TxDq        , //Clock Tx DQ
  Clk_Axi         , //Clock Axi
  Rst_TxDq        , //Reset In Clock Tx DQ
  Rst_Axi         , //Reset In Clock Axi
  //AXI WBus Signal
  I_W_ID          , //(I)[WrData]Write ID tag.
  I_W_DATA        , //(O)[WrData]Write data.
  I_W_STRB        , //(I)[WrData]Write strobes.
  I_W_LAST        , //(I)[WrData]Write last.
  I_W_VALID       , //(I)[WrData]Write valid.
  O_W_READY       , //(I)[WrData]Write ready.
  //Test Interface
  I_Test_Mode     , //(I)[Clk_Axi ] Test Mode 
  I_WrLevel_En    , //(I)[Clk_Core] Write Leveling Enable  
  I_T_W_Wr_En     , //(I)[Clk Axi ] Test WBus Write Enable
  I_T_W_Wr_D      , //(I)[Clk Axi ] Test WBus Write Data
  O_T_W_Ready     , //(O)[Clk Axi ] Test WBus Write Buffer Full
  //DDR Signal
  I_Axi_W_Pause   , //(O)[Clk_Axi ] Axi WBus Write Pause
  O_Axi_W_WrEn    , //(O)[Clk_Axi ] Axi WBus Write Enable
  I_Ddr_W_RdEn    , //(I)[Clk_TxDq] DDR Write Bus Read Enable
  O_Ddr_W_Empty   , //(O)[Clk_TxDq] DDR Write Bus Read Empty
  O_Ddr_W_DVal    , //(O)[Clk_TxDq] DDR Write Bus Data Valid 
  O_Ddr_W_Data    , //(O)[Clk_TxDq] DDR Write Bus Data
  O_Ddr_W_Strb    , //(O)[Clk_TxDq] DDR Write Bus Data Strobes(Byte valid)
  O_Ddr_W_Last    , //(O)[Clk_TxDq] DDR Write Bus Data Last
  //DDR Interface
  O_Ddr_Dm_Hi     , //(O)DDR Data Mask Output (HI)
  O_Ddr_Dm_Lo     , //(O)DDR Data Mask Output (LO)
  O_Ddr_Dq_Hi     , //(O)DDR DQ Data Input (HI)
  O_Ddr_Dq_Lo     , //(O)DDR DQ Data Input (LO)
  O_Ddr_Dq_Oe       //(O)DDR DQ Data Output Enable
);

  //Define  Parameter
  /////////////////////////////////////////////////////////

  parameter   AXI_ID_WIDTH        = 8   ;   //AXI4总线ID的宽度
  parameter   AXI_DATA_WIDTH      = 128 ;   //AXI4总线数据的宽度
  parameter   DDR_DATA_WIDTH      = 16  ;   //DDR总线数据的宽度
  parameter   WR_DATA_FIFO_DEPTH       = 512 ;   //写数据FIFO深度

  /////////////
  localparam  DDR_BUS_DATA_WIDTH  = DDR_DATA_WIDTH * 2        ; //内部数据总线的宽度，为DDR数据总线的2倍
  localparam  DDR_BUS_BYTE_NUM    = DDR_BUS_DATA_WIDTH  / 8   ; //内部数据总线字节个数
  localparam  DDR_BUS_BYTE_SIZE   = $clog2(DDR_BUS_BYTE_NUM)  ; //内部数据尺寸，即为字节计数器宽度

  localparam  AXI_BYTE_NUMBER     = AXI_DATA_WIDTH  / 8       ; //AXI4数据总线字节个数
  localparam  AXI_BYTE_SIZE       = $clog2(AXI_BYTE_NUMBER)   ; //AXI4数据尺寸，即为字节计数器宽度

  localparam  DDR_BYTE_NUMBER     = DDR_DATA_WIDTH  / 8       ; //DDR数据总线字节个数
  localparam  DDR_BYTE_SIZE       = $clog2(DDR_BYTE_NUMBER)   ; //DDR数据尺寸，即为字节计数器宽度
  
  /////////////   DM、DQS宽度
  localparam  AXI_DM_WIDTH        = AXI_BYTE_NUMBER           ; //AXI侧掩码宽度
  localparam  DDR_DM_WIDTH        = DDR_BYTE_NUMBER           ; //DDR侧掩码宽度
  localparam  DDR_BUS_DM_WIDTH    = DDR_BUS_BYTE_NUM          ; //DDR内部掩码宽度
    
  /////////////   内部存储有关    
  localparam  BUFF_FIFO_DATA_WIDTH_RITIO  = AXI_DATA_WIDTH  / DDR_BUS_DATA_WIDTH      ; //Buffer/FIFO的数据宽度比
  localparam  BUFF_FIFO_WIDTH_RITIO_SIZE  = $clog2(BUFF_FIFO_DATA_WIDTH_RITIO)        ; //Buffer/FIFO的数据宽度比的计数器宽度

  localparam  WR_DATA_BUFF_WIDTH        = AXI_DATA_WIDTH      + AXI_DM_WIDTH      + 1 ; //写缓存的宽度；
  localparam  WR_DATA_FIFO_WIDTH        = DDR_BUS_DATA_WIDTH  + DDR_BUS_DM_WIDTH  + 1 ; //写FIFO的宽度
  localparam  WR_DATA_FIFO_ADDR_WIDTH   = $clog2(WR_DATA_FIFO_DEPTH)                       ; //写FIFO地址宽度
  localparam  WR_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO                  ; //写缓存个数
  localparam  WR_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                  ; //写缓存个数计数器宽度

  /////////////   缩写               
  localparam  AIW   = AXI_ID_WIDTH              ; //AXI总线ID的宽度  

  localparam  ADW   = AXI_DATA_WIDTH            ; //AXI总线数据的宽度
  localparam  AMW   = AXI_DM_WIDTH              ; //AXI侧掩码宽度

  localparam  DDW   = DDR_DATA_WIDTH            ; //DDR总线数据的宽度
  localparam  DMW   = DDR_DM_WIDTH              ; //DDR侧掩码宽度

  localparam  BDW   = DDR_BUS_DATA_WIDTH        ; //内部数据总线的宽度，为DDR数据总线的2倍
  localparam  BMW   = DDR_BUS_DM_WIDTH          ; //DDR内部掩码宽度

  localparam  WBW   = WR_DATA_BUFF_WIDTH        ; //写缓存的宽度
  localparam  WFW   = WR_DATA_FIFO_WIDTH        ; //写FIFO的宽度
  localparam  WFS   = WR_DATA_FIFO_ADDR_WIDTH   ; //写FIFO地址宽度
  localparam  WBN   = WR_DATA_BUFF_NUMBER       ; //写缓存个数
  localparam  WBS   = WR_DATA_BUFF_NUMBER_SIZE  ; //写缓存个数计数器宽度
  
  localparam  BFWR  = BUFF_FIFO_DATA_WIDTH_RITIO  ; //Buffer/FIFO的数据宽度比 
  localparam  BFRS  = BUFF_FIFO_WIDTH_RITIO_SIZE  ; //Buffer/FIFO的数据宽度比的计数器宽度 
  /////////////////////////////////////////////////////////

  // Port Define
  /////////////////////////////////////////////////////////
  input               Clk_TxDq        ; //Clock Tx DQ
  input               Clk_Axi         ; //Clock Axi
  input               Rst_TxDq        ; //Reset In Clock Tx DQ
  input               Rst_Axi         ; //Reset In Clock Axi
  //AXI WBus Signal 
  input   [AIW-1:0]   I_W_ID          ; //(I)[WrData]Write ID tag.
  input   [ADW-1:0]   I_W_DATA        ; //(O)[WrData]Write data.
  input   [AMW-1:0]   I_W_STRB        ; //(I)[WrData]Write strobes.
  input               I_W_LAST        ; //(I)[WrData]Write last.
  input               I_W_VALID       ; //(I)[WrData]Write valid.
  output              O_W_READY       ; //(I)[WrData]Write ready.
  //Test Interface 
  input               I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  input               I_WrLevel_En    ; //(I)[Clk_Core] 写均衡（Write Leveling）允许
  input               I_T_W_Wr_En     ; //(I)[Clk Axi ] 测试WBUS写允许
  input   [WBW-1:0]   I_T_W_Wr_D      ; //(I)[Clk Axi ] 测试WBUS写数据
  output              O_T_W_Ready     ; //(O)[Clk Axi ] 测试WBUS准备好，可以接收指令
  //DDR Signal
  input               I_Axi_W_Pause   ; //(I)[Clk_Axi ] Axi 写总线操作暂停   
  output              O_Axi_W_WrEn    ; //(O)[Clk_Axi ] AXI 写总线写允许(AXI时钟域)
  input               I_Ddr_W_RdEn    ; //(I)[Clk_TxDq] 写总线读数据允许，每次读一个DDRBurst的数据
  output              O_Ddr_W_Empty   ; //(O)[Clk_TxDq] 写总线缓存空
  output              O_Ddr_W_DVal    ; //(O)[Clk_TxDq] 写总线数据有效
  output  [BDW-1:0]   O_Ddr_W_Data    ; //(O)[Clk_TxDq] 提供给DDR数据接口的数据
  output  [BMW-1:0]   O_Ddr_W_Strb    ; //(O)[Clk_TxDq] 提供给DDR数据接口的掩码（DM）
  output              O_Ddr_W_Last    ; //(O)[Clk_TxDq] DDR突发的最后一个数据指示
  //DDR Interface
  output  [DMW-1:0]   O_Ddr_Dm_Hi     ; //(O)DDR Data Mask Output (HI)
  output  [DMW-1:0]   O_Ddr_Dm_Lo     ; //(O)DDR Data Mask Output (LO)
  output  [DDW-1:0]   O_Ddr_Dq_Hi     ; //(O)DDR DQ Data Input (HI)
  output  [DDW-1:0]   O_Ddr_Dq_Lo     ; //(O)DDR DQ Data Input (LO)
  output  [DDW-1:0]   O_Ddr_Dq_Oe     ;  //(O)DDR DQ Data Output Enable
  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [AIW-1:0]   Axi_W_ID        = I_W_ID        ; //(I)[WrData]Write ID tag.
  wire  [ADW-1:0]   Axi_W_DATA      = I_W_DATA      ; //(O)[WrData]Write data.
  wire  [AMW-1:0]   Axi_W_STRB      = I_W_STRB      ; //(I)[WrData]Write strobes.
  wire              Axi_W_LAST      = I_W_LAST      ; //(I)[WrData]Write last.
  wire              Axi_W_VALID     = I_W_VALID     ; //(I)[WrData]Write valid.

  wire              Wr_Level_En     = I_WrLevel_En  ; //(I)[Clk_Core] 写均衡（Write Leveling）允许 
  wire              Test_Mode       = I_Test_Mode   ; //(I)[Clk_Axi ] 测试模式，高有效
  wire              Test_W_WrEn     = I_T_W_Wr_En   ; //(I)[Clk Axi ] 测试ABUS写允许
  wire  [WBW-1:0]   Test_W_WrD      = I_T_W_Wr_D    ; //(I)[Clk Axi ] 测试ABUS写数据

  wire              Axi_WBus_Pause  = I_Axi_W_Pause ; //(I)[Clk_Axi ] Axi 写总线操作暂停   
  wire              Ddr_WBus_RdEn   = I_Ddr_W_RdEn  ; //(I)DDR Write Bus Read Enable

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
///////////////////   Ddr_WrData_Fifo   ///////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   WBus_Pause_Flage  = 1'h0  ; //在数据传输结束再结束

  always  @(posedge Clk_Axi)  
  begin
    if (~Axi_WBus_Pause)    WBus_Pause_Flage  <=  1'h0 ;
    else if (Axi_W_VALID)   WBus_Pause_Flage  <=  Axi_W_LAST  ;
    else                    WBus_Pause_Flage  <=  1'h1 ;
  end

  wire    WBus_Pause  = WBus_Pause_Flage & (~Axi_W_VALID) ;

  /////////////////////////////////////////////////////////
  reg     Ddr_WBus_Busy ;
  reg     Axi_W_READY   = 1'h0  ;
  reg     Test_W_Ready  = 1'h0  ;

  wire  Axi_WBus_WrEn   = Test_Mode ? Test_W_WrEn : (Axi_W_READY & Axi_W_VALID) ;
  
  always  @(posedge Clk_Axi)  Axi_W_READY   <=  (~Ddr_WBus_Busy)  & (~WBus_Pause )  ;
  always  @(posedge Clk_Axi)  Test_W_Ready  <=  (~Ddr_WBus_Busy)  & (~WBus_Pause )  & Test_Mode ;

  /////////////////////////////////////////////////////////
  reg           Axi_Wr_Valid  = 1'h0        ;
  reg [WBW-1:0] Axi_Wr_Data   = {WBW{1'h0}} ;
  
  always  @(posedge Clk_Axi)  if(Axi_WBus_WrEn)  Axi_Wr_Valid <=  ~Axi_Wr_Valid ;
  always  @(posedge Clk_Axi)  if(Axi_WBus_WrEn)  
  begin
    if (Test_Mode)    Axi_Wr_Data <=    Test_W_WrD  ;
    else              Axi_Wr_Data <=  { Axi_W_LAST  ,
                                        Axi_W_STRB  , 
                                        Axi_W_DATA  } ;
  end

  /////////////////////////////////////////////////////////
  wire    O_W_READY     = Axi_W_READY     ; //(I)[WrData]Write ready.
  wire    O_Axi_W_WrEn  = Axi_WBus_WrEn   ; //(O)[Clk_Axi ] AXI 写总线写允许(AXI时钟域)
  wire    O_T_W_Ready   = Test_W_Ready    ; //(O)[Clk Axi ] 测试WBUS准备好，可以接收指令
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
///////////////////   Ddr_WrData_Fifo   ///////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [    1:0]   Axi_Wr_Valid_Reg  = 2'h0        ;
  reg   [WBW-1:0]   Axi_Wr_Data_Reg   = {WBW{1'h0}} ;

  always  @(posedge Clk_TxDq) Axi_Wr_Valid_Reg  <=  {Axi_Wr_Valid_Reg[0] , Axi_Wr_Valid } ;
  always  @(posedge Clk_TxDq) Axi_Wr_Data_Reg   <=  Axi_Wr_Data  ;

  /////////////////////////////////////////////////////////
  wire              WBus_Buff_Wr_En     = (^Axi_Wr_Valid_Reg) ;
  wire  [WBW-1:0]   WBus_Buff_Wr_Data   = Axi_Wr_Data_Reg     ;

  wire              WBus_Buff_Rd_En     ; //(I) FIFO Read Enable

  wire  [WBW-1:0]   WBus_Buff_Rd_Data   ; //(O) FIFO Read Data  
  wire  [    3:0]   WBus_Buff_Data_Num  ; //(O) Ram Data Number
  wire              WBus_Buff_Wr_Full   ; //(O) FIFO Write Full
  wire              WBus_Buff_Rd_Empty  ; //(O) FIFO Write Empty
  wire              WBus_Buff_Fifo_Err  ; //(O) FIFO Error

  defparam    U2_WBus_Buffer.OUT_REG     = "No"  ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam    U2_WBus_Buffer.DATA_WIDTH  = WR_DATA_BUFF_WIDTH    ; //Data Width
  defparam    U2_WBus_Buffer.DATA_DEPTH  = 8                ; //Address Width

  Ddr_Ctrl_Sc_Fifo  U2_WBus_Buffer
  (
    .Sys_Clk      ( Clk_TxDq            ) , //System Clock
    .Sync_Clr     ( Rst_TxDq            ) , //Sync Reset
    .I_Wr_En      ( WBus_Buff_Wr_En     ) , //(I) FIFO Write Enable
    .I_Wr_Data    ( WBus_Buff_Wr_Data   ) , //(I) FIFO Write Data
    .I_Rd_En      ( WBus_Buff_Rd_En     ) , //(I) FIFO Read Enable
    .O_Rd_Data    ( WBus_Buff_Rd_Data   ) , //(O) FIFO Read Data
    .O_Data_Num   ( WBus_Buff_Data_Num  ) , //(O) FIFO Data Number
    .O_Wr_Full    ( WBus_Buff_Wr_Full   ) , //(O) FIFO Write Full
    .O_Rd_Empty   ( WBus_Buff_Rd_Empty  ) , //(O) FIFO Write Empty
    .O_Fifo_Err   ( WBus_Buff_Fifo_Err  )   //(O) Fifo Error
  ) ;
  
  /////////////////////////////////////////////////////////
  wire              Buff_W_LAST ;    
  wire  [AMW-1:0]   Buff_W_STRB ;     
  wire  [ADW-1:0]   Buff_W_DATA ;      

  assign  { Buff_W_LAST ,
            Buff_W_STRB ,
            Buff_W_DATA } = WBus_Buff_Rd_Data ;
  /////////////////////////////////////////////////////////
  reg   WBus_Buff_Busy  = 1'h0  ;

  always  @(posedge Clk_TxDq)  WBus_Buff_Busy  <=  (|WBus_Buff_Data_Num[3:2]) ;

//222222222222222222222222222222222222222222222222222222222
///////////////////   Ddr_WrData_Fifo   ///////////////////
//333333333333333333333333333333333333333333333333333333333
//
//********************************************************/
  /////////////////////////////////////////////////////////
  localparam  [BFRS-1:0]   FIFO_WR_CNT_INI  = BUFF_FIFO_DATA_WIDTH_RITIO-{{BFRS{1'h0}},1'h1}; //FIFO写计数器的初始化值
  /////////////////////////////////////////////////////////
  reg   Buff_Data_Valid   = 1'h0  ;
  
  always  @(posedge Clk_TxDq) Buff_Data_Valid   <=  ~WBus_Buff_Rd_Empty ;

  wire    Buff_Pre_Read   = (~Buff_Data_Valid) & (~WBus_Buff_Rd_Empty)  ;

  /////////////////////////////////////////////////////////
  reg   [BFRS:0]  Fifo_Wr_Cnt   = {BFRS+1{1'h1}}  ;
  reg             Buff_Rd_En    = 1'h0            ;
  reg             Buff_Val_Flag = 1'h0            ;
  
  wire    Fifo_Wr_En  = Fifo_Wr_Cnt[BFRS]  ;

  
  always  @(posedge Clk_TxDq)
  begin
    if (Rst_TxDq)             Buff_Val_Flag   <=  1'h0  ;
    else if (Buff_Rd_En)      Buff_Val_Flag   <=  1'h0  ;
    else if (~Fifo_Wr_En)     Buff_Val_Flag   <=  1'h0  ;
    else if (Buff_Pre_Read)   Buff_Val_Flag   <=  Fifo_Wr_En  ;
  end
  always  @(posedge Clk_TxDq)
  begin
    if (Rst_TxDq)             Buff_Rd_En  <=  1'h0  ;
    else if (Buff_Rd_En)      Buff_Rd_En  <=  1'h0  ;
    else if (Fifo_Wr_En)
    begin
      Buff_Rd_En  <=  (Fifo_Wr_Cnt == {1'h1, {BFRS-1{1'h0}},1'h1}) & (~WBus_Buff_Rd_Empty);
    end
    else if (Buff_Pre_Read)   Buff_Rd_En  <=  1'h1  ;
    else if (Buff_Val_Flag)   Buff_Rd_En  <=  1'h1  ;
  end
  always  @(posedge Clk_TxDq)
  begin
    if (Rst_TxDq)             Fifo_Wr_Cnt <=  {BFRS+1{1'h0}}   ;
    else if (Buff_Rd_En)      Fifo_Wr_Cnt <=  { 1'h1 , FIFO_WR_CNT_INI  } ;
    else if (Fifo_Wr_En)      Fifo_Wr_Cnt <=  Fifo_Wr_Cnt - {{BFRS{1'h0}},1'h1} ;
  end

  assign  WBus_Buff_Rd_En = Buff_Rd_En ;

  /////////////////////////////////////////////////////////
  reg               Buff_W_LAST_Reg   = 1'h0        ;    
  reg   [AMW-1:0]   Buff_W_STRB_Sft   = {AMW{1'h0}} ;     
  reg   [ADW-1:0]   Buff_W_DATA_Sft   = {ADW{1'h0}} ;   
  
  always  @(posedge Clk_TxDq)
  begin
    if(Buff_Rd_En) 
    begin
      Buff_W_LAST_Reg   <=  Buff_W_LAST ;    
      Buff_W_STRB_Sft   <=  Buff_W_STRB ;     
      Buff_W_DATA_Sft   <=  Buff_W_DATA ;      
    end
    else 
    begin
      Buff_W_STRB_Sft   <=  {{BMW{1'h0}}  , Buff_W_STRB_Sft[AMW-1:BMW]} ;     
      Buff_W_DATA_Sft   <=  {{BDW{1'h0}}  , Buff_W_DATA_Sft[ADW-1:BDW]} ;      
    end
  end

  wire               Fifo_Wr_W_LAST   = Buff_W_LAST_Reg           ;
  wire   [BMW-1:0]   Fifo_Wr_W_STRB   = Buff_W_STRB_Sft[BMW-1:0]  ;
  wire   [BDW-1:0]   Fifo_Wr_W_DATA   = Buff_W_DATA_Sft[BDW-1:0]  ;

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333
///////////////////   Ddr_WrData_Fifo   ///////////////////
//444444444444444444444444444444444444444444444444444444444
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [2:0]   Fifo_Rd_Cnt   = 3'h0  ;

  wire  Fifo_Rd_En    = Fifo_Rd_Cnt[2]  ;
  wire  Ddr_WBus_DVal = Fifo_Rd_Cnt[2]  ;

  always  @(posedge Clk_TxDq)
  begin
    if (Rst_TxDq)             Fifo_Rd_Cnt <=  3'h0  ;
    else if (Ddr_WBus_RdEn)   Fifo_Rd_Cnt <=  3'h7  ;
    else if (Fifo_Rd_En)      Fifo_Rd_Cnt <=  Fifo_Rd_Cnt - 3'h1  ;
  end

  /////////////////////////////////////////////////////////
  wire  [WFW-1:0]   WBus_Fifo_WrData  ; //(I)Write Data

  assign  WBus_Fifo_WrData  = { Fifo_Wr_W_LAST  ,
                              ~ Fifo_Wr_W_STRB  ,
                                Fifo_Wr_W_DATA  } ;

  /////////////////////////////////////////////////////////
  wire              WBus_Fifo_RdEn      = Fifo_Rd_En ; //(I)Read Enable
  
  wire  [WFS  :0]   WBus_Fifo_DataNum   ; //(O)Data Number In Fifo
  wire              WBus_Fifo_WrEn      = Fifo_Wr_En ; //(I)Write Enable
  wire              WBus_Fifo_WrErr     ; //(O)Write Error
  wire              WBus_Fifo_WrFull    ; //(O)Write Full 
  wire              WBus_Fifo_AlmFull   ; //(O)almost Full
  
  wire              WBus_Fifo_RdErr     ; //(O)Read Error
  wire              WBus_Fifo_RdEmpty   ; //(O)Read FifoEmpty
  wire              WBus_Fifo_AlmEmpty  ; //(O)almost Empty
  wire              WBus_Fifo_DataVal   ; //(O)Data Valid
  wire  [WFW-1:0]   WBus_Fifo_RdData    ; //(O)Read Data

  defparam  U4_WBus_Fifo.FIFO_MODE        = "ShowAhead"     ; //"Normal"; //"ShowAhead"
  defparam  U4_WBus_Fifo.DATA_WIDTH       = WR_DATA_FIFO_WIDTH    ;     
  defparam  U4_WBus_Fifo.DATA_DEPTH       = WR_DATA_FIFO_DEPTH    ; 
  defparam  U4_WBus_Fifo.AFULL_THRESHOLD  = WR_DATA_BUFF_NUMBER   * 8 ;
  defparam  U4_WBus_Fifo.AEMPTY_THRESHOLD = 4   ;
      
  SC_FIFO   U4_WBus_Fifo
  (   
    //System Signal
    .SysClk     ( Clk_TxDq            ) , //(I)System Clock
    .Reset      ( Rst_TxDq            ) , //(I)System Reset (Sync / High Active)
    .DataNum    ( WBus_Fifo_DataNum   ) , //(O)Data Number In Fifo
    //Write Signal                             
    .WrEn       ( WBus_Fifo_WrEn      ) , //(I)Write Enable
    .WrErr      ( WBus_Fifo_WrErr     ) , //(O)Write Error
    .WrFull     ( WBus_Fifo_WrFull    ) , //(O)Write Full 
    .AlmFull    ( WBus_Fifo_AlmFull   ) , //(O)almost Full
    .WrData     ( WBus_Fifo_WrData    ) , //(I)Write Data
    //Read Signal                           
    .RdEn       ( WBus_Fifo_RdEn      ) , //(I)Read Enable
    .RdErr      ( WBus_Fifo_RdErr     ) , //(O)Read Error
    .RdEmpty    ( WBus_Fifo_RdEmpty   ) , //(O)Read FifoEmpty
    .AlmEmpty   ( WBus_Fifo_AlmEmpty  ) , //(O)almost Empty
    .DataVal    ( ) , //(O)Data Valid 
    .RdData     ( WBus_Fifo_RdData    )   //(O)Read Data
  );
  
  /////////////////////////////////////////////////////////
  wire      WBus_Fifo_Busy  = WBus_Fifo_AlmFull  ;

  always  @(posedge Clk_TxDq) Ddr_WBus_Busy <=  WBus_Fifo_Busy 
                                              | WBus_Buff_Busy  ;

  /////////////////////////////////////////////////////////
  wire              Ddr_WBus_Empty;
  wire              Ddr_WBus_Last ; 
  wire  [BMW-1:0]   Ddr_WBus_Strb ; 
  wire  [BDW-1:0]   Ddr_WBus_Data ; 

  assign    Ddr_WBus_Empty  = WBus_Fifo_RdEmpty ;
  assign  { Ddr_WBus_Last ,
            Ddr_WBus_Strb ,
            Ddr_WBus_Data } = WBus_Fifo_RdData  ;

  ///////////////////////////////////////////////////////// 
  wire              O_Ddr_W_DVal    = Ddr_WBus_DVal   ; //(O)DDR Write Bus Data Valid 
  wire              O_Ddr_W_Empty   = Ddr_WBus_Empty  ; //(O)DDR Write Bus Read Empty
  wire  [BDW-1:0]   O_Ddr_W_Data    = Ddr_WBus_Data   ; //(O)DDR Write Bus Data
  wire  [BMW-1:0]   O_Ddr_W_Strb    = Ddr_WBus_Strb   ; //(O)DDR Write Bus Data Strobes(Byte valid)
  wire              O_Ddr_W_Last    = Ddr_WBus_Last   ; //(O)DDR Write Bus Data Last
  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444
///////////////////   Ddr_WrData_Fifo   ///////////////////
//555555555555555555555555555555555555555555555555555555555
//
//********************************************************/
  ///////////////////////////////////////////////////////// 
  reg   [1:0]   DBG_Data_Gen  = 2'h0  ;
  
  always  @(posedge Clk_TxDq) 
  begin
    if (Ddr_WBus_DVal)  DBG_Data_Gen  <=  DBG_Data_Gen  + 2'h1  ;
    else                DBG_Data_Gen  <=  2'h0  ;
  end

  wire  [BDW-1:0]   DBG_Ddr_Data  = {BDW/4{2'h0,DBG_Data_Gen}} ;

  /////////////////////////////////////////////////////////
  reg     Ddr_WBus_Oe_Reg   = 1'h0  ;

  always  @(posedge Clk_TxDq)   Ddr_WBus_Oe_Reg <=  (Ddr_WBus_DVal  | Ddr_WBus_RdEn)
                                                  & (~Wr_Level_En   ) ;
  
  wire  Ddr_WBus_Oe   =   Ddr_WBus_RdEn | Ddr_WBus_Oe_Reg ;
  // wire  Ddr_WBus_Oe   =   Ddr_WBus_DVal & (~Wr_Level_En) ;
  /////////////////////////////////////////////////////////
  reg   [DMW-1:0]   Ddr_Dm_Hi ; //DDR Data Mask Output (HI)
  reg   [DMW-1:0]   Ddr_Dm_Lo ; //DDR Data Mask Output (LO)
  reg   [DDW-1:0]   Ddr_Dq_Hi ; //DDR DQ Data Input (HI)
  reg   [DDW-1:0]   Ddr_Dq_Lo ; //DDR DQ Data Input (LO)
  reg   [DDW-1:0]   Ddr_Dq_Oe ; //DDR DQ Data Output Enable
  
  always @(posedge Clk_TxDq)  Ddr_Dm_Hi = Ddr_WBus_Strb[DMW-1:  0]  ;
  always @(posedge Clk_TxDq)  Ddr_Dm_Lo = Ddr_WBus_Strb[BMW-1:DMW]  ;
  always @(posedge Clk_TxDq)  Ddr_Dq_Hi = Ddr_WBus_Data[DDW-1:  0]  ;
  always @(posedge Clk_TxDq)  Ddr_Dq_Lo = Ddr_WBus_Data[BDW-1:DDW]  ;
  always @(posedge Clk_TxDq)  Ddr_Dq_Oe = {DDW{Ddr_WBus_Oe}}        ;
  
  /////////////////////////////////////////////////////////  
  assign    O_Ddr_Dm_Hi     = Ddr_Dm_Hi ; //(O)DDR Data Mask Output (HI)
  assign    O_Ddr_Dm_Lo     = Ddr_Dm_Lo ; //(O)DDR Data Mask Output (LO)
  assign    O_Ddr_Dq_Hi     = Ddr_Dq_Hi ; //(O)DDR DQ Data Input (HI)
  assign    O_Ddr_Dq_Lo     = Ddr_Dq_Lo ; //(O)DDR DQ Data Input (LO)
  assign    O_Ddr_Dq_Oe     = Ddr_Dq_Oe ;  //(O)DDR DQ Data Output Enable
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
//555555555555555555555555555555555555555555555555555555555
///////////////////   Ddr_WrData_Fifo   ///////////////////

endmodule

///////////////////   Ddr_WrData_Fifo   ///////////////////






/////////////////////    Wr_Data_Num    ///////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2021-03-01
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Wr_Data_Num
(
  input           Clk_Core    , //(I)[Clk_Core ] Clock Core
  input           Clk_Axi     , //(I)[Clk_Axi  ] AXi Data Write Clock
  input           Clk_TxCmd   , //(I)[Clk_RxCmd] Clock Tx Command
  input           Rst_TxCmd   , //(I)[Clk_RxCmd] Reset Tx Command
  input           I_DW_Wr_En  , //(I)[Clk_Axi  ] AXI Data Write Enable
  input           I_AW_Rd_En  , //(I)[Clk_Core ] AXI Address Read Enable
  output  [9:0]   O_Data_Num  , //(O)[Clk_RxCmd] Data Number In Fifo
  output          O_RdWr_Err  , //(O)[Clk_RxCmd] Fifo Read Write Error
  output          O_DW_Empty    //(O)[Clk_Core ] Data Write Fifo Empty
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
/////////////////////    Wr_Data_Num    ///////////////////
//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  DW_Wr_En  = I_DW_Wr_En  ; //AXI Data Write Enable (Clk_Axi)
  wire  AW_Rd_En  = I_AW_Rd_En  ; //AXI Address Read Enable (Clk_Core)
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
/////////////////////    Wr_Data_Num    ///////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg     Axi_Clk_Div   = 1'h0  ;
  reg     Axi_WrEn_Reg  = 1'h0  ;

  always @(posedge Clk_Axi)  Axi_Clk_Div  <=  ~Axi_Clk_Div  ;
  always @(posedge Clk_Axi)  Axi_WrEn_Reg <=  DW_Wr_En      ;

  /////////////////////////////////////////////////////////
  reg   [1:0]   Cmd_WrEn_Reg   = 2'h0 ;
  reg           Cmd_Wr_En      = 1'h0 ;

  always @(posedge Clk_TxCmd) Cmd_WrEn_Reg  <=  {Cmd_WrEn_Reg[0]  , Axi_Clk_Div } ;
  always @(posedge Clk_TxCmd) Cmd_Wr_En     <=  (^Cmd_WrEn_Reg )  & Axi_WrEn_Reg  ;

  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
/////////////////////    Wr_Data_Num    ///////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg     Core_Clk_Div   = 1'h0  ;
  reg     Core_RdEn_Reg  = 1'h0  ;

  always @(posedge Clk_Core )  Core_Clk_Div   <=  ~Core_Clk_Div ;
  always @(posedge Clk_Core )  Core_RdEn_Reg  <=  AW_Rd_En      ;

  /////////////////////////////////////////////////////////
  reg   [1:0]   Cmd_RdEn_Reg   = 2'h0 ;
  reg           Cmd_Rd_En      = 1'h0 ;

  always @(posedge Clk_TxCmd )  Cmd_RdEn_Reg  <=  { Cmd_RdEn_Reg[0] , Core_Clk_Div } ;
  always @(posedge Clk_TxCmd )  Cmd_Rd_En     <=  (^Cmd_RdEn_Reg )  & Core_RdEn_Reg  ;

  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222
/////////////////////    Wr_Data_Num    ///////////////////
//333333333333333333333333333333333333333333333333333333333
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire          Cmd_RdWr_Err  ;
  reg   [9:0]   Data_Num_Cnt  = 10'h0 ;

  always @(posedge Clk_TxCmd )
  begin
    if (Rst_TxCmd)            Data_Num_Cnt  <=  10'h0 ;
    else if (Cmd_RdWr_Err)    Data_Num_Cnt  <=  10'h0 ;
    else if (Cmd_Rd_En ^ Cmd_Wr_En)
    begin
      if (Cmd_Wr_En)        Data_Num_Cnt  <=  Data_Num_Cnt + 10'h1 ;
      else if (Cmd_Rd_En)   Data_Num_Cnt  <=  Data_Num_Cnt - 10'h1 ;
    end
  end
  assign    Cmd_RdWr_Err  = Data_Num_Cnt[9] ;

  /////////////////////////////////////////////////////////
  reg           Cmd_DNum_Zero =  1'h0 ;
  reg           Cmd_Empty_En  =  1'h0 ;

  always @(posedge Clk_TxCmd )
  begin
    Cmd_Empty_En  <=  (Cmd_Rd_En & (~Cmd_Wr_En))  & (~|Data_Num_Cnt[9:1]) ;
  end
  always @(posedge Clk_TxCmd )
  begin
    if (Cmd_Rd_En & (~Cmd_Wr_En))
    begin
      Cmd_DNum_Zero <=  (~|Data_Num_Cnt[9:1]) ;
    end
    else  Cmd_DNum_Zero <=  (~|Data_Num_Cnt)  ;
  end

  /////////////////////////////////////////////////////////
  reg   [2:0]   Cmd_Empty_Cnt   = 3'h0  ;
  reg           Cmd_Empty       = 1'h0  ;

  always @(posedge Clk_TxCmd )
  begin
    if  (Cmd_Empty_En)          Cmd_Empty_Cnt <=  3'h7  ;
    else if (Cmd_Empty_Cnt[2])  Cmd_Empty_Cnt <=  Cmd_Empty_Cnt - 3'h1 ;
  end
  always @(posedge Clk_TxCmd )
  begin
    Cmd_Empty   <=  Cmd_Empty_En | Cmd_Empty_Cnt[2] | Cmd_DNum_Zero ;
  end

  /////////////////////////////////////////////////////////
  assign    O_Data_Num  = Data_Num_Cnt  ; //(O)Data Number In Fifo
  assign    O_RdWr_Err  = Cmd_RdWr_Err  ; //(O)Fifo Read Write Error
  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333
/////////////////////    Wr_Data_Num    ///////////////////
//444444444444444444444444444444444444444444444444444444444
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   Core_Empty  = 1'h0  ;

  always @(posedge Clk_Core)    Core_Empty  <= Cmd_Empty  ;

  /////////////////////////////////////////////////////////
  assign  O_DW_Empty  = Core_Empty  ; //(O)Data Write Fifo Empty (Clk_Core)
  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444

endmodule

///////////////////////////////////////////////////////////






////////////////////    BBus_Process   ////////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2021-08-10
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  BBus_Process
(
  //System Signal
  Clk_Core        , //Clock Core
  Clk_Axi         , //Clock Axi
  Rst_Core        , //Reset In Clock Core
  Rst_Axi         , //Reset In Clock Axi
  //AXI BBus Signal
  I_AW_ID         , //(I)[WrAddr]Write address ID.
  O_B_ID          , //(O)[WrResp]Response ID tag.
  O_B_VALID       , //(O)[WrResp]Write response valid.
  I_B_READY       , //(I)[WrResp]Response ready.
  //Ddr Siganl
  I_Test_Mode     , //(I)[Clk_Axi ] Test Mode 
  I_AW_Bst_Last   , //(I)DDR AWBus Last Operate
  I_Axi_AW_WrEn   , //(I)DDR AWBus Write Enable
  O_Ddr_B_Busy    , //(O)DDR BBus Busy
  O_Axi_B_Busy      //(O)AXI BBus Busy
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  parameter     AXI_ID_WIDTH        = 8 ;
  parameter     WR_BURST_QUEUE_NUM  = 8 ; //写最大地址队列深度

  localparam    BBUS_ID_BUFF_DEPTH  = WR_BURST_QUEUE_NUM   + 8 ;
  localparam    ID_BUFF_ADDR_WIDTH  = $clog2(BBUS_ID_BUFF_DEPTH  ) ;

  /////////////
  localparam  AIW   = AXI_ID_WIDTH        ;
  localparam  IAW   = ID_BUFF_ADDR_WIDTH  ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  //System Signal
  input               Clk_Core        ; //Clock Core
  input               Clk_Axi         ; //Clock Axi
  input               Rst_Core        ; //Reset In Clock Core
  input               Rst_Axi         ; //Reset In Clock Axi
  //AXI BBus Signal 
  input   [AIW-1:0]   I_AW_ID         ; //(I)[WrAddr]Write address ID.
  output  [AIW-1:0]   O_B_ID          ; //(O)[WrResp]Response ID tag.
  output              O_B_VALID       ; //(O)[WrResp]Write response valid.
  input               I_B_READY       ; //(I)[WrResp]Response ready.
  //Ddr Siganl
  input               I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  input               I_Axi_AW_WrEn   ; //(I)[Clk_Axi ] 写地址总线写允许（AW_READY & AW_VALID)
  input               I_AW_Bst_Last   ; //(I)[Clk_Core] 写地址总线当前Burst最后一个操作
  output              O_Axi_B_Busy    ; //(O)[Clk_Axi ] AXI侧B总线忙，表示IDFiFo满，需要暂停接收AXI的AW接口
  output              O_Ddr_B_Busy    ; //(O)[Clk_Core] DDR侧B总线忙，表示AXI的B接口拥塞，需要暂停DDR写操作
  /////////////////////////////////////////////////////////
////////////////////    BBus_Process   ////////////////////
//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [AIW-1:0]   Axi_AW_ID         = I_AW_ID         ; //(I)写地址总线当前操作的ID
  wire              Axi_B_READY       = I_B_READY       ; //(I)[WrResp]Response ready.
  wire              Test_Mode         = I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  wire              Axi_AWBus_WrEn    = I_Axi_AW_WrEn   ; //(I)[Clk_Axi ] 写地址总线写允许（AW_READY & AW_VALID)
  wire              AWBus_Bst_Last    = I_AW_Bst_Last   ; //(I)[Clk_Core] 写地址总线当前Burst最后一个操作
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
////////////////////    BBus_Process   ////////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  //取Wr_Last_Ack的上升沿
  reg           Wr_Last_Ack   = 1'h0  ;
  reg   [1:0]   Wr_Last_Ack_Reg   = 2'h0  ;
  reg           Wr_Last_Ack_Rise  = 1'h0  ;

  always  @(posedge Clk_Axi)  Wr_Last_Ack_Reg   <=  {Wr_Last_Ack_Reg[0] , Wr_Last_Ack } ;
  always  @(posedge Clk_Axi)  Wr_Last_Ack_Rise  <=  (Wr_Last_Ack_Reg    ==  2'h1      ) ;

  /////////////////////////////////////////////////////////
  reg     Axi_B_Valid     = 1'h0  ;

  wire    Axi_BBus_Rd_En  = ( Axi_B_Valid & ( Axi_B_READY | Test_Mode ) ) ;
  
  always  @(posedge Clk_Axi)
  begin
    if (Rst_Axi)                  Axi_B_Valid <=  1'h0  ;
    else if (Axi_BBus_Rd_En)      Axi_B_Valid <=  1'h0  ;
    else if (Wr_Last_Ack_Rise)    Axi_B_Valid <=  1'h1  ;
  end

  /////////////////////////////////////////////////////////
  wire              B_ID_Buff_Wr_En     = Axi_AWBus_WrEn  ;
  wire  [AIW-1:0]   B_ID_Buff_Wr_Data   = Axi_AW_ID       ; //(I) FIFO Write Data
  wire              B_ID_Buff_Rd_En     = Axi_BBus_Rd_En  ; //(I) FIFO Read Enable

  wire  [AIW-1:0]   B_ID_Buff_Rd_Data   ; //(O) FIFO Read Data
  wire  [IAW  :0]   B_ID_Buff_Data_Num  ; //(O) Ram Data Number
  wire              B_ID_Buff_Wr_Full   ; //(O) FIFO Write Full
  wire              B_ID_Buff_Rd_Empty  ; //(O) FIFO Write Empty
  wire              B_ID_Buff_Fifo_Err  ; //(O) FIFO Error


  defparam    U1_B_ID_Buffer.OUT_REG     = "No"               ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam    U1_B_ID_Buffer.DATA_WIDTH  = AXI_ID_WIDTH       ; //Data Width
  defparam    U1_B_ID_Buffer.DATA_DEPTH  = BBUS_ID_BUFF_DEPTH ; //Data Depth

  Ddr_Ctrl_Sc_Fifo  U1_B_ID_Buffer
  (
    .Sys_Clk      ( Clk_Axi             ) , //System Clock
    .Sync_Clr     ( Rst_Axi             ) , //Sync Reset
    .I_Wr_En      ( B_ID_Buff_Wr_En     ) , //(I) FIFO Write Enable
    .I_Wr_Data    ( B_ID_Buff_Wr_Data   ) , //(I) FIFO Write Data
    .I_Rd_En      ( B_ID_Buff_Rd_En     ) , //(I) FIFO Read Enable
    .O_Rd_Data    ( B_ID_Buff_Rd_Data   ) , //(O) FIFO Read Data
    .O_Data_Num   ( B_ID_Buff_Data_Num  ) , //(O) FIFO Data Number
    .O_Wr_Full    ( B_ID_Buff_Wr_Full   ) , //(O) FIFO Write Full
    .O_Rd_Empty   ( B_ID_Buff_Rd_Empty  ) , //(O) FIFO Write Empty
    .O_Fifo_Err   ( B_ID_Buff_Fifo_Err  )   //(O) Fifo Error
  ) ;

  /////////////////////////////////////////////////////////
  reg     Axi_B_Busy  = 1'h0  ;

  always @(posedge Clk_Axi)  Axi_B_Busy  <= ( &B_ID_Buff_Data_Num[IAW:1] ) ;

  /////////////////////////////////////////////////////////
  wire  [AIW-1:0]   O_B_ID        = B_ID_Buff_Rd_Data ; //(O)[WrResp]Response ID tag.
  wire              O_B_VALID     = Axi_B_Valid       ; //(O)[WrResp]Write response valid.
  wire              O_Axi_B_Busy  = Axi_B_Busy        ; //(O)B总线缓存满
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
////////////////////    BBus_Process   ////////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]   Axi_B_Valid_Reg   = 2'h0  ;
  reg           Axi_B_Valid_Rise  = 1'h0  ;
  reg           Axi_B_Valid_Fall  = 1'h0  ;

  always @(posedge Clk_Core)  Axi_B_Valid_Reg  <= {Axi_B_Valid_Reg[0] , Axi_B_Valid } ;
  always @(posedge Clk_Core)  Axi_B_Valid_Rise <= (Axi_B_Valid_Reg    == 2'h1       ) ;
  always @(posedge Clk_Core)  Axi_B_Valid_Fall <= (Axi_B_Valid_Reg    == 2'h2       ) ;

  /////////////////////////////////////////////////////////
  reg   [2:0]   Wr_Last_Cnt   = 1'h0  ;

  always @(posedge Clk_Core)
  begin
    if (Rst_Core)                 Wr_Last_Cnt <=  3'h0  ;
    else if (Axi_B_Valid_Rise ^ AWBus_Bst_Last )
    begin
      if (AWBus_Bst_Last )        Wr_Last_Cnt <=  Wr_Last_Cnt + 3'h1 ;
      else if (Axi_B_Valid_Rise)  Wr_Last_Cnt <=  Wr_Last_Cnt - 3'h1 ;
    end
  end  

  /////////////////////////////////////////////////////////
  always @(posedge Clk_Core)
  begin
    if (Rst_Core)                   Wr_Last_Ack <=  1'h0  ;
    else if (Wr_Last_Ack)           Wr_Last_Ack <=  ~Axi_B_Valid_Reg[0] ;
    else if (~Axi_B_Valid_Reg[1])   Wr_Last_Ack <=  (|Wr_Last_Cnt)  ;
  end

  /////////////////////////////////////////////////////////
  reg   Ddr_BBus_Busy = 1'h0  ;

  always @(posedge Clk_Core)  Ddr_BBus_Busy <=  (&Wr_Last_Cnt[2:1]) ;

  /////////////////////////////////////////////////////////
  wire        O_Ddr_B_Busy  = Ddr_BBus_Busy ; //(O)DDR侧B总线忙
  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222
////////////////////    BBus_Process   ////////////////////

endmodule

////////////////////    BBus_Process   ////////////////////






////////////////   Ddr_Addr_Bus_Control   /////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2023-08-10
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Addr_Bus_Control
(
  //System Signal
  Clk_Core        , //Clock Core
  Clk_Axi         , //Clock Axi
  Rst_Core        , //Reset In Clock Core 
  Rst_Axi         , //Reset In Clock Axi
  //Axi Signal        
  I_A_ID          , //(I)[Addr]Write address ID.
  I_A_ADDR        , //(I)[Addr]Write address.
  I_A_LEN         , //(I)[Addr]Burst length.
  I_A_SIZE        , //(I)[Addr]Burst size.
  I_A_BURST       , //(I)[Addr]Burst type.
  I_A_LOCK        , //(I)[Addr]Lock type.
  I_A_VALID       , //(I)[Addr]Write address valid.
  O_A_READY       , //(O)[Addr]Write address ready.
  //Test Interface 
  I_Test_Mode     , //(I)[Clk_Axi ] Test Mode 
  I_T_A_Wr_En     , //(I)[Clk Axi ] Test ABus Write Enable
  I_T_A_Wr_D      , //(I)[Clk Axi ] Test ABus Write Data
  O_T_A_Ready     , //(O)[Clk Axi ] Test ABus Write Buffer Full
  //DDR  Siganl
  I_Axi_Op_Pause  , //(I)[Clk_Axi ] DDR Operate Pause 
  O_Axi_A_WrEn    , //(O)[Clk_Axi ] Axi ABus Write Enable
  I_A_Addr_RdEn   , //(I)[Clk_Core] AWBus Read Address Enable
  O_A_Addr_Num    , //(O)[Clk_Core] AWBus Address Number     
  O_A_Addr_Empty  , //(O)[Clk_Core] AWBus Buffer Empty 
  O_A_Addr_Last   , //(O)[Clk_Core] AWBus Buffer Last 
  O_A_Ddr_Addr    , //(O)[Clk_Core] AWBus Address Output 
  O_A_Burst_RdEn  , //(O)[Clk_Core] AWBus Burst Read Enable    
  O_A_Burst_Last  , //(O)[Clk_Core] AWBus Burst Last
  O_A_Next_Param  , //(O)[Clk_Core] AWBus Next Parameter      
  O_A_Curr_Param  , //(O)[Clk_Core] AWBus Current Parameter
  O_A_Err_Flag      //(O)[Clk_Core] AWBus Error Flag
);  

  //Define  Parameter
  /////////////////////////////////////////////////////////  
  parameter   AXI_ID_WIDTH      = 8   ;   //AXI4总线ID的宽度
  parameter   AXI_DATA_WIDTH    = 128 ;   //AXI4总线数据的宽度
  parameter   DDR_DATA_WIDTH    = 16  ;   //DDR总线数据的宽度
  parameter   ADDR_QUEUE_NUM    = 512 ; //最大地址队列个数
  parameter   BURST_QUEUE_NUM   = 16  ;   //最大地址队列深度

  localparam  AXI_BYTE_NUMBER       = AXI_DATA_WIDTH  / 8       ; //AXI4数据总线字节个数
  localparam  AXI_BYTE_SIZE         = $clog2(AXI_BYTE_NUMBER)   ; //AXI4数据尺寸，即为字节计数器宽度

  localparam  DDR_BYTE_NUMBER       = DDR_DATA_WIDTH  / 8       ; //DDR数据总线字节个数
  localparam  DDR_BYTE_SIZE         = $clog2(DDR_BYTE_NUMBER)   ; //DDR数据尺寸，即为字节计数器宽度

  localparam  ADDR_BUFF_DATA_WIDTH  = AXI_ID_WIDTH + 32 + 3 + 8 ; //地址缓存的数据宽度
  localparam  ADDR_BUFF_ADDR_SIZE   = $clog2(BURST_QUEUE_NUM  ) ; //地址缓存的地址尺寸

  /////////////////
  localparam  AIW   = AXI_ID_WIDTH          ; //AXI总线ID的宽度
  localparam  DDS   = DDR_BYTE_SIZE         ; //DDR数据尺寸，即为字节计数器宽度
  localparam  ABS   = ADDR_BUFF_ADDR_SIZE   ; //地址缓存的地址尺寸
  localparam  ABW   = ADDR_BUFF_DATA_WIDTH  ; //地址缓存的数据宽度
  /////////////////////////////////////////////////////////
  // Port Define
  /////////////////////////////////////////////////////////
  //System Signal
  input               Clk_Core        ; //Clock Core
  input               Clk_Axi         ; //Clock Axi
  input               Rst_Core        ; //Reset In Clock Core 
  input               Rst_Axi         ; //Reset In Clock Axi
  //Axi Signal      
  input   [AIW-1:0]   I_A_ID          ; //(I)[Addr]Write address ID.
  input   [   31:0]   I_A_ADDR        ; //(I)[Addr]Write address.
  input   [    7:0]   I_A_LEN         ; //(I)[Addr]Burst length.
  input   [    2:0]   I_A_SIZE        ; //(I)[Addr]Burst size.
  input   [    1:0]   I_A_BURST       ; //(I)[Addr]Burst type.
  input   [    1:0]   I_A_LOCK        ; //(I)[Addr]Lock type.
  input               I_A_VALID       ; //(I)[Addr]Write address valid.
  output              O_A_READY       ; //(O)[Addr]Write address ready.
  //Test Interface 
  input               I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  input               I_T_A_Wr_En     ; //(I)[Clk Axi ] 测试ABUS写允许
  input  [ABW-1:0]    I_T_A_Wr_D      ; //(I)[Clk Axi ] 测试ABUS写数据
  output              O_T_A_Ready     ; //(O)[Clk Axi ] 测试ABUS忙，不能接收指令
  //DDR Controller Sigan  
  input               I_Axi_Op_Pause  ; //(I)[Clk_Axi ] Axi 地址总线操作暂停   
  output              O_Axi_A_WrEn    ; //(O)[Clk_Axi ] AXI 地址总线写允许(AXI时钟域)  
  input               I_A_Addr_RdEn   ; //(I)[Clk_Core] DDR 地址总线取地址允许
  output  [   15:0]   O_A_Addr_Num    ; //(O)[Clk_Core] ABus地址个数
  output              O_A_Addr_Empty  ; //(O)[Clk_Core] ABus地址空      
  output              O_A_Addr_Last   ; //(O)[Clk_Core] ABus最后一个地址
  output  [   31:0]   O_A_Ddr_Addr    ; //(O)[Clk_Core] DDR 地址总线读写地址 
  output              O_A_Burst_RdEn  ; //(O)[Clk_Core] ABus参数读允许   
  output              O_A_Burst_Last  ; //(O)[Clk_Core] DDR 地址总线当前Burst最后一个操作
  output  [ABW-1:0]   O_A_Next_Param  ; //(O)[Clk_Core] ABus的下一个参数
  output  [ABW  :0]   O_A_Curr_Param  ; //(O)[Clk_Core] ABus当前参数
  output  [    3:0]   O_A_Err_Flag    ; //(O)[Clk_Core] ABus的错误标志
                                        //[0] : 地址满写      [1] : 地址空读     
                                        //[2] : 参数缓存满写  [3] : 参数缓存空读 
  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire    [AIW-1:0]   Axi_A_ID        = I_A_ID        ; //(I)[Addr]Write address ID.
  wire    [   31:0]   Axi_A_ADDR      = I_A_ADDR      ; //(I)[Addr]Write address.
  wire    [    7:0]   Axi_A_LEN       = I_A_LEN       ; //(I)[Addr]Burst length.
  wire    [    2:0]   Axi_A_SIZE      = I_A_SIZE      ; //(I)[Addr]Burst size.
  wire    [    1:0]   Axi_A_BURST     = I_A_BURST     ; //(I)[Addr]Burst type.
  wire    [    1:0]   Axi_A_LOCK      = I_A_LOCK      ; //(I)[Addr]Lock type.
  wire                Axi_A_VALID     = I_A_VALID     ; //(I)[Addr]Write address valid.

  wire                Test_Mode       = I_Test_Mode   ; //(I)[Clk_Axi ] 测试模式，高有效
  wire                Test_A_WrEn     = I_T_A_Wr_En   ; //(I)[Clk Axi ] 测试ABUS写允许
  wire    [ABW-1:0]   Test_A_WrD      = I_T_A_Wr_D    ; //(I)[Clk Axi ] 测试ABUS写数据

  wire                Axi_Op_Pause    = I_Axi_Op_Pause; //Axi 地址总线操作暂停
  wire                Ddr_ABus_RdEn   = I_A_Addr_RdEn ; //DDR 取地址允许

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
////////////////   Ddr_Addr_Bus_Control   /////////////////
//111111111111111111111111111111111111111111111111111111111
//处理Axi_Clk时钟域的信号并处理和Axi总线信号的交互信号
//Axi_ABus_Wr_Req     Axi产生写请求；Sys采集该信号的上升沿并进行写操作
//Ddr_ABus_Busy       SysClk域收到写请求，置位Busy;在确认AxiClk收到Busy后，根据情况释放Busy；
//                    AxiClk收到Busy由高向低跳变，回复接收数据状态（ Axi_A_READY 置高）
//Axi_ABus_Busy_Ack   AxiClk收到Ddr_ABus_Busy的确认信号
//********************************************************/
  /////////////////////////////////////////////////////////
  //跨时钟域取 Ddr_ABus_Busy 的上升沿和下降沿
  reg           Ddr_ABus_Busy       = 1'h0  ; //DDR地址总线忙，这个信号时系统时钟域
  reg   [1:0]   Ddr_Abus_Busy_Reg   = 2'h0  ; //
  
  always  @(posedge Clk_Axi)  Ddr_Abus_Busy_Reg   <=  { Ddr_Abus_Busy_Reg[0]  , Ddr_ABus_Busy } ;

  wire  Ddr_Abus_Busy_Rise  =  ( Ddr_Abus_Busy_Reg     ==  2'h1 ) ;
  wire  Ddr_Abus_Busy_Fall  =  ( Ddr_Abus_Busy_Reg     ==  2'h2 ) ;

  /////////////////////////////////////////////////////////
  reg     Test_Mode_Reg   = 1'h0  ;
  
  always  @(posedge Clk_Axi)  Test_Mode_Reg <=  Test_Mode ;

  /////////////////////////////////////////////////////////
  wire    Axi_ABus_Pause  ;

  assign  Axi_ABus_Pause  =  Axi_Op_Pause & ( ~Axi_A_VALID  ) ;

  /////////////////////////////////////////////////////////
  //ABus的数据有效 (Axi_ABus_WrEn)  Axi_A_READY 等待ABus数据写入缓存再接收下一个数据；
  //缓存的状态通过 Ddr_ABus_Busy 进行交互 ； 
  //Ddr_ABus_Busy 由低变高， ABus暂停接收数据 （ Axi_A_READY 置低）
  reg   Axi_A_READY     = 1'h0  ;

  wire  Axi_ABus_WrEn   = Test_Mode ? Test_A_WrEn : (Axi_A_READY & Axi_A_VALID) ;

  always  @(posedge Clk_Axi)  
  begin
    if (Rst_Axi )                   Axi_A_READY  <=  1'h1  ;
    // else if (Test_Mode )            Axi_A_READY  <=  1'h0  ;
    // else if (Test_Mode_Reg)         Axi_A_READY  <=  1'h1  ;    
    else if (Axi_ABus_WrEn)         Axi_A_READY  <=  1'h0  ;  
    else if (Axi_ABus_Pause)        Axi_A_READY  <=  1'h0  ;
    else if (Ddr_Abus_Busy_Fall)    Axi_A_READY  <=  1'h1  ;
    else if (Ddr_Abus_Busy_Rise)    Axi_A_READY  <=  1'h0  ;
  end

  /////////////////////////////////////////////////////////
  //Axi_Clk和Sys_Clk 两个时钟域通过以下信号交互：
  //Axi_ABus_Wr_Req     Axi产生写请求；Sys采集该信号的上升沿并进行写操作
  //Ddr_ABus_Busy       SysClk域收到写请求，置位Busy;在确认AxiClk收到Busy后，根据情况释放Busy；
  //                    AxiClk收到Busy由高向低跳变，回复接收数据状态（ Axi_A_READY 置高）
  //Axi_ABus_Busy_Ack   AxiClk收到Ddr_ABus_Busy的确认信号
  reg   Axi_ABus_Wr_Req     = 1'h0  ;
  
  always  @(posedge Clk_Axi)  
  begin
    if (Rst_Axi )                 Axi_ABus_Wr_Req   <=  1'h0  ;
    else if (Axi_ABus_WrEn)       Axi_ABus_Wr_Req   <=  1'h1  ;
    else if (Ddr_Abus_Busy_Fall)  Axi_ABus_Wr_Req   <=  1'h0  ;
  end
  wire  Axi_ABus_Busy_Ack   = Ddr_Abus_Busy_Reg[0]  ;
  
  /////////////////////////////////////////////////////////
  reg   [ABW-1:0]   Axi_Abus_Wr_Data  = {ABW+1{1'h0}} ;
  
  always  @(posedge Clk_Axi)  if (Axi_ABus_WrEn)
  begin
    if (Test_Mode)  Axi_Abus_Wr_Data  <=  Test_A_WrD    ;
    else            Axi_Abus_Wr_Data  <=  { Axi_A_SIZE  ,
                                            Axi_A_ID    ,  
                                            Axi_A_LEN   ,
                                            Axi_A_ADDR  } ;
  end

  /////////////////////////////////////////////////////////
  reg   Test_A_Ready  = 1'h0  ;

  always  @(posedge Clk_Axi)  
  begin
    if (Rst_Axi )                 Test_A_Ready  <=  1'h0  ;
    else if (~Test_Mode )         Test_A_Ready  <=  1'h0  ;
    else if (Axi_ABus_WrEn)       Test_A_Ready  <=  1'h0  ;
    else if (Ddr_Abus_Busy_Fall)  Test_A_Ready  <=  1'h1  ;
    else if (Ddr_Abus_Busy_Rise)  Test_A_Ready  <=  1'h0  ;
  end

  /////////////////////////////////////////////////////////
  wire    O_A_READY     = Axi_A_READY   ; //(O)[Addr]Write address ready.
  wire    O_Axi_A_WrEn  = Axi_ABus_WrEn ; //(O)AXI 地址总线写允许(AXI时钟域)
  wire    O_T_A_Ready   = Axi_A_READY ;//Test_A_Ready  ; //(O)[Clk Axi ] 测试ABUS缓存写满
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
////////////////   Ddr_Addr_Bus_Control   /////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]   ABus_Wr_Req_Reg   = 2'h0  ;
  reg           ABus_Buff_Wr_En   = 1'h0  ; //(I) Write Enable

  wire  ABus_Wr_Req_Rise  = ( ABus_Wr_Req_Reg == 2'h1   ) ;
  always  @(posedge Clk_Core) ABus_Wr_Req_Reg <=  { ABus_Wr_Req_Reg[0]  , Axi_ABus_Wr_Req } ;
  always  @(posedge Clk_Core) ABus_Buff_Wr_En <=    ABus_Wr_Req_Rise    ;

  ///////////////////////////////////////////////////////// 
  wire              ABus_Param_WrEn  = ABus_Buff_Wr_En   ; //(I)ABus参数写允许        
  wire  [ABW-1:0]   ABus_Paramter    = Axi_Abus_Wr_Data  ; //(I)ABus参数(SIZE/ID/LEN/DATA)
  wire  [ABS  :0]   ABus_Param_Num   ; //(O)ABus参数缓存数量         
  wire              ABus_Param_Empty ; //(O)ABus参数缓存空  
  wire              ABus_Param_Last  ; //(O)ABus参数缓存最后一个参数
  wire              ABus_Burst_RdEn  ; //(O)
  wire  [   15:0]   ABus_Addr_Num    ; //(O)ABus地址个数
  wire              ABus_Addr_Full   ; //(O)ABus地址个数大于最大地址队列个数( ADDR_QUEUE_NUM )
  wire              ABus_Addr_Empty  ; //(O)ABus地址空      
  wire              ABus_Addr_Last   ; //(O)ABus最后一个地址
  wire              ABus_Addr_RdEn   = Ddr_ABus_RdEn     ; //(I)读地址允许       
  wire  [   31:0]   ABus_Address     ; //(O)地址输出
  wire              ABus_Burst_Last  ; //(O)Burst最后一个地址
  wire  [ABW-1:0]   ABus_Next_Param  ; //(O)ABus的下一个参数
  wire  [ABW  :0]   ABus_Curr_Param  ; //(O)ABus当前参数+新参数标志
  wire  [    3:0]   ABus_Err_Flag    ; //(O)ABus的错误标志
                                     //[0] : 地址满写      [1] : 地址空读     
                                     //[2] : 参数缓存满写  [3] : 参数缓存空读 

  defparam  U2_Ddr_Addr_Generater.AXI_ID_WIDTH    = AXI_ID_WIDTH    ; //AXI4总线ID的宽度
  defparam  U2_Ddr_Addr_Generater.AXI_DATA_WIDTH  = AXI_DATA_WIDTH  ; //AXI4总线数据的宽度
  defparam  U2_Ddr_Addr_Generater.DDR_DATA_WIDTH  = DDR_DATA_WIDTH  ; //DDR总线数据的宽度
  defparam  U2_Ddr_Addr_Generater.ADDR_QUEUE_NUM  = ADDR_QUEUE_NUM  ; //最大地址队列个数
  defparam  U2_Ddr_Addr_Generater.BURST_QUEUE_NUM = BURST_QUEUE_NUM ; //最大突发队列个数

  Ddr_Addr_Generater  U2_Ddr_Addr_Generater
  (
    .Sys_Clk          ( Clk_Core          ) , //Clock Core
    .I_Sync_Clr       ( Rst_Core          ) , //Sync Reset
    .I_A_Param_WrEn   ( ABus_Param_WrEn   ) , //(I)ABus Parameter Write Enable           
    .I_A_Paramter     ( ABus_Paramter     ) , //(I)ABus Parameter(SIZE/ID/LEN/DATA)
    .O_A_Param_Num    ( ABus_Param_Num    ) , //(O)ABus Param Full                 
    .O_A_Param_Empty  ( ABus_Param_Empty  ) , //(O)ABus Param Empty        
    .O_A_Param_Last   ( ABus_Param_Last   ) , //(O)ABus Param Last  
    .O_A_Addr_Num     ( ABus_Addr_Num     ) , //(O)ABus Address Full         
    .O_A_Addr_Full    ( ABus_Addr_Full    ) , //(O)ABus Address Number        
    .O_A_Addr_Empty   ( ABus_Addr_Empty   ) , //(O)ABus Address Empty        
    .O_A_Addr_Last    ( ABus_Addr_Last    ) , //(O)ABus Address Last
    .I_A_Addr_RdEn    ( ABus_Addr_RdEn    ) , //(I)ABus Address Read Enable           
    .O_A_Address      ( ABus_Address      ) , //(O)ABus Address Output       
    .O_A_Burst_RdEn   ( ABus_Burst_RdEn   ) , //(O)ABus Parameter Read Enable  
    .O_A_Burst_Last   ( ABus_Burst_Last   ) , //(O)ABus Burst Last
    .O_A_Next_Param   ( ABus_Next_Param   ) , //(O)ABus Error Flag
    .O_A_Curr_Param   ( ABus_Curr_Param   ) , //(O)ABus Next Parameter     
    .O_A_Err_Flag     ( ABus_Err_Flag     )   //(O)ABus Current Parameter
  );  

  ///////////////////////////////////////////////////////// 
  always  @(posedge Clk_Core) 
  begin
    if (Rst_Core)                 Ddr_ABus_Busy   <=  1'h1  ;
    else if (ABus_Wr_Req_Rise)    Ddr_ABus_Busy   <=  1'h1  ;
    else if (Axi_ABus_Busy_Ack == Ddr_ABus_Busy)              
    begin
      Ddr_ABus_Busy   <=  ABus_Addr_Full  | Axi_ABus_Pause  ;
    end
  end
 
  /////////////////////////////////////////////////////////
  wire  [31:0]  Ddr_Address  = {{DDS{1'h0}}  , ABus_Address[31:DDS]} ;

  /////////////////////////////////////////////////////////
  wire  [   31:0]   O_A_Ddr_Addr    = Ddr_Address     ; //(O)DDR 地址总线读写地址 
  wire  [   15:0]   O_A_Addr_Num    = ABus_Addr_Num   ; //(O)ABus地址个数
  wire              O_A_Addr_Empty  = ABus_Addr_Empty ; //(O)ABus地址空      
  wire              O_A_Addr_Last   = ABus_Addr_Last  ; //(O)ABus最后一个地址
  wire              O_A_Burst_RdEn  = ABus_Burst_RdEn ; //(O)ABus参数读允许   
  wire              O_A_Burst_Last  = ABus_Burst_Last ; //(O)DDR 地址总线最后一个操作
  wire  [ABW-1:0]   O_A_Next_Param  = ABus_Next_Param ; //(O)ABus的下一个参数
  wire  [ABW  :0]   O_A_Curr_Param  = ABus_Curr_Param ; //(O)ABus当前参数
  wire  [    3:0]   O_A_Err_Flag    = ABus_Err_Flag   ; //(O)ABus的错误标志
//222222222222222222222222222222222222222222222222222222222
////////////////   Ddr_Addr_Bus_Control   /////////////////

endmodule

////////////////   Ddr_Addr_Bus_Control   /////////////////






///////////////////   Ddr_Wr_Data_Ctrl  ///////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2021-03-01
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Wr_Data_Ctrl
(  
  input           Clk_TxDq        , //(I)Tx Dq Clock
  input           Rst_TxDq        , //(I)Tx DQ Reset
  input   [2:0]   Cfg_WrD_Dly     , //(I)Config Write Data Delay
  input   [1:0]   I_Ddr_Cs_In     , //(I)DDR CS Capture By Clk_TxDq
  input           I_Phy_Cmd_Write , //(I)Command Write 
  input           I_Phy_Cmd_Valid , //(I)Command Valid 
  output          O_Fifo_Rd_En      //(O)Write Fifo Read Enable
);

///////////////////   Ddr_Wr_Data_Ctrl  ///////////////////
//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire   [    2:0]  Conf_WrD_Dly  = Cfg_WrD_Dly     ; //(I)Config Write Data Delay
  wire   [    1:0]  Ddr_Cs_In     = I_Ddr_Cs_In     ; //(I)DDR CS Capture By Clk_TxDq
  wire              Phy_Cmd_Write = I_Phy_Cmd_Write ; //(I)Command Write 
  wire              Phy_Cmd_Valid = I_Phy_Cmd_Valid ; //(I)Command Valid 
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
///////////////////   Ddr_Wr_Data_Ctrl  ///////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]   Cmd_Write_Reg   = 2'h0  ;

  always  @(posedge Clk_TxDq)    Cmd_Write_Reg  <=  { Cmd_Write_Reg[0]  , Phy_Cmd_Write } ;
  wire      Cmd_Write_Rise  =  ( Cmd_Write_Reg  ==  2'h1  ) ;

  /////////////////////////////////////////////////////////
  reg           Write_Ready   = 1'h0  ;
  
  always  @(posedge Clk_TxDq)  
  begin
    if (Rst_TxDq)               Write_Ready  <=  1'h0  ;
    else if (~&Ddr_Cs_In)       Write_Ready  <=  1'h0  ;
    else if (Cmd_Write_Rise)    Write_Ready  <=  1'h1  ;
  end  

  wire  Write_Start   =  (~&Ddr_Cs_In) & ( Write_Ready | Cmd_Write_Rise ) ;  

  /////////////////////////////////////////////////////////
  reg   [7:0]   Fifo_Rd_Sft   = 8'h0  ;
  
  always  @(posedge Clk_TxDq) 
  begin
    Fifo_Rd_Sft[0]  <=  (Conf_WrD_Dly ==  3'h0) ? Write_Start : Fifo_Rd_Sft[1]  ;
    Fifo_Rd_Sft[1]  <=  (Conf_WrD_Dly ==  3'h1) ? Write_Start : Fifo_Rd_Sft[2]  ;
    Fifo_Rd_Sft[2]  <=  (Conf_WrD_Dly ==  3'h2) ? Write_Start : Fifo_Rd_Sft[3]  ;
    Fifo_Rd_Sft[3]  <=  (Conf_WrD_Dly ==  3'h3) ? Write_Start : Fifo_Rd_Sft[4]  ;
    Fifo_Rd_Sft[4]  <=  (Conf_WrD_Dly ==  3'h4) ? Write_Start : Fifo_Rd_Sft[5]  ;
    Fifo_Rd_Sft[5]  <=  (Conf_WrD_Dly ==  3'h5) ? Write_Start : Fifo_Rd_Sft[6]  ;
    Fifo_Rd_Sft[6]  <=  (Conf_WrD_Dly ==  3'h6) ? Write_Start : Fifo_Rd_Sft[7]  ;
    Fifo_Rd_Sft[7]  <=  (Conf_WrD_Dly ==  3'h7) ? Write_Start : 1'h0            ;
  end

  wire    Fifo_Rd_En    = Fifo_Rd_Sft[0]  ;
  
  /////////////////////////////////////////////////////////
  assign  O_Fifo_Rd_En  = Fifo_Rd_En      ; //(O)Write Fifo Read Enable
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
///////////////////   Ddr_Wr_Data_Ctrl  ///////////////////

endmodule

///////////////////////////////////////////////////////////








/////////////////////   Ddr_Wr_Dqs   //////////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2023-07-26
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Wr_Dqs
(
  input           Sys_Clk         , //System Clock
  input           I_Sync_Clr      , //Sync Reset
  input   [2:0]   Cfg_Dqs_Delay   , //(I)Config Tx Dqs Delay
  input           I_Phy_Cmd_Write , //(I)Command Write 
  input           I_WrLevel_En    , //(I)Write Leveling Enable  
  output          O_Ddr_Dqs_Last  , //(O)DDR Dqs Last
  output  [1:0]   O_Ddr_Dqs_Out   , //(O)DDR DQS Output
  output          O_Ddr_Dqs_OE      //(O)DDR DQS Output Enable
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
/////////////////////   Ddr_Wr_Dqs   //////////////////////
//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire          Sync_Clr        =   I_Sync_Clr    ; //Sync Reset
  wire          Sys_Rst_N       = ~ I_Sync_Clr    ; //Sync Reset
  wire          Phy_Cmd_Write   = I_Phy_Cmd_Write ; //(I)Command Write 
  wire          Wr_Level_En     = I_WrLevel_En    ; //(I)Write Leveling Enable  
  /////////////////////////////////////////////////////////
  wire  [2:0]   Conf_Dqs_Dly    = Cfg_Dqs_Delay   ; //Config Write Latency
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
/////////////////////   Ddr_Wr_Dqs   //////////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]   Cmd_Write_Reg = 2'h0  ;

  always  @(posedge Sys_Clk)  Cmd_Write_Reg <=  { Cmd_Write_Reg[0]  , Phy_Cmd_Write } ;
  
  wire  Write_Start   = ( Cmd_Write_Reg     ==  2'h1  ) ;

  /////////////////////////////////////////////////////////
  reg   [2:0]     Wr_Burst_Cnt  = 3'h0  ;
  wire            Dqs_Last_En   ;

  always @(posedge Sys_Clk) 
  begin
    if (Sync_Clr)           Wr_Burst_Cnt  <=  3'h0  ;
    else if ( Write_Start ^ Dqs_Last_En )
    begin
      if (Write_Start)      Wr_Burst_Cnt  <=  Wr_Burst_Cnt - 3'h1 ;
      else if (Dqs_Last_En) Wr_Burst_Cnt  <=  Wr_Burst_Cnt + 3'h1 ;
    end
  end
  wire    Write_State   = Wr_Burst_Cnt[2] ;

  /////////////////////////////////////////////////////////
  reg   [7:0]   Dqs_Start_Sft = 8'h0  ;
  
  always  @(posedge Sys_Clk) 
  begin
    Dqs_Start_Sft[0]  <=  (Conf_Dqs_Dly ==  3'h0) ? Write_Start : Dqs_Start_Sft[1]  ;
    Dqs_Start_Sft[1]  <=  (Conf_Dqs_Dly ==  3'h1) ? Write_Start : Dqs_Start_Sft[2]  ;
    Dqs_Start_Sft[2]  <=  (Conf_Dqs_Dly ==  3'h2) ? Write_Start : Dqs_Start_Sft[3]  ;
    Dqs_Start_Sft[3]  <=  (Conf_Dqs_Dly ==  3'h3) ? Write_Start : Dqs_Start_Sft[4]  ;
    Dqs_Start_Sft[4]  <=  (Conf_Dqs_Dly ==  3'h4) ? Write_Start : Dqs_Start_Sft[5]  ;
    Dqs_Start_Sft[5]  <=  (Conf_Dqs_Dly ==  3'h5) ? Write_Start : Dqs_Start_Sft[6]  ;
    Dqs_Start_Sft[6]  <=  (Conf_Dqs_Dly ==  3'h6) ? Write_Start : Dqs_Start_Sft[7]  ;
    Dqs_Start_Sft[7]  <=  (Conf_Dqs_Dly ==  3'h7) ? Write_Start : 1'h0              ;
  end

  wire    Dqs_Start_En  = Dqs_Start_Sft[0]  ;

  /////////////////////////////////////////////////////////
  wire  [2:0]   Conf_Dqs_Len  = 4'h3  ;

  defparam  U1_Dqs_End_Dly.DATA_WIDTH     = 1 ;
  defparam  U1_Dqs_End_Dly.DELAY_LEN_MAX  = 8 ;

  Delay_Use_SRL8  U1_Dqs_End_Dly
  (
    .Sys_Clk      ( Sys_Clk           ) , //System Clock
    .Sys_Rst_N    ( Sys_Rst_N         ) , //System Reset
    .I_Data_En    ( 1'h1              ) , //(I)Data Enable
    .I_Data_In    ( Dqs_Start_En      ) , //(I)Data Input
    .I_Dly_Len    ( Conf_Dqs_Len      ) , //(I)Delay Length
    .O_Shift_Out  (                   ) , //(O)Shift Output
    .O_Data_Out   ( Dqs_Last_En       )   //(O)Data Output
  );

  /////////////////////////////////////////////////////////
  reg   [5:0]   WrLevel_Inv_Cnt   = 6'h0  ;
  reg           WrLevel_En_Reg    = 6'h0  ;

  always @(posedge Sys_Clk)   WrLevel_En_Reg  <=  Wr_Level_En ;
  always @(posedge Sys_Clk)   
  begin
    if (~Wr_Level_En)               WrLevel_Inv_Cnt <=  6'h0  ;
    else if ( WrLevel_Inv_Cnt[5])   WrLevel_Inv_Cnt <=  6'h0  ;
    else     WrLevel_Inv_Cnt    <=  WrLevel_Inv_Cnt   + 6'h1  ;
  end

  wire    WrLvl_Dqs_Val   = WrLevel_Inv_Cnt[5]  ;

  /////////////////////////////////////////////////////////
  reg   Dqs_Last_Reg  = 1'h0 ;
  reg   Ddr_Dqs_OE    = 1'h0 ;  //DDR DQS Output Enable

  always @(posedge Sys_Clk)   Dqs_Last_Reg  <=  Dqs_Last_En  ;
  always @(posedge Sys_Clk)
  begin
    if (Sync_Clr)             Ddr_Dqs_OE  <=  1'h0        ;
    else if (Wr_Level_En)     Ddr_Dqs_OE  <=  1'h1        ;
    else if (WrLevel_En_Reg)  Ddr_Dqs_OE  <=  1'h0        ;
    else if (Dqs_Start_En)    Ddr_Dqs_OE  <=  1'h1        ;
    else if (Dqs_Last_Reg)    Ddr_Dqs_OE  <=  Write_State ;
  end

  /////////////////////////////////////////////////////////
  reg   [1:0]   Ddr_Dqs_Out = 2'h0  ;

  always @(posedge Sys_Clk) 
  begin
    if  (Wr_Level_En)   Ddr_Dqs_Out <=  WrLvl_Dqs_Val ? 2'h2  : 2'h0  ;
    else                Ddr_Dqs_Out <=  2'h2          ;
  end

  /////////////////////////////////////////////////////////
  reg   Ddr_Dqs_Last  = 1'h0 ;  //DDR Dqs Last

  always @(posedge Sys_Clk)   Ddr_Dqs_Last  <=  Dqs_Last_En & (~Write_State)  ;

  /////////////////////////////////////////////////////////
  assign  O_Ddr_Dqs_Last  = Ddr_Dqs_Last  ; //(O)DDR Dqs Last
  assign  O_Ddr_Dqs_Out   = Ddr_Dqs_Out   ; //(O)DDR DQS Output
  assign  O_Ddr_Dqs_OE    = Ddr_Dqs_OE    ; //(O)DDR DQS Output Enable
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

endmodule

/////////////////////   Ddr_Wr_Dqs   //////////////////////








////////////////////    Ddr_Odt_Ctrl    ///////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2023-07-26
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Odt_Ctrl
(
  input           Sys_Clk         , //System Clock
  input           I_Sync_Clr      , //Sync Reset
  input   [2:0]   Cfg_Odt_Delay   , //(I)Config ODT Delay
  input           I_Phy_Cmd_Write , //(I)Command Write 
  input           I_WrLevel_En    , //(I)Write Leveling Enable  
  output          O_Ddr_Odt_Last  , //(O)DDR Odt Last
  output          O_Ddr_Odt_Out     //(O)DDR ODT Output
);

  //Define  Parameter
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////

////////////////////    Ddr_Odt_Ctrl    ///////////////////
//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire          Sync_Clr        =   I_Sync_Clr    ; //Sync Reset
  wire          Sys_Rst_N       = ~ I_Sync_Clr    ; //Sync Reset
  wire          Phy_Cmd_Write   = I_Phy_Cmd_Write ; //(I)Command Write 
  wire          Wr_Level_En     = I_WrLevel_En    ; //(I)写均衡（Write Leveling）允许 
  /////////////////////////////////////////////////////////
  wire  [2:0]   Conf_Odt_Dly    = Cfg_Odt_Delay   ; //Config Write Latency

//000000000000000000000000000000000000000000000000000000000
////////////////////    Ddr_Odt_Ctrl    ///////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]   Cmd_Write_Reg = 2'h0  ;

  always  @(posedge Sys_Clk)  Cmd_Write_Reg <=  { Cmd_Write_Reg[0]  , Phy_Cmd_Write } ;
  
  wire  Write_Start   = ( Cmd_Write_Reg[0]  & Phy_Cmd_Write ) ;

  /////////////////////////////////////////////////////////
  reg   [2:0]     Wr_Burst_Cnt  = 3'h0  ;
  wire            Odt_Last_En   ;

  always @(posedge Sys_Clk) 
  begin
    if (Sync_Clr)           Wr_Burst_Cnt  <=  3'h0  ;
    else if ( Write_Start ^ Odt_Last_En )
    begin
      if (Write_Start)      Wr_Burst_Cnt  <=  Wr_Burst_Cnt - 3'h1 ;
      else if (Odt_Last_En) Wr_Burst_Cnt  <=  Wr_Burst_Cnt + 3'h1 ;
    end
  end
  wire    Write_State   = Wr_Burst_Cnt[2] ;

  /////////////////////////////////////////////////////////
  defparam  U1_Dqs_Start_Dly.DATA_WIDTH     = 1   ;
  defparam  U1_Dqs_Start_Dly.DELAY_LEN_MAX  = 8   ;

  Delay_Use_SRL8  U1_Dqs_Start_Dly
  (
    .Sys_Clk      ( Sys_Clk       ) , //System Clock
    .Sys_Rst_N    ( Sys_Rst_N     ) , //System Reset
    .I_Data_En    ( 1'h1          ) , //(I)Data Enable
    .I_Data_In    ( Write_Start   ) , //(I)Data Input
    .I_Dly_Len    ( Conf_Odt_Dly  ) , //(I)Delay Length
    .O_Shift_Out  (               ) , //(O)Shift Output
    .O_Data_Out   ( Odt_Last_En   )   //(O)Data Output
  );

  /////////////////////////////////////////////////////////
  reg   [4:0]   WrLevel_Inv_Cnt   = 5'h0  ;
  reg   [4:0]   WrLevel_En_Reg    = 5'h0  ;

  always @(posedge Sys_Clk)   WrLevel_En_Reg  <=  Wr_Level_En ;
  always @(posedge Sys_Clk)   
  begin
    if (~Wr_Level_En)               WrLevel_Inv_Cnt <=  5'h0  ;
    else if (~WrLevel_Inv_Cnt[4])   WrLevel_Inv_Cnt <=  WrLevel_Inv_Cnt + 5'h1  ;
  end

  wire    WrLevel_Odt_En  = WrLevel_Inv_Cnt[4]  ;

  /////////////////////////////////////////////////////////
  reg     Odt_Last_Reg  = 1'h0  ;
  reg     Ddr_Odt_Out   = 1'h0  ;

  always @(posedge Sys_Clk)  Odt_Last_Reg   <=  Odt_Last_En  ;
  always @(posedge Sys_Clk)
  begin
    if (Sync_Clr)             Ddr_Odt_Out <=  1'h0  ;
    else if (Wr_Level_En)     Ddr_Odt_Out <=  WrLevel_Odt_En  ;
    else if (WrLevel_En_Reg)  Ddr_Odt_Out <=  1'h0  ;
    else if (Write_Start)     Ddr_Odt_Out <=  1'h1  ;
    else if (Odt_Last_Reg)    Ddr_Odt_Out <=  Write_State ;
  end

  /////////////////////////////////////////////////////////
  reg   Ddr_Odt_Last  = 1'h0 ;  //DDR Odt Last

  always @(posedge Sys_Clk)   Ddr_Odt_Last  <=  Odt_Last_En & (~Write_State)  ;

  /////////////////////////////////////////////////////////
  assign  O_Ddr_Odt_Last  = Ddr_Odt_Last  ; //(O)DDR Odt Last
  assign  O_Ddr_Odt_Out   = Ddr_Odt_Out   ; //(O)DDR ODT Output
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
////////////////////    Ddr_Odt_Ctrl    ///////////////////
endmodule

////////////////////    Ddr_Odt_Ctrl    ///////////////////
















/////////////////    Ddr_Addr_Generater   /////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2023-08-10
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Addr_Generater
(
  Sys_Clk         , //Clock Core
  I_Sync_Clr      , //Sync Reset
  I_A_Param_WrEn  , //(I)ABus Parameter Write Enable           
  I_A_Paramter    , //(I)ABus Parameter(SIZE/ID/LEN/DATA)
  O_A_Param_Num   , //(O)ABus Param Number In Buffer            
  O_A_Param_Empty , //(O)ABus Param Empty        
  O_A_Param_Last  , //(O)ABus Param Last  
  O_A_Addr_Num    , //(O)ABus Address Number     
  O_A_Addr_Full   , //(O)ABus Address Full        
  O_A_Addr_Empty  , //(O)ABus Address Empty        
  O_A_Addr_Last   , //(O)ABus Address Last
  I_A_Addr_RdEn   , //(I)ABus Address Read Enable           
  O_A_Address     , //(O)ABus Address Output       
  O_A_Burst_RdEn  , //(O)ABus Parameter Read Enable      
  O_A_Burst_Last  , //(O)ABus Burst Last
  O_A_Next_Param  , //(O)ABus Next Parameter     
  O_A_Curr_Param  , //(O)ABus Current Parameter
  O_A_Err_Flag      //(O)ABus Error Flag
);  

  //Define  Parameter
  /////////////////////////////////////////////////////////  
  parameter   AXI_ID_WIDTH      = 8   ; //AXI4总线ID的宽度
  parameter   AXI_DATA_WIDTH    = 128 ; //AXI4总线数据的宽度
  parameter   DDR_DATA_WIDTH    = 16  ; //DDR总线数据的宽度
  parameter   ADDR_QUEUE_NUM    = 512 ; //最大地址队列个数
  parameter   BURST_QUEUE_NUM   = 16  ; //最大突发队列个数

  localparam  AXI_BYTE_NUMBER       = AXI_DATA_WIDTH  / 8       ; //AXI4数据总线字节个数
  localparam  AXI_BYTE_SIZE         = $clog2(AXI_BYTE_NUMBER)   ; //AXI4数据尺寸，即为字节计数器宽度

  localparam  DDR_BYTE_NUMBER       = DDR_DATA_WIDTH  / 8       ; //DDR数据总线字节个数
  localparam  DDR_BYTE_SIZE         = $clog2(DDR_BYTE_NUMBER)   ; //DDR数据尺寸，即为字节计数器宽度

  localparam  ADDR_BUFF_DATA_WIDTH  = AXI_ID_WIDTH + 32 + 3 + 8 ; //地址缓存的数据宽度
  localparam  ADDR_BUFF_ADDR_SIZE   = $clog2(BURST_QUEUE_NUM ) ; //地址缓存的地址尺寸

  localparam  ADDR_MAX_NUM      = (4096 * BURST_QUEUE_NUM)  / AXI_BYTE_NUMBER / 2 ; //地址队列最大值，设置为突发队列的50%
  localparam  ADDR_QUEUE_SIZE   = $clog2(ADDR_MAX_NUM)  + 1 ; //地址队列计数器的宽度

  localparam  ADDR_QUEUE_VALID  = (ADDR_QUEUE_NUM - ADDR_MAX_NUM) > 0 ;

  /////////////////
  localparam  AIW   = AXI_ID_WIDTH          ; //AXI总线ID的宽度
  localparam  DDS   = DDR_BYTE_SIZE         ; //DDR数据尺寸，即为字节计数器宽度
  localparam  ABS   = ADDR_BUFF_ADDR_SIZE   ; //地址缓存的地址尺寸
  localparam  ABW   = ADDR_BUFF_DATA_WIDTH  ; //地址缓存的数据宽度

  localparam  AQS   = ADDR_QUEUE_SIZE       ; //地址队列计数器的宽度
  /////////////////////////////////////////////////////////
  // Port Define
  /////////////////////////////////////////////////////////
  //System Signal
  input               Sys_Clk         ; //System Clock
  input               I_Sync_Clr      ; //Sync Reset

  input               I_A_Param_WrEn  ; //(I)ABus参数写允许        
  input   [ABW-1:0]   I_A_Paramter    ; //(I)ABus参数(SIZE/ID/LEN/DATA)
  output  [ABS  :0]   O_A_Param_Num   ; //(O)ABus参数缓存数量(Sim)         
  output              O_A_Param_Empty ; //(O)ABus参数缓存空 (Sim)
  output              O_A_Param_Last  ; //(O)ABus参数缓存最后一个参数(Sim)
  output  [   15:0]   O_A_Addr_Num    ; //(O)ABus地址个数
  output              O_A_Addr_Full   ; //(O)ABus地址个数大于最大地址队列个数(Sim)
  output              O_A_Addr_Empty  ; //(O)ABus地址空      
  output              O_A_Addr_Last   ; //(O)ABus最后一个地址
  input               I_A_Addr_RdEn   ; //(I)读地址允许       
  output  [   31:0]   O_A_Address     ; //(O)地址输出
  output              O_A_Burst_RdEn  ; //(O)ABus参数读允许   
  output              O_A_Burst_Last  ; //(O)Burst最后一个地址
  output  [ABW-1:0]   O_A_Next_Param  ; //(O)ABus的下一个参数
  output  [ABW  :0]   O_A_Curr_Param  ; //(O)ABus当前参数
  output  [    3:0]   O_A_Err_Flag    ; //(O)ABus的错误标志
                                        //[0] : 地址满写      [1] : 地址空读     
                                        //[2] : 参数缓存满写  [3] : 参数缓存空读 
  /////////////////////////////////////////////////////////
/////////////////    Ddr_Addr_Generater   /////////////////
//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              Sync_Clr          = I_Sync_Clr      ; //Sync Reset
  wire              ABus_Param_WrEn   = I_A_Param_WrEn  ; //(I)ABus参数写允许        
  wire  [ABW-1:0]   ABus_Parameter    = I_A_Paramter    ; //(I)ABus参数(SIZE/ID/LEN/DATA)
  wire              ABus_Addr_RdEn    = I_A_Addr_RdEn   ; //(I)读地址允许    
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
/////////////////    Ddr_Addr_Generater   /////////////////
//111111111111111111111111111111111111111111111111111111111
  /////////////////////////////////////////////////////////

  /////////////////////////////////////////////////////////
  wire              ABus_Buff_Wr_En     = ABus_Param_WrEn ;
  wire  [ABW-1:0]   ABus_Buff_Wr_Data   = ABus_Parameter  ; //(I) FIFO Write Data

  reg               ABus_Buff_Rd_En     ; //(I) FIFO Read Enable

  wire  [ABW-1:0]   ABus_Buff_Rd_Data   ; //(O) FIFO Read Data  
  wire  [ABS  :0]   ABus_Buff_Data_Num  ; //(O) Ram Data Number
  wire              ABus_Buff_Wr_Full   ; //(O) FIFO Write Full
  wire              ABus_Buff_Rd_Empty  ; //(O) FIFO Write Empty
  wire              ABus_Buff_Fifo_Err  ; //(O) FIFO Error
  
  defparam    U1_ABus_Buffer.OUT_REG     = "Yes"  ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam    U1_ABus_Buffer.DATA_WIDTH  = ADDR_BUFF_DATA_WIDTH ; //Data Width
  defparam    U1_ABus_Buffer.DATA_DEPTH  = BURST_QUEUE_NUM      ; //Address Width

  Ddr_Ctrl_Sc_Fifo  U1_ABus_Buffer
  (
    .Sys_Clk      ( Sys_Clk             ) , //System Clock
    .Sync_Clr     ( Sync_Clr            ) , //Sync Reset
    .I_Wr_En      ( ABus_Buff_Wr_En     ) , //(I) FIFO Write Enable
    .I_Wr_Data    ( ABus_Buff_Wr_Data   ) , //(I) FIFO Write Data
    .I_Rd_En      ( ABus_Buff_Rd_En     ) , //(I) FIFO Read Enable
    .O_Rd_Data    ( ABus_Buff_Rd_Data   ) , //(O) FIFO Read Data
    .O_Data_Num   ( ABus_Buff_Data_Num  ) , //(O) FIFO Data Number
    .O_Wr_Full    ( ABus_Buff_Wr_Full   ) , //(O) FIFO Write Full
    .O_Rd_Empty   ( ABus_Buff_Rd_Empty  ) , //(O) FIFO Write Empty
    .O_Fifo_Err   ( ABus_Buff_Fifo_Err  )   //(O) Fifo Error
  ) ;
  
  ///////////////////////////////////////////////////////// 
  wire   [    2:0]  Axi_A_SIZE  ;  
  wire   [AIW-1:0]  Axi_A_ID    ;  
  wire   [    7:0]  Axi_A_LEN   ;  
  wire   [   31:0]  Axi_A_ADDR  ;  

  assign  { Axi_A_SIZE  ,
            Axi_A_ID    ,
            Axi_A_LEN   ,
            Axi_A_ADDR  }   = ABus_Buff_Rd_Data ;

  ///////////////////////////////////////////////////////// 
  reg     ABus_Buff_Rd_Last   = 1'h0  ;

  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)               ABus_Buff_Rd_Last <=  1'h0  ;
    else if (ABus_Buff_Rd_En & (~ABus_Buff_Wr_En))   
    begin
      ABus_Buff_Rd_Last <=  (~|ABus_Buff_Data_Num[ABS:1]) ;
    end
  end

  ///////////////////////////////////////////////////////// 
  wire  [ABS  :0]   O_A_Param_Num     = ABus_Buff_Data_Num  ; //(O)ABus参数缓存数量         
  wire              O_A_Param_Empty   = ABus_Buff_Rd_Empty  ; //(O)ABus参数缓存空
  wire              O_A_Param_Last    = ABus_Buff_Rd_Last   ; //(O)ABus参数缓存最后一个参数
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
/////////////////    Ddr_Addr_Generater   /////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  ///////////////////////////////////////////////////////// 
  
  ///////////////////////////////////////////////////////// 
  reg   [AQS-1:0]   ABus_Addr_Cnt = {AQS{1'h0}} ;
  wire  [    7:0]   Axi_Addr_Len  = ABus_Parameter[39:32] ;
  wire  [AQS-1:0]   Burst_Num_In  = { {AQS-7{1'h0}},Axi_Addr_Len  } 
                                  + { 12'h0,~ABus_Addr_RdEn       } ;

  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)               ABus_Addr_Cnt <=  13'h0 ;
    else if (ABus_Buff_Wr_En)   ABus_Addr_Cnt <=  ABus_Addr_Cnt + Burst_Num_In  ;
    else if (ABus_Addr_RdEn)    ABus_Addr_Cnt <=  ABus_Addr_Cnt - {{AQS-1{1'h0}},1'h1};
  end
  
  wire [15:0]   ABus_Addr_Num   = {{16-AQS{1'h0}} , ABus_Addr_Cnt[AQS-1:0]} ;

  ///////////////////////////////////////////////////////// 
  reg     ABus_Addr_Full    =   1'h0  ; //ABus地址个数大于最大地址队列个数( ADDR_QUEUE_NUM )

  wire  [15:0]  Calc_Addr_Full  = ADDR_QUEUE_VALID  
                ? ( ADDR_QUEUE_NUM[15:0] - {{16-AQS{1'h0}},ABus_Addr_Num} ) : 16'h0 ;
  
  always  @(posedge Sys_Clk)  
  begin
    ABus_Addr_Full  <=  ABus_Buff_Wr_Full   | ABus_Addr_Num[AQS]  | Calc_Addr_Full[15]  ;
  end

  ///////////////////////////////////////////////////////// 
  wire  [   15:0]   O_A_Addr_Num    = ABus_Addr_Num   ; //(O)ABus地址个数（用于调试）
  wire              O_A_Addr_Full   = ABus_Addr_Full  ; //ABus地址个数大于最大地址队列个数( ADDR_QUEUE_NUM )
  ///////////////////////////////////////////////////////// 
//222222222222222222222222222222222222222222222222222222222
/////////////////    Ddr_Addr_Generater   /////////////////
//333333333333333333333333333333333333333333333333333333333
//处理读长度
//********************************************************/
  /////////////////////////////////////////////////////////
  //对空信号的检测是为了Buff从空到非空时预读数据
  reg   Buff_Rd_Empty_Reg   = 1'h0  ;
  
  always  @(posedge Sys_Clk)  Buff_Rd_Empty_Reg   <=  ABus_Buff_Rd_Empty  ;


  /////////////////////////////////////////////////////////
  reg     ABus_Data_Valid   = 1'h0  ;  
  wire    ABus_Bst_Last  ;
  
  wire    Buff_Pre_Read   = ~ABus_Buff_Rd_Empty  & Buff_Rd_Empty_Reg & (~ABus_Data_Valid) ;

  always  @( * )
  begin
    if (ABus_Data_Valid)  ABus_Buff_Rd_En   = ABus_Bst_Last & (~ABus_Buff_Rd_Empty) ;
    else                  ABus_Buff_Rd_En   = Buff_Pre_Read ;
  end    
  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)                               ABus_Data_Valid   <=  1'h0  ;
    else if (Buff_Pre_Read)                     ABus_Data_Valid   <=  1'h1  ;
    else if (ABus_Data_Valid & ABus_Bst_Last)   ABus_Data_Valid   <=  ~ABus_Buff_Rd_Empty ;
  end
  
  wire    ABus_Addr_Empty   = ~ABus_Data_Valid ;

  /////////////////////////////////////////////////////////
  reg   [8:0]   ABus_Burst_Len_Cnt  = 9'h0  ;
  reg           Buff_Pre_Rd_Reg     = 1'h0  ;
  
  always  @(posedge Sys_Clk)   Buff_Pre_Rd_Reg  <=  Buff_Pre_Read & (~ABus_Data_Valid)  ;
  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)                   ABus_Burst_Len_Cnt  <=  9'h0ff  ;
    else if (Buff_Pre_Read)         ABus_Burst_Len_Cnt  <=  {1'h0 , Axi_A_LEN  }  - 9'h1 ;
    else if (ABus_Addr_RdEn)    
    begin
      if (ABus_Burst_Len_Cnt[8])    ABus_Burst_Len_Cnt  <=  {1'h0 , Axi_A_LEN  }  - 9'h1 ;
      else                          ABus_Burst_Len_Cnt  <=  ABus_Burst_Len_Cnt    - 9'h1 ;
    end
  end

  /////////////////////////////////////////////////////////
  //产生Busrt的最后一个读
  reg           ABus_Bst_Last_Flag  = 1'h0  ;

  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)                   ABus_Bst_Last_Flag  <=  1'h0  ;
    else if (Buff_Pre_Rd_Reg)       ABus_Bst_Last_Flag  <=  ( ABus_Burst_Len_Cnt[8] ) ;
    else if (ABus_Addr_RdEn)        
    begin
      if(ABus_Burst_Len_Cnt[8])     ABus_Bst_Last_Flag  <=  (~|Axi_A_LEN  ) ;
      else                          ABus_Bst_Last_Flag  <=  (~|ABus_Burst_Len_Cnt)  ;
    end
  end

  assign    ABus_Bst_Last   = ABus_Addr_RdEn  & ABus_Bst_Last_Flag  ;
  wire      ABus_Addr_Last  = ABus_Bst_Last   & ABus_Buff_Rd_Empty  ;
  
  /////////////////////////////////////////////////////////  
  wire    O_A_Burst_RdEn  = ABus_Buff_Rd_En ; //(O)ABus参数读允许      
  wire    O_A_Addr_Last   = ABus_Addr_Last  ; //(O)ABus最后一个地址
  wire    O_A_Addr_Empty  = ABus_Addr_Empty ; //(O)ABus地址空      
  wire    O_A_Burst_Last  = ABus_Bst_Last   ; //(O)Burst最后一个地址
  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333
/////////////////    Ddr_Addr_Generater   /////////////////
//444444444444444444444444444444444444444444444444444444444
//
//********************************************************/
  wire    [31:0]  Ddr_ABus_Addr  ; //(O)Address Output

  Axi_Burst_Address U3_Axi_Burst_Address
  (
    .Sys_Clk          ( Sys_Clk         ) , //System Clock
    .I_Addr_Start_En  ( ABus_Buff_Rd_En ) , //(I)Start Address Enable
    .I_Addr_Cnt_En    ( ABus_Addr_RdEn  ) , //(I)Address Counter Enable
    .I_Addr_Size      ( Axi_A_SIZE      ) , //(I)Address Size
    .I_Addr_Start     ( Axi_A_ADDR      ) , //(I)Start Address
    .O_Address        ( Ddr_ABus_Addr   )   //(O)Address Output
  );

  /////////////////////////////////////////////////////////
  wire  [   31:0]   O_A_Address  = Ddr_ABus_Addr  ; //(O)DDR 地址总线读写地址 
  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444
/////////////////    Ddr_Addr_Generater   /////////////////
//555555555555555555555555555555555555555555555555555555555
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire  [ABW-1:0]   ABus_Next_Param   = ABus_Buff_Rd_Data ;
  reg               ABus_New_Param    = 1'h0              ;
  reg   [ABW  :0]   ABus_Curr_Param   = {ABW+1{1'h0}}     ;
   
  always  @(posedge Sys_Clk)  if (ABus_Buff_Rd_En)  ABus_New_Param    <=  ~ ABus_New_Param;
  always  @(posedge Sys_Clk)  if (ABus_Buff_Rd_En)  ABus_Curr_Param   <=  { ABus_New_Param, ABus_Next_Param } ;
  
  /////////////////////////////////////////////////////////
  reg       ABus_Addr_WrErr   = 1'h0  ; //地址满写
  reg       ABus_Param_WrErr  = 1'h0  ; //参数缓存满写

  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)               ABus_Addr_WrErr   <=  1'h0  ;
    else if (ABus_Buff_Wr_En)   ABus_Addr_WrErr   <=  ABus_Addr_WrErr   
                                                    | ABus_Addr_Num[AQS]  | Calc_Addr_Full[15]  ;
  end
  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)               ABus_Param_WrErr  <=  1'h0  ;
    else if (ABus_Buff_Wr_En)   ABus_Param_WrErr  <=  ABus_Param_WrErr  | ABus_Buff_Wr_Full ;
  end
  
  /////////////////////////////////////////////////////////
  reg       ABus_Addr_RdErr   = 1'h0  ; //地址空读
  reg       ABus_Param_RdErr  = 1'h0  ; //参数缓存空读

  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)               ABus_Addr_RdErr   <=  1'h0  ;
    else if (ABus_Addr_RdEn)    ABus_Addr_RdErr   <=  ABus_Addr_RdErr   | ABus_Addr_Empty ;
  end
  always  @(posedge Sys_Clk)  
  begin
    if (Sync_Clr)               ABus_Param_RdErr  <=  1'h0  ;
    else if (ABus_Addr_RdEn)    ABus_Param_RdErr  <=  ABus_Param_RdErr  | ABus_Buff_Rd_Empty  ;
  end

  /////////////////////////////////////////////////////////
  wire  [3:0]   ABus_Err_Flag ;
   
  assign  ABus_Err_Flag[0]  = ABus_Addr_WrErr   ; //地址满写
  assign  ABus_Err_Flag[1]  = ABus_Addr_RdErr   ; //地址空读
  assign  ABus_Err_Flag[2]  = ABus_Param_WrErr  ; //参数缓存满写
  assign  ABus_Err_Flag[3]  = ABus_Param_RdErr  ; //参数缓存空读

  /////////////////////////////////////////////////////////  
  wire  [    3:0]   O_A_Err_Flag    = ABus_Err_Flag   ; //(O)ABus的错误标志
  wire  [ABW-1:0]   O_A_Next_Param  = ABus_Next_Param ; //(O)ABus的下一个参数
  wire  [ABW  :0]   O_A_Curr_Param  = ABus_Curr_Param ; //(O)ABus当前参数
  /////////////////////////////////////////////////////////
//555555555555555555555555555555555555555555555555555555555

endmodule 

/////////////////    Ddr_Addr_Generater   /////////////////







//////////////////   Axi_Burst_Address   //////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2021-03-01
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Axi_Burst_Address
(
  input           Sys_Clk         , //System Clock
  input           I_Addr_Start_En , //(I)Start Address Enable
  input           I_Addr_Cnt_En   , //(I)Address Counter Enable
  input   [ 2:0]  I_Addr_Size     , //(I)Address Size
  input   [31:0]  I_Addr_Start    , //(I)Start Address
  output  [31:0]  O_Address         //(O)Address Output
);

  //Define  Parameter
  /////////////////////////////////////////////////////////  
  parameter         AXI_DATA_WIDTH  = 128 ; //AXI4总线数据的宽度

  localparam        AXI_BYTE_NUMBER = AXI_DATA_WIDTH  / 8       ; //AXI4数据总线字节个数
  localparam        AXI_BYTE_SIZE   = $clog2(AXI_BYTE_NUMBER)   ; //AXI4数据尺寸，即为字节计数器宽度
  localparam [31:0] AXI_ADDR_MASK   = 32'hff_ff_ff_ff <<  AXI_BYTE_SIZE ;
  
  /////////////   缩写    
  localparam  ABS   = AXI_BYTE_SIZE             ; //AXI数据尺寸，即为字节计数器宽度
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire           Addr_Start_En = I_Addr_Start_En ; //Start Address Enable
  wire           Addr_Cnt_En   = I_Addr_Cnt_En   ; //Address Counter Enable
  wire   [ 2:0]  Addr_Size     = I_Addr_Size     ; //Address Size
  wire   [31:0]  Addr_Start    = I_Addr_Start    ; //Start Address
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//////////////////   Axi_Burst_Address   //////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg  [31:0]  Addr_Step  = 32'h0   ;  //地址计数器的步进；取决于Addr_Size

  always  @(posedge Sys_Clk)  if (Addr_Start_En)  Addr_Step <=  32'h1 << Addr_Size  ;
  
  ///////////////////////////////////////////////////////
  reg   [31:0]  Address  = 32'h0 ;    //LUT 144

  always  @(posedge Sys_Clk)  
  begin
    if (Addr_Start_En)      Address   <=  AXI_ADDR_MASK & Addr_Start ;
    else if (Addr_Cnt_En)   Address   <=  AXI_ADDR_MASK & (Address   + Addr_Step) ;
  end

  /////////////////////////////////////////////////////////
  assign    O_Address   = Address ; //(O)Address Output
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
//////////////////   Axi_Burst_Address   //////////////////

endmodule

//////////////////   Axi_Burst_Address   //////////////////














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

/*

  parameter   AXI_ID_WIDTH        = 8   ;   //AXI4总线ID的宽度
  parameter   AXI_DATA_WIDTH      = 128 ;   //AXI4总线数据的宽度
  parameter   DDR_DATA_WIDTH      = 16  ;   //DDR总线数据的宽度

  parameter   WR_DATA_FIFO_DEPTH       = 512 ;   //写数据FIFO深度
  parameter   WR_BURST_QUEUE_NUM       = 16  ;   //写最大地址队列深度

  parameter   RD_DATA_FIFO_DEPTH       = 512 ;   //读数据FIFO深度
  parameter   RD_BURST_QUEUE_NUM     = 16  ;   //读最大地址队列深度

  parameter   SECTION_MIN_LEN     = 32  ;   //最小切片长度，单位是AXI的Busrt个数
                                            //存储容量小于该值，将不进行下一步操作

  /////////////
  localparam  DDR_BUS_DATA_WIDTH  = DDR_DATA_WIDTH * 2        ; //内部数据总线的宽度，为DDR数据总线的2倍
  localparam  DDR_BUS_BYTE_NUM    = DDR_BUS_DATA_WIDTH  / 8   ; //内部数据总线字节个数
  localparam  DDR_BUS_BYTE_SIZE   = $clog2(DDR_BUS_BYTE_NUM)  ; //内部数据尺寸，即为字节计数器宽度

  localparam  AXI_BYTE_NUMBER     = AXI_DATA_WIDTH  / 8       ; //AXI4数据总线字节个数
  localparam  AXI_BYTE_SIZE       = $clog2(AXI_BYTE_NUMBER)   ; //AXI4数据尺寸，即为字节计数器宽度

  localparam  DDR_BYTE_NUMBER     = DDR_DATA_WIDTH  / 8       ; //DDR数据总线字节个数
  localparam  DDR_BYTE_SIZE       = $clog2(DDR_BYTE_NUMBER)   ; //DDR数据尺寸，即为字节计数器宽度
   
  localparam  DDR_BURST_WIDTH     = DDR_DATA_WIDTH  * 8       ; //DDR每次Burst的数据宽度,Burst=8
  /////////////   DM、DQS宽度
  localparam  AXI_DM_WIDTH        = AXI_BYTE_NUMBER           ; //AXI侧掩码宽度
  localparam  DDR_DM_WIDTH        = DDR_BYTE_NUMBER           ; //DDR侧掩码宽度
  localparam  DDR_BUS_DM_WIDTH    = DDR_BUS_BYTE_NUM          ; //DDR内部掩码宽度
    
  /////////////   内部存储有关    
  localparam  BUFF_FIFO_DATA_WIDTH_RITIO  = AXI_DATA_WIDTH  / DDR_BUS_DATA_WIDTH      ; //Buffer/FIFO的数据宽度比
  localparam  BUFF_FIFO_WIDTH_RITIO_SIZE  = $clog2(BUFF_FIFO_DATA_WIDTH_RITIO)        ; //Buffer/FIFO的数据宽度比的计数器宽度

  localparam  WR_DATA_BUFF_WIDTH        = AXI_DATA_WIDTH      + AXI_DM_WIDTH      + 1 ; //写缓存的宽度；
  localparam  WR_DATA_FIFO_WIDTH        = DDR_BUS_DATA_WIDTH  + DDR_BUS_DM_WIDTH  + 1 ; //写FIFO的宽度
  localparam  WR_DATA_FIFO_ADDR_WIDTH   = $clog2(WR_DATA_FIFO_DEPTH)                       ; //写FIFO地址宽度
  localparam  WR_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO                  ; //写缓存个数
  localparam  WR_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                  ; //写缓存个数计数器宽度

  localparam  RD_DATA_BUFF_WIDTH        = DDR_BUS_DATA_WIDTH                          ; //读缓存的宽度
  localparam  RD_DATA_FIFO_WIDTH        = DDR_BUS_DATA_WIDTH  + 1                     ; //读FIFO的宽度
  localparam  RD_DATA_FIFO_ADDR_WIDTH   = $clog2(RD_DATA_FIFO_DEPTH)                       ; //读FIFO地址宽度  
  localparam  RD_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO * 2              ; //读缓存个数，读缓存采用乒乓结构，要多用一倍的资源
  localparam  RD_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                  ; //读缓存个数计数器宽度

  localparam  ADDR_BUS_BUFF_WIDTH       = AXI_ID_WIDTH + 32 + 8 + 3                   ; //地址总线缓存数据宽度；包括ID/ADDR/LEN/SIZE

  /////////////   缩写               
  localparam  AIW   = AXI_ID_WIDTH              ; //AXI总线ID的宽度  
  localparam  ADW   = AXI_DATA_WIDTH            ; //AXI总线数据的宽度
  localparam  ADS   = AXI_BYTE_SIZE             ; //AXI数据尺寸，即为字节计数器宽度
  localparam  AMW   = AXI_DM_WIDTH              ; //AXI侧掩码宽度
  localparam  ABN   = AXI_BYTE_NUMBER           ; //AXI侧字节个数

  localparam  DDW   = DDR_DATA_WIDTH            ; //DDR总线数据的宽度
  localparam  DDS   = DDR_BYTE_SIZE             ; //DDR数据尺寸，即为字节计数器宽度
  localparam  DMW   = DDR_DM_WIDTH              ; //DDR侧掩码宽度
  localparam  DBN   = DDR_BYTE_NUMBER           ; //DDR侧字节个数

  localparam  BDW   = DDR_BUS_DATA_WIDTH        ; //内部数据总线的宽度，为DDR数据总线的2倍
  localparam  BDS   = DDR_BUS_BYTE_SIZE         ; //内部数据尺寸，即为字节计数器宽度
  localparam  BMW   = DDR_BUS_DM_WIDTH          ; //DDR内部掩码宽度
  localparam  BBN   = DDR_BUS_BYTE_NUM          ; //DDR内字节个数

  localparam  DBW   = DDR_BURST_WIDTH           ; //DDR每次Burst的数据宽度

  localparam  WBW   = WR_DATA_BUFF_WIDTH        ; //写缓存的宽度
  localparam  WFW   = WR_DATA_FIFO_WIDTH        ; //写FIFO的宽度
  localparam  WFS   = WR_DATA_FIFO_ADDR_WIDTH   ; //写FIFO地址宽度
  localparam  WBN   = WR_DATA_BUFF_NUMBER       ; //写缓存个数
  localparam  WBS   = WR_DATA_BUFF_NUMBER_SIZE  ; //写缓存个数计数器宽度

  localparam  RBW   = RD_DATA_BUFF_WIDTH        ; //读缓存的宽度
  localparam  RFW   = RD_DATA_FIFO_WIDTH        ; //读FIFO的宽度
  localparam  RFS   = RD_DATA_FIFO_ADDR_WIDTH   ; //读FIFO地址宽度  
  localparam  RBN   = RD_DATA_BUFF_NUMBER       ; //读缓存个数，读缓存采用乒乓结构，要多用一倍的资源
  localparam  RBS   = RD_DATA_BUFF_NUMBER_SIZE  ; //读缓存个数计数器宽度

  localparam  ABW   = ADDR_BUS_BUFF_WIDTH       ; //地址总线缓存数据宽度；包括ID/ADDR/LEN/SIZE   
  /////////////////////////////////////////////////////////
*/