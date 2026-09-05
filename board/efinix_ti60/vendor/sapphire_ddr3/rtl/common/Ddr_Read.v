
//////////////////////   Ddr_Read   ///////////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2021-03-01
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Read
(
  //System Signal
  Clk_TxCmd       , //Clock Tx Command
  Clk_RxDq        , //Clock Rx DQ
  Clk_Core        , //Clock Core
  Clk_Axi         , //Clock Axi
  Rst_TxCmd       , //Reset In Clock Tx Command
  Rst_RxDq        , //Reset In Clock Rx DQ
  Rst_Core        , //Reset In Clock Core
  Rst_Axi         , //Reset In Clock Axi
  //Axi Signal  
  I_AR_ID         , //(I)[RdAddr]Read address ID. 
  I_AR_ADDR       , //(I)[RdAddr]Read address. 
  I_AR_LEN        , //(I)[RdAddr]Burst length. 
  I_AR_SIZE       , //(I)[RdAddr]Burst size.
  I_AR_BURST      , //(I)[RdAddr]Burst type. 
  I_AR_LOCK       , //(I)[RdAddr]Lock type. 
  I_AR_VALID      , //(I)[RdAddr]Read address valid. 
  O_AR_READY      , //(O)[RdAddr]Read address ready.
  O_R_ID          , //(O)[RdData]Read ID tag. 
  O_R_DATA        , //(O)[RdData]Read data.
  O_R_LAST        , //(O)[RdData]Read last. 
  O_R_RESP        , //(O)[RdData]Read response. 
  O_R_VALID       , //(O)[RdData]Read valid. 
  I_R_READY       , //(I)[RdData]Read ready.  
  //Test Interface 
  I_RdLevel_En    , //(I)[Clk_Core] Read Leveling Enable
  I_Test_Mode     , //(I)[Clk_Axi ] Test Mode 
  I_T_AR_Wr_En    , //(I)[Clk Axi ] Test ARBus Write Enable
  I_T_AR_Wr_D     , //(I)[Clk Axi ] Test ARBus Write Data
  O_T_AR_Ready    , //(O)[Clk Axi ] Test ARBus Write Buffer Full
  O_T_AR_Idle     , //(O)[Clk Core] Test ARBus Idle 
  I_T_R_Rd_En     , //(I)[Clk Axi ] Test RBus Read Enable
  O_T_R_Rd_D      , //(O)[Clk Axi ] Test RBus Read Data
  O_T_R_Ready     , //(O)[Clk Axi ] Test RBus Read Buffer Full
  O_T_R_Idle      , //(O)[Clk Core] Test RBus Idle 
  //DDR RBus Signal
  I_Phy_Cmd_Read  , //(I)Comand Read     
  O_Phy_Rd_Num    , //(O)Read Data Number (Debug)
  O_Phy_Rd_Error  , //(O)Read Error  
  O_Phy_Dqs_State , //(O)DQS State 0:Dir ; 1:Error ;2:Change 
  O_Ddr_Rd_DVal   , //(O)DDR Read Data Valid 
  O_RD_Fifo_Empty , //(I)[Clk_RxDq] DDR Read FIFO Empty
  O_RD_Fifo_Spls  , //(O)DDR Read FIFO Surplus Burst Number
  O_RD_Fifo_Full  , //(O)DDR RBus Data FIFO Full
  O_Read_Err_Flag , //(O)[Clk_Core] ARBus Error Flag
  
  I_Axi_Rd_Pause  , //(I)[Clk_Core] Axi Read Pause 
  I_Ddr_Rd_Pause  , //(I)[Clk_Core] DDR Read Pause 
  I_AR_Addr_RdEn  , //(I)[Clk_Core] ARBus Read Address Enable
  O_AR_Addr_Num   , //(O)[Clk_Core] ARBus Address Number     
  O_AR_Addr_Empty , //(O)[Clk_Core] ARBus Buffer Empty 
  O_AR_Addr_Last  , //(O)[Clk_Core] ARBus Buffer Last 
  O_AR_Ddr_Addr   , //(O)[Clk_Core] ARBus Address Output 
  O_AR_Burst_RdEn , //(O)[Clk_Core] ABBus Burst Read Enable     
  O_AR_Burst_Last , //(O)[Clk_Core] ARBus Burst Last
  O_AR_Burst_Done , //(O)[Clk_Core] AWBus Burst Done 
  O_AR_Next_Param , //(O)[Clk_Core] ARBus Next Parameter      
  O_AR_Curr_Param , //(O)[Clk_Core] ARBus Current Parameter
  //DDR Interface 
  I_Ddr_Dqs_Hi    , //(I)DDR DQS Input (HI) 
  I_Ddr_Dqs_Lo    , //(I)DDR DQS Input (LO) 
  I_Ddr_Dq_Hi     , //(I)DDR DQ Input (HI)
  I_Ddr_Dq_Lo       //(I)DDR DQ Input (LO)
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
  localparam  WR_DATA_FIFO_ADDR_WIDTH   = $clog2(WR_DATA_FIFO_DEPTH)                  ; //写FIFO地址宽度
  localparam  WR_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO                  ; //写缓存个数
  localparam  WR_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                  ; //写缓存个数计数器宽度

  localparam  RD_DATA_BUFF_WIDTH        = DDR_BUS_DATA_WIDTH                          ; //读缓存的宽度
  localparam  RD_DATA_FIFO_WIDTH        = DDR_BUS_DATA_WIDTH  + 1                     ; //读FIFO的宽度
  localparam  RD_DATA_FIFO_ADDR_WIDTH   = $clog2(RD_DATA_FIFO_DEPTH)                  ; //读FIFO地址宽度  
  localparam  RD_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO * 2              ; //读缓存个数，读缓存采用乒乓结构，要多用一倍的资源
  localparam  RD_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                  ; //读缓存个数计数器宽度

  localparam  TEST_RD_DATA_WIDTH        = AXI_DATA_WIDTH + AXI_ID_WIDTH + 1           ; //读测试的数据宽度；包括DATA/ID/LAST

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

  localparam  TDW   = TEST_RD_DATA_WIDTH        ; //读测试的数据宽度；包括DATA/ID/LAST

  localparam  ABW   = ADDR_BUS_BUFF_WIDTH       ; //地址总线缓存数据宽度；包括ID/ADDR/LEN/SIZE    
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  input                     Clk_TxCmd       ; //Clock Tx Command
  input                     Clk_RxDq        ; //Clock Rx DQ
  input                     Clk_Core        ; //Clock Core
  input                     Clk_Axi         ; //Clock Axi
  input                     Rst_TxCmd       ; //Reset In Clock Tx Command
  input                     Rst_RxDq        ; //Reset In Clock Rx DQ
  input                     Rst_Core        ; //Reset In Clock Core
  input                     Rst_Axi         ; //Reset In Clock Axi

  input   wire  [AIW-1:0]   I_AR_ID         ; //(I)[RdAddr]Read address ID.  
  input   wire  [   31:0]   I_AR_ADDR       ; //(I)[RdAddr]Read address.  
  input   wire  [    7:0]   I_AR_LEN        ; //(I)[RdAddr]Burst length.  
  input   wire  [    2:0]   I_AR_SIZE       ; //(I)[RdAddr]Burst size. 
  input   wire  [    1:0]   I_AR_BURST      ; //(I)[RdAddr]Burst type.  
  input   wire  [    1:0]   I_AR_LOCK       ; //(I)[RdAddr]Lock type.  
  input   wire              I_AR_VALID      ; //(I)[RdAddr]Read address valid.  
  output  wire              O_AR_READY      ; //(O)[RdAddr]Read address ready. 
  output  wire  [AIW-1:0]   O_R_ID          ; //(O)[RdData]Read ID tag.  
  output  wire  [ADW-1:0]   O_R_DATA        ; //(O)[RdData]Read data. 
  output  wire              O_R_LAST        ; //(O)[RdData]Read last.  
  output  wire  [    1:0]   O_R_RESP        ; //(O)[RdData]Read response.  
  output  wire              O_R_VALID       ; //(O)[RdData]Read valid.  
  input   wire              I_R_READY       ; //(I)[RdData]Read ready.   
  //Test Interface 
  input   wire              I_RdLevel_En    ; //(I)[Clk_Core] 读均衡(Read Leveling)允许
  input   wire              I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  input   wire              I_T_AR_Wr_En    ; //(I)[Clk Axi ] 测试ARBUS写允许
  input   wire  [ABW-1:0]   I_T_AR_Wr_D     ; //(I)[Clk Axi ] 测试ARBUS写数据
  output  wire              O_T_AR_Ready    ; //(O)[Clk Axi ] 测试ARBUS忙，不能接收指令
  output  wire              O_T_AR_Idle     ; //(O)[Clk_Core] 测试ARBUS空闲，表示完成所有指令
  input   wire              I_T_R_Rd_En     ; //(I)[Clk Axi ] 测试RBUS读允许
  output  wire  [TDW-1:0]   O_T_R_Rd_D      ; //(O)[Clk Axi ] 测试RBUS读数据;包括DATA/ID/LAST
  output  wire              O_T_R_Ready     ; //(O)[Clk Axi ] 测试RBUS准备好，可以接收指令 
  output  wire              O_T_R_Idle      ; //(O)[Clk_Core] 测试RBUS空闲，表示完成所有指令
  //Controller Interface
  input   wire              I_Phy_Cmd_Read  ; //(I)[Clk_Cmd ] 发送到PHY的读指令  
  output  wire  [    2:0]   O_Phy_Rd_Num    ; //(O)[Clk_RxDq] 指示没有执行的读命令个数（用于调试）
  output  wire  [    2:0]   O_Phy_Rd_Error  ; //(O)[Clk_RxDq] 读错误指示, 可用于错误侦测和故障诊断 
  output  wire  [    2:0]   O_Phy_Dqs_State ; //(O)[Clk_RxDq] DQS状态 ，用于读校准               

  // O_Phy_Rd_Error  读错误指示, 可用于错误侦测和故障诊断   
  //   2:  Err_TimeOut     当在指定窗口没有搜索到DQS的头
  //   1:  Err_Sdq_Code    在读数据过程中出现与数据选择不匹配的DQS
  //   0:  Err_Overflow    数据结束后DQS仍然有效 
  // O_Phy_Dqs_State   DQS状态 ，用于读校准  0:Dir ; 1:Error ;2:Change 
  //   2:  高电平表示DQS发生一次相位变化，从01到10或从10到01
  //   1:  DQS错误，高电平表示DQS在一次采集过程中出现不同DQS相位；
  //   0： DQS方向，这个为DDIO采集的DQS的第一个Bit

  output  wire  [    7:0]   O_Read_Err_Flag ; //(O)[Clk_Core] 读地址总线的错误标志
                                              //[0] : 地址满写      [1] : 地址空读     
                                              //[2] : 参数缓存满写  [3] : 参数缓存空读 
                                              //[7] : 校验和错

  output  wire              O_Ddr_Rd_DVal   ; //DDR读数据有效
  output  wire              O_RD_Fifo_Empty ; //(O)读数据FIFO空
  output  wire              O_RD_Fifo_Full  ; //(O)[Clk_RxDq] 读数据FIFO满指示
  output  wire  [    7:0]   O_RD_Fifo_Spls  ; //(O)[Clk_RxDq] 读数据FIFO剩余空间

  //O_RD_Fifo_Full  ; //(O)读数据FIFO满指示 用于操作仲裁
  //    FIFO满需要立刻停止当前的读操作，避免溢出
  //O_RD_Fifo_Spls    读数据FIFO剩余空间，用于操作仲裁
  //    用于仲裁是判断读数据FIFO是否能容纳一次Burst或一次最小分割单位的访问
  //    在有多个访问需求时才需要对该项进行判断

  input   wire              I_Axi_Rd_Pause  ; //(I)[Clk_Core] Axi读暂停
  input   wire              I_Ddr_Rd_Pause  ; //(I)[Clk_Core] DDR读暂停
  input   wire              I_AR_Addr_RdEn  ; //(I)[Clk_Core] 读地址总线取地址允许
  output  wire  [   15:0]   O_AR_Addr_Num   ; //(O)[Clk_Core] 未操作的写地址个数
  output  wire              O_AR_Addr_Empty ; //(O)[Clk_Core] 读地址总线无操作地址 
  output  wire              O_AR_Addr_Last  ; //(O)[Clk_Core] 最后一个地址
  output  wire  [   31:0]   O_AR_Ddr_Addr   ; //(O)[Clk_Core] DDR的读地址      
  output  wire              O_AR_Burst_RdEn ; //(O)[Clk_Core] 读参数允许   
  output  wire              O_AR_Burst_Last ; //(O)[Clk_Core] 当前Burst最后一个操作
  output  wire              O_AR_Burst_Done ; //(O)[Clk_Core] 指示刚刚完成一个读Burst
  output  wire  [ABW-1:0]   O_AR_Next_Param ; //(O)[Clk_Core] 读地址总线的下一个参数
  output  wire  [ABW  :0]   O_AR_Curr_Param ; //(O)[Clk_Core] 读地址总线的当前参数

  input         [DBN-1:0]   I_Ddr_Dqs_Hi    ; //(I)DDR DQS Input (HI) 
  input         [DBN-1:0]   I_Ddr_Dqs_Lo    ; //(I)DDR DQS Input (LO) 
  input         [DDW-1:0]   I_Ddr_Dq_Hi     ; //(I)DDR DQ Input (HI)
  input         [DDW-1:0]   I_Ddr_Dq_Lo     ; //(I)DDR DQ Input (LO)
  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  ///////////////////////////////////////////////////////// 
  wire  [AIW-1:0]   Axi_AR_ID       = I_AR_ID         ; //(I)[WrAddr]Write address ID.
  wire  [   31:0]   Axi_AR_ADDR     = I_AR_ADDR       ; //(I)[WrAddr]Write address.
  wire  [    7:0]   Axi_AR_LEN      = I_AR_LEN        ; //(I)[WrAddr]Burst length.
  wire  [    2:0]   Axi_AR_SIZE     = I_AR_SIZE       ; //(I)[WrAddr]Burst size.
  wire  [    1:0]   Axi_AR_BURST    = I_AR_BURST      ; //(I)[WrAddr]Burst type.
  wire  [    1:0]   Axi_AR_LOCK     = I_AR_LOCK       ; //(I)[WrAddr]Lock type.
  wire              Axi_AR_VALID    = I_AR_VALID      ; //(I)[WrAddr]Write address valid.
  wire              Axi_R_READY     = I_R_READY       ; //(I)[RdData]Read ready. 

  wire              Rd_Level_En     = I_RdLevel_En    ; //(I)[Clk_Core] 读均衡(Read Leveling)允许
  wire              Test_Mode       = I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  wire              Test_AR_Wr_En   = I_T_AR_Wr_En    ; //(I)[Clk Axi ] 测试ARBUS写允许
  wire  [ABW-1:0]   Test_AR_Wr_D    = I_T_AR_Wr_D     ; //(I)[Clk Axi ] 测试ARBUS写数据

  wire              Axi_Rd_Pause    = I_Axi_Rd_Pause  ; //(I)[Clk_Core] Axi读暂停
  wire              Ddr_Rd_Pause    = I_Ddr_Rd_Pause  ; //(I)[Clk_Core] DDR读暂停
  wire              Phy_Cmd_Read    = I_Phy_Cmd_Read  ; //(I)发送到PHY的读指令  
  wire              ARBus_Addr_RdEn = I_AR_Addr_RdEn  ; //(I)DDR 地址总线取地址允许
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
//////////////////////   Ddr_Read   ///////////////////////
//111111111111111111111111111111111111111111111111111111111
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire                Axi_ARBus_Pause   ; //(I)Axi 地址总线操作暂停
  wire                Axi_ARBus_WrEn    ; //(O)[Clk_Axi ] AXI 地址总线写允许(AXI时钟域) 
  
  wire  [3:0]         ARBus_Err_Flag    ;
  wire                ARBus_Addr_Empty  ; //(O)[Clk_Core] ABus地址空    
 
  defparam  U1_Ddr_ARBus_Control.AXI_ID_WIDTH      = AXI_ID_WIDTH       ; //AXI4总线ID的宽度
  defparam  U1_Ddr_ARBus_Control.AXI_DATA_WIDTH    = AXI_DATA_WIDTH     ; //AXI4总线数据的宽度
  defparam  U1_Ddr_ARBus_Control.DDR_DATA_WIDTH    = DDR_DATA_WIDTH     ; //DDR总线数据的宽度
  defparam  U1_Ddr_ARBus_Control.ADDR_QUEUE_NUM    = RD_ADDR_QUEUE_NUM  ; //最大地址队列个数
  defparam  U1_Ddr_ARBus_Control.BURST_QUEUE_NUM   = RD_BURST_QUEUE_NUM ; //最大地址队列深度

  Ddr_Addr_Bus_Control  U1_Ddr_ARBus_Control
  (
    //System Signal
    .Clk_Core         ( Clk_Core          ) , //System Clock
    .Clk_Axi          ( Clk_Axi           ) , //System Clock
    .Rst_Core         ( Rst_Core          ) , //(I)Sync Reset
    .Rst_Axi          ( Rst_Axi           ) , //(I)Sync Reset
    //Axi Signal          
    .I_A_ID           ( I_AR_ID           ) , //(I)[Addr]Write address ID.
    .I_A_ADDR         ( I_AR_ADDR         ) , //(I)[Addr]Write address.
    .I_A_LEN          ( I_AR_LEN          ) , //(I)[Addr]Burst length.
    .I_A_SIZE         ( I_AR_SIZE         ) , //(I)[Addr]Burst size.
    .I_A_BURST        ( I_AR_BURST        ) , //(I)[Addr]Burst type.
    .I_A_LOCK         ( I_AR_LOCK         ) , //(I)[Addr]Lock type.
    .I_A_VALID        ( I_AR_VALID        ) , //(I)[Addr]Write address valid.
    .O_A_READY        ( O_AR_READY        ) , //(O)[Addr]Write address ready.
    //Test Interface 
    .I_Test_Mode      ( I_Test_Mode       ) , //(I)[Clk_Axi ] Test Mode 
    .I_T_A_Wr_En      ( I_T_AR_Wr_En      ) , //(I)[Clk Axi ] Test ABus Write Enable
    .I_T_A_Wr_D       ( I_T_AR_Wr_D       ) , //(I)[Clk Axi ] Test ABus Write Data
    .O_T_A_Ready      ( O_T_AR_Ready      ) , //(O)[Clk Axi ] Test ABus Write Buffer Full
    //DDR Controller Siganl
    .I_Axi_Op_Pause   ( Axi_ARBus_Pause   ) , //(I)[Clk_Axi ] DDR Operate Pause 
    .O_Axi_A_WrEn     ( Axi_ARBus_WrEn    ) , //(O)[Clk_Axi ] Axi ABus Write Enable   
    .I_A_Addr_RdEn    ( I_AR_Addr_RdEn    ) , //(I)[Clk_Core] DDR Address Bus Read Address Enable
    .O_A_Addr_Num     ( O_AR_Addr_Num     ) , //(O)[Clk_Core] ABus Address Number     
    .O_A_Addr_Empty   ( ARBus_Addr_Empty  ) , //(O)[Clk_Core] DDR Address Bus Buffer Empty 
    .O_A_Addr_Last    ( O_AR_Addr_Last    ) , //(O)[Clk_Core] DDR Address Bus Buffer Last 
    .O_A_Ddr_Addr     ( O_AR_Ddr_Addr     ) , //(O)[Clk_Core] DDR Address Bus Address Output 
    .O_A_Burst_RdEn   ( O_AR_Burst_RdEn   ) , //(O)[Clk_Core] ABus Parameter Read Enable     
    .O_A_Burst_Last   ( O_AR_Burst_Last   ) , //(O)[Clk_Core] DDR Address Bus Burst Last
    .O_A_Next_Param   ( O_AR_Next_Param   ) , //(O)[Clk_Core] ABus Next Parameter      
    .O_A_Curr_Param   ( O_AR_Curr_Param   ) , //(O)[Clk_Core] ABus Current Parameter
    .O_A_Err_Flag     ( ARBus_Err_Flag    )   //(O)[Clk_Core] ABus Error Flag
  ) ;
  
  /////////////////////////////////////////////////////////
  wire  ARBus_Addr_Last   = O_AR_Addr_Last  ;
  wire  ARBus_Bst_Last    = O_AR_Burst_Last ;
  
  /////////////////////////////////////////////////////////
  wire    RdD_Fifo_Full   ;
  wire    Ddr_ARBus_Pause ;
  reg     AR_Burst_Done   = 1'h0  ;

  always  @(posedge  Clk_Core)  
  begin
    if (Rst_Core)               AR_Burst_Done <=  1'h0 ;
    else if (RdD_Fifo_Full)     AR_Burst_Done <=  1'h1 ;
    else if (~Ddr_ARBus_Pause)  AR_Burst_Done <=  1'h0 ;
    else if (ARBus_Bst_Last)    AR_Burst_Done <=  1'h1 ;
  end
  
  wire  Read_Pause  = AR_Burst_Done ;
  
  /////////////////////////////////////////////////////////
  reg   AR_Addr_Empty = 1'h1  ;
    
  always  @ ( * )  AR_Addr_Empty =  ARBus_Addr_Empty  | Read_Pause ;

  /////////////////////////////////////////////////////////
  assign    O_AR_Addr_Empty   = AR_Addr_Empty     ; //(O)[Clk_Core] 读地址总线无操作地址 
  assign    O_AR_Burst_Done   = AR_Burst_Done     ; //(O)[Clk_Core] 指示刚刚完成一个读Burst
  assign    O_T_AR_Idle       = ARBus_Addr_Empty  ; //(O)[Clk_Core] 测试ARBUS空闲，表示完成所有指令
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
//////////////////////   Ddr_Read   ///////////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [5:0]   Rd_Cmd_Reg  = 2'h0  ; //读命令寄存器
  reg           Read_Start  = 1'h0  ; //读开始

  always @(posedge  Clk_RxDq  ) Rd_Cmd_Reg  <=  { Rd_Cmd_Reg[4:0] , Phy_Cmd_Read  } ;
  always @(posedge  Clk_RxDq  ) Read_Start  <=  ( Rd_Cmd_Reg[3:2]==  2'h1      ) ;
  
  /////////////////////////////////////////////////////////
  wire              Ddr_Read_DVal     ; //(O)DDR Data Valid 
  wire  [BDW-1:0]   Ddr_Read_Data     ; //(O)DDR Data 
  wire              Ddr_Bst_End       ; //(O)DDR Burst End
  wire              Ddr_Burst_DVal    ; //(O)Read Data Valid 
  wire  [DBW-1:0]   Ddr_Burst_Data    ; //(O)Read Data

  defparam  U4_Ddr_Rd_Data.DRAM_GROUP_NUM      = DDR_BYTE_NUMBER  ;
  defparam  U4_Ddr_Rd_Data.DRAM_GROUP_WIDTH    = 8             ;

  Ddr_Rd_Data   U4_Ddr_Rd_Data
  (
    .Sys_Clk        ( Clk_RxDq        ) , //System Clock
    .Sys_Rst_N      ( ~Rst_RxDq       ) , //System Reset
    .I_dqs_hi       ( I_Ddr_Dqs_Hi    ) , //(I)DRAM DQS Input Pos (High) 
    .I_dqs_lo       ( I_Ddr_Dqs_Lo    ) , //(I)DRAM DQS Input Pos (Low ) 
    .I_dq_hi        ( I_Ddr_Dq_Hi     ) , //(I)DRAM DQ Input (High)
    .I_dq_lo        ( I_Ddr_Dq_Lo     ) , //(I)DRAM DQ Input (Low )
    .I_Read_Start   ( Read_Start      ) , //(I)Read Start 
    .O_Read_Num     ( O_Phy_Rd_Num    ) , //(O)Read Data Number
    .O_Read_Error   ( O_Phy_Rd_Error  ) , //(O)Read Error
    .O_Dqs_State    ( O_Phy_Dqs_State ) , //(O)DQS State 0:Dir ; 1:Error ;2:Change 
    .O_Ddr_DVal     ( Ddr_Read_DVal   ) , //(O)DDR Data Valid 
    .O_Ddr_Data     ( Ddr_Read_Data   ) , //(O)DDR Data 
    .O_Ddr_Bst_End  ( Ddr_Bst_End     ) , //(O)DDR Burst End
    .O_Read_DVal    ( Ddr_Burst_DVal  ) , //(O)Data Valid 
    .O_Read_Data    ( Ddr_Burst_Data  )   //(O)Read Data
  ) ;
  
  /////////////////////////////////////////////////////////
  assign  O_Ddr_Rd_DVal   = Ddr_Read_DVal ; //DDR读数据有效
  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222
//////////////////////   Ddr_Read   ///////////////////////
//333333333333333333333333333333333333333333333333333333333
//
//********************************************************/
  /////////////////////////////////////////////////////////  
  reg   [1:0]   Addr_RdEn_Reg   = 2'h0  ;

  always  @(posedge  Clk_RxDq )  Addr_RdEn_Reg  <=  {Addr_RdEn_Reg[0] , ARBus_Addr_RdEn} ;  
  
  wire  RxDq_Addr_RdEn    = (Addr_RdEn_Reg  ==  2'h1) ;

  /////////////////////////////////////////////////////////
  reg   RdAddr_Last_Reg  = 1'h0  ;
           
  always  @(posedge  Clk_RxDq )  RdAddr_Last_Reg  <=  ARBus_Bst_Last & ARBus_Addr_RdEn  ;   
  
  wire  RdLast_Fifo_WrData  = RdAddr_Last_Reg ;

  /////////////////////////////////////////////////////////   
  wire  RdLast_Fifo_WrEn    = RxDq_Addr_RdEn  ;
  wire  RdLast_Fifo_RdEn    = Ddr_Bst_End     ; //(I) FIFO Read Enable

  wire          RdLast_Fifo_RdData    ; //(O) Read Data
  wire  [4:0]   RdLast_Fifo_RdNum     ; //(O) Read 

  defparam    U3_Rd_Last_Fifo.OUT_REG       = "No"  ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam    U3_Rd_Last_Fifo.DATA_WIDTH    = 1     ; //Data Width
  defparam    U3_Rd_Last_Fifo.DATA_DEPTH    = 16    ; //Address Width

  Ddr_Ctrl_Sc_Fifo  U3_Rd_Last_Fifo
  (
    .Sys_Clk      ( Clk_RxDq              ) , //System Clock
    .Sync_Clr     ( Rst_RxDq              ) , //Sync Reset
    .I_Wr_En      ( RdLast_Fifo_WrEn      ) , //(I) FIFO Write Enable
    .I_Wr_Data    ( RdLast_Fifo_WrData    ) , //(I) FIFO Write Data
    .I_Rd_En      ( RdLast_Fifo_RdEn      ) , //(I) FIFO Read Enable
    .O_Rd_Data    ( RdLast_Fifo_RdData    ) , //(I) FIFO Read Data
    .O_Data_Num   ( RdLast_Fifo_RdNum     ) , //(I) FIFO Data Number
    .O_Wr_Full    (                       ) , //(O) FIFO Write Full
    .O_Rd_Empty   (                       ) , //(O) FIFO Write Empty
    .O_Fifo_Err   (                       )   //(O) Fifo Error
  ) ;

  /////////////////////////////////////////////////////////
  wire    RBus_Last_Flag  = RdLast_Fifo_RdData ;

  /////////////////////////////////////////////////////////
  //记录取地址和读数据的数量差；监控取地址到读出数据的流程是否正常
  reg   [3:0]   RBus_A2D_Cnt  = 4'h0  ; //RBUS地址到数据的操作计数器                    
  
  always  @(posedge  Clk_RxDq ) 
  begin 
    if (Rst_RxDq)             RBus_A2D_Cnt  <=  4'h0  ;
    else if (Rd_Level_En)     RBus_A2D_Cnt  <=  4'h0  ;
    else if (RxDq_Addr_RdEn ^ Ddr_Bst_End)   
    begin
      if (RxDq_Addr_RdEn)     RBus_A2D_Cnt  <=  RBus_A2D_Cnt  - 4'h1  ;
      else if (Ddr_Bst_End)   RBus_A2D_Cnt  <=  RBus_A2D_Cnt  + {3'h0,RBus_A2D_Cnt[3]}  ;
    end
  end

  wire  [3:0] RBus_A2D_Num    = (4'h0 - RBus_A2D_Cnt) ; //RBUS地址到数据未完成个数
  wire        RBus_A2D_Done   = ( ~ RBus_A2D_Cnt[3] ) ; //RBUS地址到数据的操作全部完成

  /////////////////////////////////////////////////////////
  reg   DBG_RBus_A2D_Err  = 1'h0  ;
  
  always  @(posedge  Clk_RxDq ) 
  begin 
    if (Rst_RxDq)         DBG_RBus_A2D_Err  <=  4'h0  ;
    else if (RxDq_Addr_RdEn ^ Ddr_Bst_End)
    begin
      if (RxDq_Addr_RdEn)     DBG_RBus_A2D_Err  <=  ( RBus_A2D_Cnt  == 4'h8 ) ;
      else if (Ddr_Bst_End)   DBG_RBus_A2D_Err  <=  ( ~ RBus_A2D_Cnt[3]     ) ;
    end
  end

  /////////////////////////////////////////////////////////
  //检查  RdLast_Fifo_Rd_Num 和 O_Phy_Rd_Num  ??
  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333
//////////////////////   Ddr_Read   ///////////////////////
//444444444444444444444444444444444444444444444444444444444
//
//********************************************************/
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
  //DDR RBus Signal

  wire    [AIW-1:0]   Axi_RBus_ID     ; //(I)DDR Current ID 
  wire                Ddr_RBus_DVal   = ~RBus_A2D_Done  & Ddr_Read_DVal   ; //(I)DDR Read Bus Write Enable
  wire                Ddr_RBus_Last   = RBus_Last_Flag  ; //(I)DDR Read Bus Last Data 
  wire    [BDW-1:0]   Ddr_RBus_Data   = Ddr_Read_Data   ; //(I)DDR Read Bus Write Data
  wire                Ddr_Rd_Bst_End  = Ddr_Bst_End     ; //(I)DDR Burst End
  
  wire                RD_ChkSum_Err   ; //(O)[Clk_Axi ] 校验和出错，错误产生在数据传输过程中
  wire                Axi_RBus_RdEn   ; //(O)[Clk_Axi ] 读地址总线写允许（R_READY & R_VALID)

  defparam  U4_Ddr_Read_FiFo.AXI_ID_WIDTH        = AXI_ID_WIDTH       ;   //AXI4总线ID的宽度
  defparam  U4_Ddr_Read_FiFo.AXI_DATA_WIDTH      = AXI_DATA_WIDTH     ;   //AXI4总线数据的宽度
  defparam  U4_Ddr_Read_FiFo.DDR_DATA_WIDTH      = DDR_DATA_WIDTH     ;   //DDR总线数据的宽度
  defparam  U4_Ddr_Read_FiFo.RD_DATA_FIFO_DEPTH  = RD_DATA_FIFO_DEPTH ;   //读数据FIFO深度

  Ddr_Read_FiFo   U4_Ddr_Read_FiFo
  (
    //System Signal
    .Clk_RxDq       ( Clk_RxDq        ) , //Clock Rx Dq
    .Clk_Axi        ( Clk_Axi         ) , //Clock Axi
    .Rst_RxDq       ( Rst_RxDq        ) , //Reset In Clock Rx DQ
    .Rst_Axi        ( Rst_Axi         ) , //Reset In Clock Axi
    //Axi RBus Signal 
    .O_R_ID         ( O_R_ID          ) , //(O)[RdData]Read ID tag. 
    .O_R_DATA       ( O_R_DATA        ) , //(O)[RdData]Read data.
    .O_R_LAST       ( O_R_LAST        ) , //(O)[RdData]Read last. 
    .O_R_RESP       ( O_R_RESP        ) , //(O)[RdData]Read response. 
    .O_R_VALID      ( O_R_VALID       ) , //(O)[RdData]Read valid. 
    .I_R_READY      ( I_R_READY       ) , //(I)[RdData]Read ready. 
    //Test Interface 
    .I_Test_Mode    ( I_Test_Mode     ) , //(I)[Clk_Axi ] Test Mode 
    .I_T_R_Rd_En    ( I_T_R_Rd_En     ) , //(I)[Clk Axi ] Test RBus Read Enable
    .O_T_R_Rd_D     ( O_T_R_Rd_D      ) , //(I)[Clk Axi ] Test RBus Read Data
    .O_T_R_Ready    ( O_T_R_Ready     ) , //(O)[Clk Axi ] Test RBus Read Buffer Full
    //DDR RBus Signal 
    .I_Ddr_Curr_ID  ( Axi_RBus_ID     ) , //(I)[Clk_Axi ] DDR Current ID 
    .I_Ddr_R_DVal   ( Ddr_RBus_DVal   ) , //(I)[Clk_RxDq] DDR Read Bus Data Valid
    .I_Ddr_R_Last   ( Ddr_RBus_Last   ) , //(I)[Clk_RxDq] DDR Read Bus Last Data 
    .I_Ddr_R_Data   ( Ddr_RBus_Data   ) , //(I)[Clk_RxDq] DDR Read Bus Write Data
    .I_Rd_Bst_End   ( Ddr_Rd_Bst_End  ) , //(I)[Clk_RxDq] DDR Read Burst End
    .O_Axi_RBus_RdEn( Axi_RBus_RdEn   ) , //(O)[Clk_Axi ] Axi AWBus Write Enable
    .O_RD_ChkSum_Err( RD_ChkSum_Err   ) , //(O)[Clk_Axi ] Read Data Checksum Error
    .O_RD_Fifo_Empty( O_RD_Fifo_Empty ) , //(I)[Clk_RxDq] DDR Read FIFO Empty
    .O_RD_Fifo_Spls ( O_RD_Fifo_Spls  ) , //(O)[Clk_RxDq] DDR Read FIFO Surplus Burst Number
    .O_RD_Fifo_Full ( O_RD_Fifo_Full  )   //(O)[Clk_RxDq] DDR Read Bus Buff Full  
  );

  wire    RdD_Fifo_Empty  = O_RD_Fifo_Empty ;
  assign  RdD_Fifo_Full   = O_RD_Fifo_Full  ;

  /////////////////////////////////////////////////////////
  wire  [7:0]   Read_Err_Flag   = { RD_ChkSum_Err   ,
                                    3'h0            ,
                                    ARBus_Err_Flag  } ;

  /////////////////////////////////////////////////////////
  assign  O_T_R_Idle      = RdD_Fifo_Empty  ; //(O)[Clk_Core] 测试RBUS空闲，表示完成所有指令
  assign  O_Read_Err_Flag = Read_Err_Flag   ; //(O)[Clk_Core] 读地址总线的错误标志
                                              //[0] : 地址满写      [1] : 地址空读     
                                              //[2] : 参数缓存满写  [3] : 参数缓存空读 
                                              //[7] : 校验和错
  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444
//////////////////////   Ddr_Read   ///////////////////////
//555555555555555555555555555555555555555555555555555555555
//
//********************************************************/
  /////////////////////////////////////////////////////////
  localparam  RBUS_ID_BUFF_DEPTH  = RD_BURST_QUEUE_NUM * 2  ;           //读操作的ID缓存的深度
  localparam  RBUS_ID_BUFF_ADDR_WIDTH   = $clog2(RBUS_ID_BUFF_DEPTH) ;  //读操作的ID缓存的地址宽度
  localparam  RIBAW  = RBUS_ID_BUFF_ADDR_WIDTH ;                        //读操作的ID缓存的地址宽度
  /////////////////////////////////////////////////////////
  reg     RBus_Last_Val   = 1'h0 ;

  always  @(posedge Clk_Axi)  RBus_Last_Val <=  Axi_RBus_RdEn & O_R_LAST  ;

  /////////////////////////////////////////////////////////  
  wire   [    2:0]  Test_AR_SIZE  ;  
  wire   [AIW-1:0]  Test_AR_ID    ;  
  wire   [    7:0]  Test_AR_LEN   ;  
  wire   [   31:0]  Test_AR_ADDR  ;  

  assign  { Test_AR_SIZE  ,
            Test_AR_ID    ,
            Test_AR_LEN   ,
            Test_AR_ADDR  }   = Test_AR_Wr_D  ;

  wire  [AIW-1:0]   R_Id_Buff_Wr_Data   = Test_Mode ? 
                                          Test_AR_ID :  Axi_AR_ID   ; //(I) FIFO Write Data

  /////////////////////////////////////////////////////////  
  wire              R_Id_Buff_Wr_En     = Axi_ARBus_WrEn  ;
  wire              R_Id_Buff_Rd_En     = RBus_Last_Val   ; //(I) FIFO Read Enable

  wire  [AIW-1:0]   R_Id_Buff_Rd_Data   ; //(O) FIFO Read Data
  wire  [RIBAW:0]   R_Id_Buff_Data_Num  ; //(O) Ram Data Number
  wire              R_Id_Buff_Wr_Full   ; //(O) FIFO Write Full
  wire              R_Id_Buff_Rd_Empty  ; //(O) FIFO Write Empty
  wire              R_Id_Buff_Fifo_Err  ; //(O) FIFO Error

  defparam    U1_R_Id_Buffer.OUT_REG     = "No"               ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam    U1_R_Id_Buffer.DATA_WIDTH  = AXI_ID_WIDTH       ; //Data Width
  defparam    U1_R_Id_Buffer.DATA_DEPTH  = RBUS_ID_BUFF_DEPTH ; //Data Depth

  Ddr_Ctrl_Sc_Fifo  U1_R_Id_Buffer
  (
    .Sys_Clk      ( Clk_Axi             ) , //System Clock
    .Sync_Clr     ( Rst_Axi             ) , //Sync Reset
    .I_Wr_En      ( R_Id_Buff_Wr_En     ) , //(I) FIFO Write Enable
    .I_Wr_Data    ( R_Id_Buff_Wr_Data   ) , //(I) FIFO Write Data
    .I_Rd_En      ( R_Id_Buff_Rd_En     ) , //(I) FIFO Read Enable
    .O_Rd_Data    ( R_Id_Buff_Rd_Data   ) , //(O) FIFO Read Data
    .O_Data_Num   ( R_Id_Buff_Data_Num  ) , //(O) FIFO Data Number
    .O_Wr_Full    ( R_Id_Buff_Wr_Full   ) , //(O) FIFO Write Full
    .O_Rd_Empty   ( R_Id_Buff_Rd_Empty  ) , //(O) FIFO Write Empty
    .O_Fifo_Err   ( R_Id_Buff_Fifo_Err  )   //(O) Fifo Error
  ) ;

  /////////////////////////////////////////////////////////
  assign    Axi_RBus_ID       = R_Id_Buff_Rd_Empty  ? {AIW{1'h1}}   : R_Id_Buff_Rd_Data ;   
  assign    Axi_ARBus_Pause   = R_Id_Buff_Wr_Full   | Axi_Rd_Pause  ; 
  assign    Ddr_ARBus_Pause   = Ddr_Rd_Pause  ;

  /////////////////////////////////////////////////////////
//555555555555555555555555555555555555555555555555555555555
//////////////////////   Ddr_Read   ///////////////////////
//666666666666666666666666666666666666666666666666666666666
//
//********************************************************/
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
//666666666666666666666666666666666666666666666666666666666
//////////////////////   Ddr_Read   ///////////////////////
//777777777777777777777777777777777777777777777777777777777
//
//********************************************************/
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
//777777777777777777777777777777777777777777777777777777777
//////////////////////   Ddr_Read   ///////////////////////
//888888888888888888888888888888888888888888888888888888888
//
//********************************************************/
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
//888888888888888888888888888888888888888888888888888888888
//////////////////////   Ddr_Read   ///////////////////////
//999999999999999999999999999999999999999999999999999999999
//
//********************************************************/
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
//999999999999999999999999999999999999999999999999999999999

endmodule

//////////////////////   Ddr_Read   ///////////////////////








/////////////////////   Ddr_Read_FiFo   ///////////////////
/**********************************************************
  Function Description:

  Establishment : Richard Zhu
  Create date   : 2021-03-01
  Versions      : V0.1
  Revision of records:
  Ver0.1

**********************************************************/

module  Ddr_Read_FiFo
(
  //System Signal
  Clk_RxDq        , //Clock Rx Dq
  Clk_Axi         , //Clock Axi
  Rst_RxDq        , //Reset In Clock Rx DQ
  Rst_Axi         , //Reset In Clock Axi
  //Axi RBus Signal
  O_R_ID          , //(O)[RdData]Read ID tag. 
  O_R_DATA        , //(O)[RdData]Read data.
  O_R_LAST        , //(O)[RdData]Read last. 
  O_R_RESP        , //(O)[RdData]Read response. 
  O_R_VALID       , //(O)[RdData]Read valid. 
  I_R_READY       , //(I)[RdData]Read ready. 
  //Test Interface 
  I_Test_Mode     , //(I)[Clk_Axi ] Test Mode 
  I_T_R_Rd_En     , //(I)[Clk Axi ] Test RBus Read Enable
  O_T_R_Rd_D      , //(O)[Clk Axi ] Test RBus Read Data
  O_T_R_Ready     , //(O)[Clk Axi ] Test RBus Read Buffer Full
  //DDR RBus Signal
  I_Ddr_Curr_ID   , //(I)[Clk_Axi ] DDR Current ID 
  I_Ddr_R_DVal    , //(I)[Clk_RxDq] DDR Read Bus Data Valid
  I_Ddr_R_Last    , //(I)[Clk_RxDq] DDR Read Bus Last Data 
  I_Ddr_R_Data    , //(I)[Clk_RxDq] DDR Read Bus Write Data
  I_Rd_Bst_End    , //(I)[Clk_RxDq] DDR Read Burst End
  O_Axi_RBus_RdEn , //(O)[Clk_Axi ] Axi AWBus Write Enable
  O_RD_ChkSum_Err , //(O)[Clk_Axi ] Read Data Checksum Error
  O_RD_Fifo_Spls  , //(O)[Clk_RxDq] DDR Read FIFO Surplus Burst Number
  O_RD_Fifo_Empty , //(O)[Clk_RxDq] DDR Read FIFO Empty
  O_RD_Fifo_Full    //(O)[Clk_RxDq] DDR Read Bus Buff Full  
);


  //Define  Parameter
  /////////////////////////////////////////////////////////  
  parameter   AXI_ID_WIDTH        = 8   ;   //AXI4总线ID的宽度
  parameter   AXI_DATA_WIDTH      = 128 ;   //AXI4总线数据的宽度
  parameter   DDR_DATA_WIDTH      = 16  ;   //DDR总线数据的宽度
  parameter   RD_DATA_FIFO_DEPTH  = 512 ;   //读数据FIFO深度

  /////////////
  localparam  DDR_BUS_DATA_WIDTH  = DDR_DATA_WIDTH * 2        ; //内部数据总线的宽度，为DDR数据总线的2倍
  localparam  DDR_BUS_BYTE_NUM    = DDR_BUS_DATA_WIDTH  / 8   ; //内部数据总线字节个数
  localparam  DDR_BUS_BYTE_SIZE   = $clog2(DDR_BUS_BYTE_NUM)  ; //内部数据尺寸，即为字节计数器宽度
  localparam  DDR_CHKSUM_WIDTH    = 2                         ; //DDR侧的校验和宽度

  localparam  AXI_BYTE_NUMBER     = AXI_DATA_WIDTH  / 8       ; //AXI4数据总线字节个数
  localparam  AXI_BYTE_SIZE       = $clog2(AXI_BYTE_NUMBER)   ; //AXI4数据尺寸，即为字节计数器宽度
  localparam  AXI_CHKSUM_WIDTH    = AXI_DATA_WIDTH  / DDR_DATA_WIDTH ; //AXI侧的校验和宽度

  localparam  DDR_BYTE_NUMBER     = DDR_DATA_WIDTH  / 8       ; //DDR数据总线字节个数
  localparam  DDR_BYTE_SIZE       = $clog2(DDR_BYTE_NUMBER)   ; //DDR数据尺寸，即为字节计数器宽度

  /////////////   DM、DQS宽度
  localparam  AXI_DM_WIDTH        = AXI_BYTE_NUMBER           ; //AXI侧掩码宽度
  localparam  DDR_DM_WIDTH        = DDR_BYTE_NUMBER           ; //DDR侧掩码宽度
  localparam  DDR_BUS_DM_WIDTH    = DDR_BUS_BYTE_NUM          ; //DDR内部掩码宽度
    
  /////////////   内部存储有关    
  localparam  BUFF_FIFO_DATA_WIDTH_RITIO  = AXI_DATA_WIDTH  / DDR_BUS_DATA_WIDTH          ; //Buffer/FIFO的数据宽度比
  localparam  BUFF_FIFO_WIDTH_RITIO_SIZE  = $clog2(BUFF_FIFO_DATA_WIDTH_RITIO)            ; //Buffer/FIFO的数据宽度比的计数器宽度

  localparam  RD_DATA_BUFF_WIDTH        = DDR_BUS_DATA_WIDTH  + AXI_CHKSUM_WIDTH          ; //读缓存的宽度
  localparam  RD_DATA_FIFO_WIDTH        = DDR_BUS_DATA_WIDTH  + DDR_CHKSUM_WIDTH + 2 + 2  ; //读FIFO的宽度（DATA+LAST+BSTEND+CHKSUM+CNT)
  localparam  RD_DATA_FIFO_ADDR_WIDTH   = $clog2(RD_DATA_FIFO_DEPTH)                      ; //读FIFO地址宽度  
  localparam  RD_DATA_BUFF_NUMBER       = BUFF_FIFO_DATA_WIDTH_RITIO * 2                  ; //读缓存个数，读缓存采用乒乓结构，要多用一倍的资源
  localparam  RD_DATA_BUFF_NUMBER_SIZE  = BUFF_FIFO_WIDTH_RITIO_SIZE                      ; //读缓存个数计数器宽度

  localparam  TEST_RD_DATA_WIDTH        = AXI_DATA_WIDTH  + AXI_ID_WIDTH + 1              ; //读测试的数据宽度；包括DATA/ID/LAST

  /////////////   缩写               
  localparam  AIW   = AXI_ID_WIDTH              ; //AXI总线ID的宽度  
  localparam  ADW   = AXI_DATA_WIDTH            ; //AXI总线数据的宽度
  localparam  ACW   = AXI_CHKSUM_WIDTH          ; //AXI侧的校验和宽度

  localparam  DDW   = DDR_DATA_WIDTH            ; //DDR总线数据的宽度
  localparam  DCW   = DDR_CHKSUM_WIDTH          ; //DDR侧的校验和宽度

  localparam  BDW   = DDR_BUS_DATA_WIDTH        ; //内部数据总线的宽度，为DDR数据总线的2倍

  localparam  RBW   = RD_DATA_BUFF_WIDTH        ; //读缓存的宽度
  localparam  RFW   = RD_DATA_FIFO_WIDTH        ; //读FIFO的宽度(DATA+LAST+BSTEND+CHKSUM)
  localparam  RFS   = RD_DATA_FIFO_ADDR_WIDTH   ; //读FIFO地址宽度  
  localparam  RBN   = RD_DATA_BUFF_NUMBER       ; //读缓存个数，读缓存采用乒乓结构，要多用一倍的资源
  localparam  RBS   = RD_DATA_BUFF_NUMBER_SIZE  ; //读缓存个数计数器宽度
  
  localparam  TDW   = TEST_RD_DATA_WIDTH        ; //读测试的数据宽度；包括DATA/ID/LAST
  /////////////////////////////////////////////////////////


  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////
  //System Signal
  input               Clk_RxDq        ; //Clock Rx Dq
  input               Clk_Axi         ; //Clock Axi
  input               Rst_RxDq        ; //Reset In Clock Rx DQ
  input               Rst_Axi         ; //Reset In Clock Axi
  //Axi RBus Signal 
  output  [AIW-1:0]   O_R_ID          ; //(O)[RdData]Read ID tag. 
  output  [ADW-1:0]   O_R_DATA        ; //(O)[RdData]Read data. 
  output              O_R_LAST        ; //(O)[RdData]Read last.  
  output  [    1:0]   O_R_RESP        ; //(O)[RdData]Read response.  
  output              O_R_VALID       ; //(O)[RdData]Read valid.  
  input               I_R_READY       ; //(I)[RdData]Read ready. 
  //Test Interface 
  input               I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  input               I_T_R_Rd_En     ; //(I)[Clk Axi ] 测试RBUS读允许
  output  [TDW-1:0]   O_T_R_Rd_D      ; //(O)[Clk Axi ] 测试RBUS读数据;包括DATA/ID/LAST
  output              O_T_R_Ready     ; //(O)[Clk Axi ] 测试RBUS忙，不能接收指令  
  //DDR RBus Signal
  input               I_Ddr_R_DVal    ; //(I)从DDR读出一个有效数
  input   [AIW-1:0]   I_Ddr_Curr_ID   ; //(I)DDR Current ID 
  input               I_Rd_Bst_End    ; //(I)DDR Burst End
  input               I_Ddr_R_Last    ; //(I)DDR Read Bus Last Data 
  input   [BDW-1:0]   I_Ddr_R_Data    ; //(I)DDR Read Bus Write Data
  output              O_Axi_RBus_RdEn ; //(O)[Clk_Axi ] 读地址总线写允许（R_READY & R_VALID)
  output              O_RD_ChkSum_Err ; //(O)[Clk_Axi ] 校验和出错，错误产生在数据传输过程中
  output              O_RD_Fifo_Empty ; //(O)读数据FIFO空
  output              O_RD_Fifo_Full  ; //(O)读数据FIFO满
  output  [    7:0]   O_RD_Fifo_Spls  ; //(O)读数据FIFO剩余空间

  //O_RD_Fifo_Spls    读数据FIFO剩余空间，用于操作仲裁
  //    用于仲裁是判断读数据FIFO是否能容纳一次Burst或一次最小分割单位的访问
  //    在有多个访问需求时才需要对该项进行判断
  /////////////////////////////////////////////////////////

/////////////////////   Ddr_Read_FiFo   ///////////////////
//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire              Axi_R_READY       = I_R_READY       ; //(I)[RdData]Read ready. 
  
  wire              Ddr_Rd_Bst_End    = I_Rd_Bst_End    ; //(I)DDR Burst End
  wire  [AIW-1:0]   RBus_Curr_ID      = I_Ddr_Curr_ID   ; //(I)DDR Current ID 
  wire              Ddr_RBus_DVal     = I_Ddr_R_DVal    ; //(I)DDR Read Bus Data Valid
  wire              Ddr_RBus_Last     = I_Ddr_R_Last    ; //(I)DDR Read Bus Last Data 
  wire  [BDW-1:0]   Ddr_RBus_Data     = I_Ddr_R_Data    ; //(I)DDR Read Bus Write Data
  
  wire              Test_Mode         = I_Test_Mode     ; //(I)[Clk_Axi ] 测试模式，高有效
  wire              Test_RBus_RdEn    = I_T_R_Rd_En     ; //(I)[Clk Axi ] 测试RBUS读允许
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000
/////////////////////   Ddr_Read_FiFo   ///////////////////
//111111111111111111111111111111111111111111111111111111111
//存储从DDR PHY接口恢复出来的数据
//传输数据的内容中加入了三个标志：
//Ddr_Rd_Bst_End  : 用于同步数据计数器；
//Ddr_Read_ChkSum : 检查数据的传输的正确性
//Ddr_Read_Cnt    : 检查数据的顺序
//********************************************************/
  /////////////////////////////////////////////////////////  
  wire  [DCW-1:0]    Ddr_Read_ChkSum ;  

  defparam  U1_Ddr_Rd_ChkSum.DATA_IN_WIDTH  =  DDR_BUS_DATA_WIDTH  ;  
  defparam  U1_Ddr_Rd_ChkSum.CHKSUM_WIDTH   =  DDR_CHKSUM_WIDTH    ;

  Calc_Data_ChkSum  U1_Ddr_Rd_ChkSum
  (
    .I_Data       ( Ddr_RBus_Data   ) , //(I)Data Input 
    .O_Chk_Sum    ( Ddr_Read_ChkSum )   //(O)Check Sum
  );

  /////////////////////////////////////////////////////////
  reg   [1:0]   Ddr_Read_Cnt   =  2'h0  ;

  always  @(posedge Clk_RxDq) if (Ddr_Rd_Bst_End)   Ddr_Read_Cnt  <=  Ddr_Read_Cnt + 2'h1 ;

  /////////////////////////////////////////////////////////

  wire  [RFW-1:0]   RBus_Fifo_WrData  ; //(I)Write Data

  assign  RBus_Fifo_WrData  = { Ddr_RBus_Last   ,
                                Ddr_Rd_Bst_End  ,
                                Ddr_Read_Cnt    ,
                                Ddr_Read_ChkSum ,
                                Ddr_RBus_Data   } ;

  /////////////////////////////////////////////////////////
  wire              RBus_Fifo_WrEn      = Ddr_RBus_DVal ; //(I)Write Enable
  
  wire  [RFS  :0]   RBus_Fifo_DataNum   ; //(O)Data Number In Fifo
  wire              RBus_Fifo_WrErr     ; //(O)Write Error
  wire              RBus_Fifo_WrFull    ; //(O)Write Full 
  wire              RBus_Fifo_AlmFull   ; //(O)almost Full
  
  wire              RBus_Fifo_RdEn      ; //(I)Read Enable

  wire              RBus_Fifo_RdErr     ; //(O)Read Error
  wire              RBus_Fifo_RdEmpty   ; //(O)Read FifoEmpty
  wire              RBus_Fifo_AlmEmpty  ; //(O)almost Empty
  wire              RBus_Fifo_DataVal   ; //(O)Data Valid
  wire  [RFW-1:0]   RBus_Fifo_RdData    ; //(O)Read Data

  defparam  U4_RBus_Fifo.FIFO_MODE        = "ShowAhead"         ; //"Normal"; //"ShowAhead"
  defparam  U4_RBus_Fifo.DATA_WIDTH       = RD_DATA_FIFO_WIDTH  ;     
  defparam  U4_RBus_Fifo.DATA_DEPTH       = RD_DATA_FIFO_DEPTH  ; 
  defparam  U4_RBus_Fifo.AFULL_THRESHOLD  = 64  ;
  defparam  U4_RBus_Fifo.AEMPTY_THRESHOLD = 1   ;
      
  SC_FIFO   U4_RBus_Fifo
  (   
    //System Signal
    .SysClk     ( Clk_RxDq            ) , //(I)System Clock
    .Reset      ( Rst_RxDq            ) , //(I)System Reset (Sync / High Active)
    .DataNum    ( RBus_Fifo_DataNum   ) , //(O)Data Number In Fifo
    //Write Signal                             
    .WrEn       ( RBus_Fifo_WrEn      ) , //(I)Write Enable
    .WrErr      ( RBus_Fifo_WrErr     ) , //(O)Write Error
    .WrFull     ( RBus_Fifo_WrFull    ) , //(O)Write Full 
    .AlmFull    ( RBus_Fifo_AlmFull   ) , //(O)almost Full
    .WrData     ( RBus_Fifo_WrData    ) , //(I)Write Data
    //Read Signal                           
    .RdEn       ( RBus_Fifo_RdEn      ) , //(I)Read Enable
    .RdErr      ( RBus_Fifo_RdErr     ) , //(O)Read Error
    .RdEmpty    ( RBus_Fifo_RdEmpty   ) , //(O)Read FifoEmpty
    .AlmEmpty   ( RBus_Fifo_AlmEmpty  ) , //(O)almost Empty
    .DataVal    ( RBus_Fifo_DataVal   ) , //(O)Data Valid 
    .RdData     ( RBus_Fifo_RdData    )   //(O)Read Data
  );

  /////////////////////////////////////////////////////////
  wire  [DCW-1:0] RBus_Fifo_ChkSum  ;
  wire  [    1:0] RBus_Fifo_Cnt     ;
  wire            RBus_Fifo_Last    ;
  wire            RBus_Fifo_Bst_End ;
  wire  [BDW-1:0] RBus_Fifo_Data    ;

  assign  { RBus_Fifo_Last    ,
            RBus_Fifo_Bst_End ,
            RBus_Fifo_Cnt     , 
            RBus_Fifo_ChkSum  ,            
            RBus_Fifo_Data    } = RBus_Fifo_RdData  ;

  /////////////////////////////////////////////////////////
  localparam    FIFO_SURPLUS_SIZE   = RD_DATA_FIFO_ADDR_WIDTH - RD_DATA_BUFF_NUMBER_SIZE ;
  localparam    FSS = FIFO_SURPLUS_SIZE ;
  /////////////////  此处运算没有考虑大于255个Burst的情况  ??
  reg   [7  :0]   Fifo_Surplus_Num  = 8'h0  ;   //Surplus

  wire  [RFS+1:0] Calc_Surplus_Num  = RD_DATA_FIFO_DEPTH[RFS+1:0] - {1'h0,RBus_Fifo_DataNum}  ;
 
  always  @(posedge Clk_RxDq)   Fifo_Surplus_Num  <=  Calc_Surplus_Num[RFS:RBS]  ;

  /////////////////////////////////////////////////////////
  wire          O_RD_Fifo_Full    = RBus_Fifo_AlmFull ; //(O)DDR Read Bus Buff Full  
  wire  [7:0]   O_RD_Fifo_Spls    = Fifo_Surplus_Num  ; //(O)DDR Read FIFO Surplus Burst Number
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111
/////////////////////   Ddr_Read_FiFo   ///////////////////
//222222222222222222222222222222222222222222222222222222222
//
//********************************************************/
  localparam  [RBS-1:0]   FIFO_RD_CNT_INI  = BUFF_FIFO_DATA_WIDTH_RITIO-{{RBS{1'h0}},1'h1}; //FIFO读计数器的初始化值
  /////////////////////////////////////////////////////////
  reg               RBus_Buff_Busy  = 1'h0          ;
  reg               Fifo_Read_En    = 1'h0          ;
  // reg   [RBS-1:0]   Fifo_Read_Cnt   = {RBS{1'h0}}   ;
  
  wire    Fifo_Buff_Valid   = ~(RBus_Fifo_RdEmpty | RBus_Buff_Busy) ;
  always  @(posedge Clk_RxDq)
  begin
    if (Rst_RxDq)           Fifo_Read_En  <=  1'h0              ;
    else if (Fifo_Read_En)  Fifo_Read_En  <=  (~RBus_Fifo_AlmEmpty) 
                              & (~(RBus_Fifo_Bst_End & RBus_Buff_Busy));    
    else                    Fifo_Read_En  <=  Fifo_Buff_Valid   ;
  end
  // always  @(posedge Clk_RxDq)
  // begin
  //   if (Rst_RxDq)                   Fifo_Read_Cnt   <=  FIFO_RD_CNT_INI;  
  //   else if (~Fifo_Read_En)         Fifo_Read_Cnt   <=  Fifo_Read_Cnt   ;  
  //   else if (|Fifo_Read_Cnt)        Fifo_Read_Cnt   <=  Fifo_Read_Cnt   - {{RBS-1{1'h0}} , 1'h1}  ;
  //   else if (RBus_Fifo_Bst_End)     Fifo_Read_Cnt   <=  FIFO_RD_CNT_INI ;
  // end

  assign  RBus_Fifo_RdEn = Fifo_Read_En  ;

  /////////////////////////////////////////////////////////
  reg   [RBN-1:0]   Buff_Write_Sft  = {RBN{1'h0}}  ;
  reg               Buff_Write_Sel  = 1'h0         ;
  reg   [RBN-1:0]   Buff_Write_En   = {RBN{1'h0}}  ;
    
  always  @(posedge Clk_RxDq) 
  begin
    if (Rst_RxDq)   Buff_Write_Sel  <=  1'h0  ;
    else  if (RBus_Fifo_Bst_End & Fifo_Read_En)  Buff_Write_Sel  <=  ~Buff_Write_Sel ;
  end
  always  @(posedge Clk_RxDq)
  begin
    if (Rst_RxDq)                 Buff_Write_Sft  <=  {{RBN-1{1'h0}},1'h1}    ;
    else if (~Fifo_Read_En)       Buff_Write_Sft  <=  Buff_Write_Sft          ;
    else if (~RBus_Fifo_Bst_End)  Buff_Write_Sft  <=  {Buff_Write_Sft[RBN-2:0],Buff_Write_Sft[RBN-1]} ;
    else if (Buff_Write_Sel)      Buff_Write_Sft  <=  {{RBN-1{1'h0}},1'h1} ;
    else                          Buff_Write_Sft  <=  {Buff_Write_Sft[RBN-2:0],Buff_Write_Sft[RBN-1]} ;
  end
  
  always  @(posedge Clk_RxDq)   Buff_Write_En   <=  Buff_Write_Sft & {RBN{Fifo_Read_En}} ;

  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222
/////////////////////   Ddr_Read_FiFo   ///////////////////
//333333333333333333333333333333333333333333333333333333333
//
//********************************************************/
  // localparam  RBW   = RD_DATA_BUFF_WIDTH        ; //读缓存的宽度
  /////////////////////////////////////////////////////////
  reg   [RBW-1:0]   Buff_Write_Data   = {RBW{1'h0}} ;
  reg               Buff_Write_Last   = 1'h0  ;
  
  always  @(posedge Clk_RxDq)   Buff_Write_Data <=  { RBus_Fifo_ChkSum , RBus_Fifo_Data } ;
  always  @(posedge Clk_RxDq)   Buff_Write_Last <=  RBus_Fifo_Last  ;

  /////////////////////////////////////////////////////////
  wire  [    1:0]   Buff_Read_En    ;      
  wire  [RBN-1:0]   RBus_Buff_Rd_En ; //(I) FIFO Read Enable

  assign  RBus_Buff_Rd_En[RBN-1:RBN/2]  = {(RBN/2){Buff_Read_En[1]}}  ;
  assign  RBus_Buff_Rd_En[RBN/2-1:  0]  = {(RBN/2){Buff_Read_En[0]}}  ;

  /////////////////////////////////////////////////////////
  wire  [RBN-1:0]   RBus_Buff_Wr_En = Buff_Write_En   ;

  wire  [RBW-1:0]   RBus_Buff_Wr_Data  [RBN-1:0]  ; //(I) FIFO Write Data
  wire  [RBW-1:0]   RBus_Buff_Rd_Data  [RBN-1:0]  ; //(O) FIFO Read Data  
       
  wire  [ADW-1:0]   RBus_Buff_Data    [1:0] ;
  wire  [ACW-1:0]   RBus_Buff_ChkSum  [1:0] ;

  genvar  i ;
  generate
    for (i=0;i<RBN;i=i+1)
    begin : RBus_Data2Axi_Buff

      assign      RBus_Buff_Wr_Data[i]            = Buff_Write_Data  ;
      defparam    U2_RBus_Data_Buffer.OUT_REG     = "No"  ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
      defparam    U2_RBus_Data_Buffer.DATA_WIDTH  = RD_DATA_BUFF_WIDTH  ; //Data Width
      defparam    U2_RBus_Data_Buffer.DATA_DEPTH  = 8                   ; //Address Width

      Ddr_Ctrl_Sc_Fifo  U2_RBus_Data_Buffer
      (
        .Sys_Clk      ( Clk_RxDq              ) , //System Clock
        .Sync_Clr     ( Rst_RxDq              ) , //Sync Reset
        .I_Wr_En      ( RBus_Buff_Wr_En   [i] ) , //(I) FIFO Write Enable
        .I_Wr_Data    ( RBus_Buff_Wr_Data [i] ) , //(I) FIFO Write Data
        .I_Rd_En      ( RBus_Buff_Rd_En   [i] ) , //(I) FIFO Read Enable
        .O_Rd_Data    ( RBus_Buff_Rd_Data [i] ) , //(O) FIFO Read Data
        .O_Data_Num   (                       ) , //(O) FIFO Data Number
        .O_Wr_Full    (                       ) , //(O) FIFO Write Full
        .O_Rd_Empty   (                       ) , //(O) FIFO Write Empty
        .O_Fifo_Err   (                       )   //(O) Fifo Error
      ) ;
      
      if (i<RBN/2)  assign RBus_Buff_Data   [0][( i       +1)*BDW-1 :  i       *BDW]  = RBus_Buff_Rd_Data[i][BDW-1:0]; 
      else          assign RBus_Buff_Data   [1][((i-RBN/2)+1)*BDW-1 : (i-RBN/2)*BDW]  = RBus_Buff_Rd_Data[i][BDW-1:0];
      if (i<RBN/2)  assign RBus_Buff_ChkSum [0][( i       +1)*DCW-1 :  i       *DCW]  = RBus_Buff_Rd_Data[i][RBW-1:BDW]; 
      else          assign RBus_Buff_ChkSum [1][((i-RBN/2)+1)*DCW-1 : (i-RBN/2)*DCW]  = RBus_Buff_Rd_Data[i][RBW-1:BDW];
    end
  endgenerate

  /////////////////////////////////////////////////////////
  wire  [1:0]   RBus_Flag_Wr_En     ;

  assign        RBus_Flag_Wr_En[1]  = Buff_Write_En[RBN  -1] ;
  assign        RBus_Flag_Wr_En[0]  = Buff_Write_En[RBN/2-1] ;

  /////////////////////////////////////////////////////////
  wire  [1:0]   RBus_Flag_Rd_En     = Buff_Read_En        ; //(I) FIFO Read Enable

  wire  [2:0]   RBus_Flag_Wr_Data   [1:0] ; //(I) FIFO Write Data
  wire  [2:0]   RBus_Flag_Rd_Data   [1:0] ; //(O) FIFO Read Data  

  wire  [3:0]   RBus_Flag_Data_Num  [1:0] ; //(O) Ram Data Number
  wire  [1:0]   RBus_Flag_Wr_Full         ; //(O) FIFO Write Full
  wire  [1:0]   RBus_Flag_Rd_Empty        ; //(O) FIFO Write Empty
  wire  [1:0]   RBus_Flag_Fifo_Err        ; //(O) FIFO Error

  genvar  j ;
  generate
    for (j=0;j<2;j=j+1)
    begin : RBus_Flag2Axi_Buff

      assign    RBus_Flag_Wr_Data[j][2:1] = RBus_Fifo_Cnt   ;    
      assign    RBus_Flag_Wr_Data[j][  0] = Buff_Write_Last ;

      defparam  U2_RBus_Flag_Buffer.OUT_REG     = "No"  ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
      defparam  U2_RBus_Flag_Buffer.DATA_WIDTH  = 3     ; //Data Width
      defparam  U2_RBus_Flag_Buffer.DATA_DEPTH  = 8     ; //Address Width

      Ddr_Ctrl_Sc_Fifo  U2_RBus_Flag_Buffer
      ( 
        .Sys_Clk      ( Clk_RxDq              ) , //System Clock
        .Sync_Clr     ( Rst_RxDq              ) , //Sync Reset
        .I_Wr_En      ( RBus_Flag_Wr_En   [j] ) , //(I) FIFO Write Enable
        .I_Wr_Data    ( RBus_Flag_Wr_Data [j] ) , //(I) FIFO Write Data
        .I_Rd_En      ( RBus_Flag_Rd_En   [j] ) , //(I) FIFO Read Enable
        .O_Rd_Data    ( RBus_Flag_Rd_Data [j] ) , //(O) FIFO Read Data
        .O_Data_Num   ( RBus_Flag_Data_Num[j] ) , //(O) FIFO Data Number
        .O_Wr_Full    ( RBus_Flag_Wr_Full [j] ) , //(O) FIFO Write Full
        .O_Rd_Empty   ( RBus_Flag_Rd_Empty[j] ) , //(O) FIFO Write Empty
        .O_Fifo_Err   ( RBus_Flag_Fifo_Err[j] )   //(O) Fifo Error
      ) ;
    end
  endgenerate

  /////////////////////////////////////////////////////////
  wire  [1:0]   RBus_Flag_Rd_Cnt  [1:0] ;
  wire  [1:0]   RBus_Flag_Rd_Last       ;

  assign  { RBus_Flag_Rd_Cnt [0]  ,
            RBus_Flag_Rd_Last[0]  } = RBus_Flag_Rd_Data[0]  ;
  assign  { RBus_Flag_Rd_Cnt [1]  ,
            RBus_Flag_Rd_Last[1]  } = RBus_Flag_Rd_Data[1]  ;

  /////////////////////////////////////////////////////////

  always  @(posedge Clk_RxDq)   RBus_Buff_Busy        = (&RBus_Flag_Data_Num[1][2:1]) ;
  
  /////////////////////////////////////////////////////////
  reg   [1:0]   RBus_Buff_Alm_Empty = 1'h1  ;

  always  @( * )  RBus_Buff_Alm_Empty[0]  = (~|RBus_Flag_Data_Num[0][3:1]) & (~RBus_Flag_Wr_En[0]) ;
  always  @( * )  RBus_Buff_Alm_Empty[1]  = (~|RBus_Flag_Data_Num[1][3:1]) & (~RBus_Flag_Wr_En[1]) ;

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333
/////////////////////   Ddr_Read_FiFo   ///////////////////
//444444444444444444444444444444444444444444444444444444444
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg           Axi_RBus_Rd_Sel = 1'h0  ; //AXI读总线数据选择，AXI时钟域，用于选择采用哪个通道
  reg   [1:0]   Axi_Rd_Sel_Reg  = 2'h0  ; //AXI选择寄存器
  reg           Axi_Rd_Sel_Rise = 1'h0  ;
  reg           Axi_Rd_Sel_Fall = 1'h0  ;

  always  @(posedge Clk_RxDq)   Axi_Rd_Sel_Reg  <=  { Axi_Rd_Sel_Reg[0]  
                                                    , Axi_RBus_Rd_Sel   } ;

  always  @( * )   Axi_Rd_Sel_Rise <=  (Axi_Rd_Sel_Reg   ==  2'h1 ) ;
  always  @( * )   Axi_Rd_Sel_Fall <=  (Axi_Rd_Sel_Reg   ==  2'h2 ) ;

  assign  Buff_Read_En[0]   = Axi_Rd_Sel_Rise ;
  assign  Buff_Read_En[1]   = Axi_Rd_Sel_Fall ;

  /////////////////////////////////////////////////////////
  reg   [1:0]   RBus_Rd_Empty_Reg ;
  wire  [1:0]   RBus_Buff_Pre_Rd  ;
    
  always  @(posedge Clk_RxDq)       RBus_Rd_Empty_Reg   <=  RBus_Flag_Rd_Empty    ;

  assign  RBus_Buff_Pre_Rd      = ( RBus_Rd_Empty_Reg   &  ~RBus_Flag_Rd_Empty  ) ;

  /////////////////////////////////////////////////////////
  reg  [1:0]  RBus_RdD_Flag   = 1'h0  ; //读总线数据有效

  always  @(posedge Clk_RxDq)   
  begin 
    if (Rst_RxDq)                     RBus_RdD_Flag[0]  <=  1'h0  ;
    else if (RBus_Buff_Pre_Rd[0])     RBus_RdD_Flag[0]  <= ~RBus_RdD_Flag[0]  ;
    else if (RBus_Buff_Alm_Empty[0])  RBus_RdD_Flag[0]  <=  RBus_RdD_Flag[0]  ;
    else if (Buff_Read_En[0])         RBus_RdD_Flag[0]  <= ~RBus_RdD_Flag[0]  ;
  end  
  always  @(posedge Clk_RxDq)   
  begin 
    if (Rst_RxDq)                     RBus_RdD_Flag[1]  <=  1'h0  ;
    else if (RBus_Buff_Pre_Rd[1])     RBus_RdD_Flag[1]  <= ~RBus_RdD_Flag[1]  ;
    else if (RBus_Buff_Alm_Empty[1])  RBus_RdD_Flag[1]  <=  RBus_RdD_Flag[1]  ;
    else if (Buff_Read_En[1])         RBus_RdD_Flag[1]  <= ~RBus_RdD_Flag[1]  ;
  end
  
  /////////////////////////////////////////////////////////
  reg  [1:0]    RBus_Data_Valid = 2'h0 ;

  always  @(posedge Clk_RxDq)         RBus_Data_Valid   <=  RBus_RdD_Flag  ;

  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444
/////////////////////   Ddr_Read_FiFo   ///////////////////
//555555555555555555555555555555555555555555555555555555555
//
//********************************************************/
  /////////////////////////////////////////////////////////
  localparam  AXI_BUFF_DATA_WIDTH =  AXI_DATA_WIDTH + AXI_CHKSUM_WIDTH  + 1 + 2 ; //AXI缓存数据宽度（DATA+CHKSUM+LAST+CNT)
  localparam  ABDW =  AXI_BUFF_DATA_WIDTH ; //AXI缓存数据宽度（DATA+CHKSUM+LAST)
  /////////////////////////////////////////////////////////
  reg           Axi_RBuff_WrEn  = 1'h0  ;
  reg   [1:0]   Axi_Data_Val_Reg  [1:0] ;
  wire  [1:0]   Axi_Data_Val_Chg        ;
  wire  [1:0]   Axi_Data_Val_En         ;        

  always @(posedge Clk_Axi)   
  begin
    if (Rst_Axi)                  Axi_Data_Val_Reg[0][0]  <=  1'h0  ;
    else if(Axi_Data_Val_En[0])   Axi_Data_Val_Reg[0][0]  <=  RBus_Data_Valid[0] ;
  end
  always @(posedge Clk_Axi)   
  begin
    if (Rst_Axi)                  Axi_Data_Val_Reg[1][0]  <=  1'h0  ;
    else if(Axi_Data_Val_En[1])   Axi_Data_Val_Reg[1][0]  <=  RBus_Data_Valid[1] ;
  end
  always @(posedge Clk_Axi)  
  begin
    if (Rst_Axi)            { Axi_Data_Val_Reg[1][1]  ,   Axi_Data_Val_Reg[0][1]} <=  2'h0  ;
    else if (Axi_RBuff_WrEn)
    begin
      if (Axi_RBus_Rd_Sel)    Axi_Data_Val_Reg[1][1]  <=  Axi_Data_Val_Reg[1][0]  ;
      else                    Axi_Data_Val_Reg[0][1]  <=  Axi_Data_Val_Reg[0][0]  ;
    end
  end

  /////////////////////////////////////////////////////////
  assign  Axi_Data_Val_Chg[0] = ( Axi_Data_Val_Reg[0][0]  ^ Axi_Data_Val_Reg[0][1]  ) ;  
  assign  Axi_Data_Val_Chg[1] = ( Axi_Data_Val_Reg[1][0]  ^ Axi_Data_Val_Reg[1][1]  ) ; 
  assign  Axi_Data_Val_En[0]  = ~ Axi_Data_Val_Chg[0]     ;  
  assign  Axi_Data_Val_En[1]  = ~ Axi_Data_Val_Chg[1]     ; 

  wire    Axi_Data_Valid  =   Axi_RBus_Rd_Sel ? Axi_Data_Val_Chg[1]  : Axi_Data_Val_Chg[0]  ;

  /////////////////////////////////////////////////////////
  reg     Axi_RBuff_Val   = 1'h0  ;

  always @(posedge Clk_Axi)  
  begin
    if (Rst_Axi)    Axi_RBuff_WrEn    <=  1'h0            ;
    else            Axi_RBuff_WrEn    <=  Axi_Data_Valid  & Axi_RBuff_Val ; 
  end

  /////////////////////////////////////////////////////////
  always @(posedge Clk_Axi) 
  begin
    if (Rst_Axi)              Axi_RBus_Rd_Sel <=  1'h0 ;
    else if (Axi_Data_Valid)  
    begin
      if(Axi_RBuff_WrEn)      Axi_RBus_Rd_Sel <=  ~Axi_RBus_Rd_Sel ;
    end
  end
  
  /////////////////////////////////////////////////////////
  wire  [ABDW-1:0]  Axi_RBuff_Wr_Data   = { RBus_Flag_Rd_Data [Axi_RBus_Rd_Sel] ,
                                            RBus_Buff_ChkSum  [Axi_RBus_Rd_Sel] ,
                                            RBus_Buff_Data    [Axi_RBus_Rd_Sel] } ;
  
  /////////////////////////////////////////////////////////
  wire              Axi_RBuff_Wr_En     = Axi_RBuff_WrEn & Axi_Data_Valid ;

  wire              Axi_RBuff_Rd_En     ; //(I) FIFO Read Enable

  wire  [ABDW-1:0]  Axi_RBuff_Rd_Data   ; //(O) FIFO Read Data  
  wire  [     3:0]  Axi_RBuff_Data_Num  ; //(O) Ram Data Number
  wire              Axi_RBuff_Wr_Full   ; //(O) FIFO Write Full
  wire              Axi_RBuff_Rd_Empty  ; //(O) FIFO Write Empty
  wire              Axi_RBuff_Fifo_Err  ; //(O) FIFO Error

  defparam    U2_Axi_R_Buffer.OUT_REG     = "No"  ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
  defparam    U2_Axi_R_Buffer.DATA_WIDTH  = AXI_BUFF_DATA_WIDTH ; //Data Width  
  defparam    U2_Axi_R_Buffer.DATA_DEPTH  = 8                   ; //Address Width

  Ddr_Ctrl_Sc_Fifo  U2_Axi_R_Buffer
  (
    .Sys_Clk      ( Clk_Axi             ) , //System Clock
    .Sync_Clr     ( Rst_Axi             ) , //Sync Reset
    .I_Wr_En      ( Axi_RBuff_Wr_En     ) , //(I) FIFO Write Enable
    .I_Wr_Data    ( Axi_RBuff_Wr_Data   ) , //(I) FIFO Write Data
    .I_Rd_En      ( Axi_RBuff_Rd_En     ) , //(I) FIFO Read Enable
    .O_Rd_Data    ( Axi_RBuff_Rd_Data   ) , //(O) FIFO Read Data
    .O_Data_Num   ( Axi_RBuff_Data_Num  ) , //(O) FIFO Data Number
    .O_Wr_Full    ( Axi_RBuff_Wr_Full   ) , //(O) FIFO Write Full
    .O_Rd_Empty   ( Axi_RBuff_Rd_Empty  ) , //(O) FIFO Write Empty
    .O_Fifo_Err   ( Axi_RBuff_Fifo_Err  )   //(O) Fifo Error
  ) ;

   always @(posedge Clk_Axi)  Axi_RBuff_Val <= (~Axi_RBuff_Data_Num[2])  ;

  /////////////////////////////////////////////////////////
  reg       RD_Fifo_Empty = 1'h0  ;

  always @(posedge Clk_Axi)   RD_Fifo_Empty <=  RBus_Fifo_RdEmpty & Axi_RBuff_Rd_Empty
                                              & (&RBus_Flag_Rd_Empty) ;

  /////////////////////////////////////////////////////////
  wire    O_RD_Fifo_Empty = RD_Fifo_Empty ; //(O)读数据FIFO空
//555555555555555555555555555555555555555555555555555555555
/////////////////////   Ddr_Read_FiFo   ///////////////////
//666666666666666666666666666666666666666666666666666666666
//
//********************************************************/
  /////////////////////////////////////////////////////////
  wire    Axi_R_VALID       = ~Axi_RBuff_Rd_Empty; // [RdData]Read valid.  
  wire    Axi_RBus_RdEn     = Test_Mode     ? Test_RBus_RdEn  
                            : (Axi_R_VALID  & Axi_R_READY   ) ;

  assign  Axi_RBuff_Rd_En   = Axi_RBus_RdEn ;

  /////////////////////////////////////////////////////////
  wire    [ADW-1:0]   Axi_R_DATA    ; //[RdData]Read data. 
  wire    [    1:0]   Axi_R_Cnt     ; //[RdData]Read data. 
  wire    [ACW-1:0]   Axi_R_ChkSum  ; 
  wire                Axi_R_LAST    ; //[RdData]Read last.  

  assign  { Axi_R_Cnt     ,
            Axi_R_LAST    ,
            Axi_R_ChkSum  ,
            Axi_R_DATA    } = Axi_RBuff_Rd_Data ;

  /////////////////////////////////////////////////////////
  reg   [AIW-1:0]   Axi_R_ID    = {AIW{1'h0}} ; //(O)[RdData]Read ID tag. 
  reg   [    1:0]   Axi_R_RESP  = 2'h0        ; //(O)[RdData]Read response.  

  always @(posedge Clk_Axi)   Axi_R_ID    <=   RBus_Curr_ID ;
  always @(posedge Clk_Axi)   Axi_R_RESP  <=   2'h2 ;

  /////////////////////////////////////////////////////////
  wire  [TDW-1:0]   Test_RBus_RdD   = { Axi_R_LAST  ,
                                        Axi_R_ID    ,
                                        Axi_R_DATA  } ;

  /////////////////////////////////////////////////////////
  wire  [TDW-1:0]   O_T_R_Rd_D      = Test_RBus_RdD ; //(O)[Clk Axi ] 测试RBUS读数据;包括DATA/ID/LAST
  wire              O_T_R_Ready     = Axi_R_VALID   ; //(O)[Clk Axi ] 测试RBUS忙，不能接收指令  
  wire              O_Axi_RBus_RdEn = Axi_RBus_RdEn ; //(O)[Clk_Axi ] 读地址总线写允许（R_READY & R_VALID)
  /////////////////////////////////////////////////////////
  wire  [AIW-1:0]   O_R_ID      = Axi_R_ID      ; //(O)[RdData]Read ID tag. 
  wire  [ADW-1:0]   O_R_DATA    = Axi_R_DATA    ; //(O)[RdData]Read data. 
  wire              O_R_LAST    = Axi_R_LAST    ; //(O)[RdData]Read last.  
  wire  [    1:0]   O_R_RESP    = Axi_R_RESP    ; //(O)[RdData]Read response.  
  wire              O_R_VALID   = Axi_R_VALID   ; //(O)[RdData]Read valid.  
  /////////////////////////////////////////////////////////
  /////////////////////////////////////////////////////////
//666666666666666666666666666666666666666666666666666666666
/////////////////////   Ddr_Read_FiFo   ///////////////////
//777777777777777777777777777777777777777777777777777777777
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]   Axi_R_Cnt_Reg   = 2'h0  ;
  reg           Axi_R_Order_Err = 1'h0  ;

  
  always @(posedge Clk_Axi) if (Axi_RBus_RdEn)  Axi_R_Cnt_Reg   <=  ( Axi_R_Cnt   + 2'h1  ) ;
  always @(posedge Clk_Axi) if (Axi_RBus_RdEn)  Axi_R_Order_Err <=  ( Axi_R_Cnt !=  Axi_R_Cnt_Reg ) ;

  /////////////////////////////////////////////////////////
  wire  [ACW-1:0]    Axi_RBus_ChkSum ;

  defparam  U7_Axi_RBus_ChkSum.DATA_IN_WIDTH  =  AXI_DATA_WIDTH   ;  
  defparam  U7_Axi_RBus_ChkSum.CHKSUM_WIDTH   =  AXI_CHKSUM_WIDTH ;

  Calc_Data_ChkSum  U7_Axi_RBus_ChkSum
  (
    .I_Data       ( Axi_R_DATA      ) , //(I)Data Input 
    .O_Chk_Sum    ( Axi_RBus_ChkSum )   //(O)Check Sum
  );

  /////////////////////////////////////////////////////////
  reg   RdData_ChkSum_Err  = 1'h0  ;
  
  always @(posedge Clk_Axi) if (Axi_RBus_RdEn)  RdData_ChkSum_Err  <=  ( Axi_RBus_ChkSum !=  Axi_R_ChkSum  ) ;
  
  /////////////////////////////////////////////////////////  
  wire    O_RD_ChkSum_Err   = RdData_ChkSum_Err ; //(O)[Clk_Axi ] 校验和出错，错误产生在数据传输过程中
  /////////////////////////////////////////////////////////
//777777777777777777777777777777777777777777777777777777777
/////////////////////   Ddr_Read_FiFo   ///////////////////

endmodule

/////////////////////   Ddr_Read_FiFo   ///////////////////















/////////////////       Ddr_Rd_Data       ////////////////
/**********************************************************
  Function Description:
  
  DDR数据读取和对齐

    Read_Start  读启动信号，每间隔4个时钟周期发送一个
    Read_Error  读错误指示, 可用于错误侦测和故障诊断   
      2:  Err_TimeOut     当在指定窗口没有搜索到DQS的头
      1:  Err_Sdq_Code    在读数据过程中出现与数据选择不匹配的DQS
      0:  Err_Overflow    数据结束后DQS仍然有效 
    Read_Num    指示正在处理的读数据个数（用于调试）
    Ddr_DVal    DDR读数据有效
    Ddr_Data    DDR读数据，宽度为DDR的两倍
    Read_DVal   读数据有效
    Read_Data   读数据，宽度为DDR数据总线的8倍

  Establishment : Richard Zhu
  Create date   : 2022-11-06
  Versions      : V0.1
  Revision of records:
  Ver0.1

  --  2022-11-06  (Ddr_Rd_Data)
        创建文件并经过上板测试
  --  2022-11-08  (Ddr_Rd_Data)
        代码整理
  --  2022-11-12  (Ddr_Rd_Data)
    1、 调整读数据方案，确保读数据数量和读请求一致；
    2、 通过每组DQ对应的DQS来采集数据，每组数据通过FIFO进行对齐，保证DQS不一致时数据能对齐
    3、 增加 Read_Num 用于指示正在处理的读数据个数（用于调试） 
  
  V1.4
  /////////////////
  --  2023-03-20
    添加了 Dqs_State 用于指示Dqs的方向和变化，用于错误边界的测量 

**********************************************************/

module  Ddr_Rd_Data
(
  Sys_Clk         , //System Clock
  Sys_Rst_N       , //System Reset
  I_dqs_hi        , //(I)[DDR]  DRAM DQS Input Pos (High) 
  I_dqs_lo        , //(I)[DDR]  DRAM DQS Input Pos (Low ) 
  I_dq_hi         , //(I)[DDR]  DRAM DQ Input (High)
  I_dq_lo         , //(I)[DDR]  DRAM DQ Input (Low )
  I_Read_Start    , //(I)Read Start 
  O_Read_Num      , //(O)Read Data Number
  O_Read_Error    , //(O)Read Error  
  O_Dqs_State     , //(O)DQS State 0:Dir ; 1:Error ;2:Change 
  O_Ddr_DVal      , //(O)DDR Data Valid 
  O_Ddr_Data      , //(O)DDR Data 
  O_Ddr_Bst_End   , //(O)DDR Burst End
  O_Read_DVal     , //(O)Read Data Valid 
  O_Read_Data       //(O)Read Data
) ;

  //Define  Parameter
  /////////////////////////////////////////////////////////  
  parameter   DRAM_GROUP_NUM      = 2  ;
  parameter   DRAM_GROUP_WIDTH    = 8  ;

  localparam  DRAM_DATA_WIDTH     = DRAM_GROUP_NUM    * DRAM_GROUP_WIDTH  ;
  localparam  DRAM_DATA_PER_BST   = DRAM_DATA_WIDTH   * 8                 ;

  localparam  GROUP_WIDTH_PER_CLK = DRAM_GROUP_WIDTH  * 2 ; 
  localparam  DRAM_DATA_PER_CLK   = DRAM_DATA_WIDTH   * 2 ; 

  /////////////////
  localparam  DGN = DRAM_GROUP_NUM      ;
  localparam  DGW = DRAM_GROUP_WIDTH    ;
  localparam  GCW = GROUP_WIDTH_PER_CLK ;
  localparam  DDW = DRAM_DATA_WIDTH     ;
  localparam  DCW = DRAM_DATA_PER_CLK   ;
  localparam  DBW = DRAM_DATA_PER_BST   ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////  
  input               Sys_Clk       ; //System Clock
  input               Sys_Rst_N     ; //System Reset
  //DDR Interface
  input   [DGN-1:0]   I_dqs_hi      ; //(I)DRAM DQS Input Pos (High) 
  input   [DGN-1:0]   I_dqs_lo      ; //(I)DRAM DQS Input Pos (Low ) 
  input   [DDW-1:0]   I_dq_hi       ; //(I)DRAM DQ Input (High)
  input   [DDW-1:0]   I_dq_lo       ; //(I)DRAM DQ Input (Low )
  //Read Siganl 
  input               I_Read_Start  ; //(I)Read Start 
  output  [    2:0]   O_Read_Error  ; //(O)Read Error  
  output  [    2:0]   O_Dqs_State   ; //(O)DQS State 0:Dir ; 1:Error ;2:Change 
  output  [    2:0]   O_Read_Num    ; //(O)Read Data Number
  output              O_Ddr_DVal    ; //(O)DDR Data Valid 
  output  [DCW-1:0]   O_Ddr_Data    ; //(O)DDR Data 
  output              O_Ddr_Bst_End ; //(O)DDR Burst End
  output              O_Read_DVal   ; //(O)Read Data Valid 
  output  [DBW-1:0]   O_Read_Data   ; //(O)Read Data

  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  //把DQS、DQ的输入按Group组来安排
  wire  [    1:0]   Dqs_In  [DGN-1:0] ; //DRAM DQS Input 
  wire  [DGW-1:0]   Dq_Hi_In[DGN-1:0] ; //DRAM DQ Input (High)
  wire  [DGW-1:0]   Dq_Lo_In[DGN-1:0] ; //DRAM DQ Input (Low )
  
  genvar  i ;
  generate
    for (i=0;i<DRAM_GROUP_NUM;i=i+1)
    begin
    /////////////////////////
      assign  Dqs_In  [i][0]        = I_dqs_hi[i] ;
      assign  Dqs_In  [i][1]        = I_dqs_lo[i] ;
      assign  Dq_Hi_In[i][DGW-1:0]  = I_dq_hi [(i+1)*DGW-1 : i*DGW] ;
      assign  Dq_Lo_In[i][DGW-1:0]  = I_dq_lo [(i+1)*DGW-1 : i*DGW] ;
    /////////////////////////
    end
  endgenerate

  /////////////////////////////////////////////////////////
  wire  Read_Start    = I_Read_Start  ; //Read Start 
  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//DDR 输入的数据读取
//********************************************************/
  /////////////////////////////////////////////////////////
  reg                 Read_Ready  = 1'h0    ; 

  wire    [DGN-1:0]   Read_Valid            ; //(O)Read Enable  
  wire    [DGN-1:0]   Read_End              ; //(O)Read End 
  wire    [DGN-1:0]   Group_DVal            ; //(O)DRAM Group Data Valid
  wire    [    2:0]   Read_Error [DGN-1:0]  ; //(O)Read Error
  wire    [    2:0]   Dqs_State  [DGN-1:0]  ; //(O)(O)DQS State 0:Dir ; 1:Error ;2:Change 
  wire    [GCW-1:0]   Group_Data [DGN-1:0]  ; //(O)DRAM Group Data 

  genvar j  ;
  generate
    for (j=0;j<DRAM_GROUP_NUM;j=j+1)
    begin : Rd_Group_Data    
    /////////////////////////
      defparam    U1_Ddr_Rd_Group_Data.DRAM_GROUP_WIDTH    = DRAM_GROUP_WIDTH ;

      Ddr_Rd_Group_Data U1_Ddr_Rd_Group_Data
      (
        .Sys_Clk        ( Sys_Clk         ) , //System Clock
        .I_Ddr_Dqs      ( Dqs_In      [j] ) , //(I)DRAM DQS (0:High 1:Low)
        .I_Ddr_Dq_Hi    ( Dq_Hi_In    [j] ) , //(I)DRAM DQ Input (High)
        .I_Ddr_Dq_Lo    ( Dq_Lo_In    [j] ) , //(I)DRAM DQ Input (Low )
        .I_Read_Start   ( Read_Start      ) , //(I)Read_Start
        .I_Read_Ready   ( Read_Ready      ) , //(O)Read Ready
        .O_Read_Valid   ( Read_Valid  [j] ) , //(O)Read Valid  
        .O_Read_End     ( Read_End    [j] ) , //(O)Read End 
        .O_Read_Error   ( Read_Error  [j] ) , //(O)Read Error
        .O_Dqs_State    ( Dqs_State   [j] ) , //(O)DQS State 0:Dir ; 1:Error ;2:Change 
        .O_Group_DVal   ( Group_DVal  [j] ) , //(O)DRAM Group Data Valid
        .O_Group_Data   ( Group_Data  [j] )   //(O)DRAM Group Data 
      ) ;
    /////////////////////////      
    end    
  endgenerate 

  /////////////////////////////////////////////////////////
  reg   [DGN-1:0]   Dqs_Read_Val  = {DGN{1'h0}} ; //用于对齐 Read_Valid 
  wire              Dqs_Read_En   ;               //对齐的Read_Valid 

  always  @(posedge Sys_Clk or negedge Sys_Rst_N) 
  begin
    if (~Sys_Rst_N)         Dqs_Read_Val  <=  {DGN{1'h0}}   ;
    else if (Dqs_Read_En)   Dqs_Read_Val  <=  {DGN{1'h0}}   ;
    else                    Dqs_Read_Val  <=  Dqs_Read_Val  | Read_Valid  ;
  end

  assign  Dqs_Read_En  = &  Dqs_Read_Val  ; 

  /////////////////////////////////////////////////////////
  //产生 Data_Ready 信号； 当读计数器不为0时 Data_Ready 有效
  reg   [2:0]   Read_Num_Cnt = 3'h0  ; //读数据计数器

  always  @(posedge Sys_Clk or negedge Sys_Rst_N)      
  begin
    if (~Sys_Rst_N)           Read_Num_Cnt <=  3'h0 ; 
    else if (Read_Start ^ Dqs_Read_En)
    begin
      if (Read_Start)         Read_Num_Cnt <=  Read_Num_Cnt + 3'h1 ; 
      else if (Dqs_Read_En)   Read_Num_Cnt <=  Read_Num_Cnt - 3'h1 ;  
    end
  end
  always  @(posedge Sys_Clk or negedge Sys_Rst_N)   
  begin
    if (~Sys_Rst_N)           Read_Ready    <=  1'h0 ; 
    else if (Read_Start ^ Dqs_Read_En)
    begin
      if (Read_Start)         Read_Ready    <=  1'h1 ; 
      else if (Dqs_Read_En)   Read_Ready    <=  |Read_Num_Cnt[2:1] ;
    end
  end

  /////////////////////////////////////////////////////////
  //合并 Error 指示
  wire  [DGN-1:0] Rd_Error_Flag [2:0]   ; 
  wire  [DGN-1:0] Dqs_State_Flag[2:0]   ; //0:Direction ; 1:Error 
  reg   [2:0]     Rd_Error_Reg  = 3'h0  ;
  reg   [2:0]     Dqs_State_Reg = 3'h0  ;
  
  genvar m  ;
  generate
    for (m=0; m<DRAM_GROUP_NUM; m=m+1 )
    begin : Group_Error
    /////////////////////////
      assign  Rd_Error_Flag [2][m]  = Read_Error[m][2]  ;  
      assign  Rd_Error_Flag [1][m]  = Read_Error[m][1]  ;  
      assign  Rd_Error_Flag [0][m]  = Read_Error[m][0]  ;  

      assign  Dqs_State_Flag[2][m]  = Dqs_State [m][2]  ;  
      assign  Dqs_State_Flag[1][m]  = Dqs_State [m][1]  ;  
      assign  Dqs_State_Flag[0][m]  = Dqs_State [m][0]  ;  
    /////////////////////////
    end
  endgenerate
  
  always  @(posedge Sys_Clk) 
  begin
    Rd_Error_Reg[2]   <=  | Rd_Error_Flag  [2][DGN-1:0] ;
    Rd_Error_Reg[1]   <=  | Rd_Error_Flag  [1][DGN-1:0] ;
    Rd_Error_Reg[0]   <=  | Rd_Error_Flag  [0][DGN-1:0] ;
    
    Dqs_State_Reg[2]  <=  | Dqs_State_Flag [2][DGN-1:0] ;
    Dqs_State_Reg[1]  <=  | Dqs_State_Flag [1][DGN-1:0] ;
    Dqs_State_Reg[0]  <=  | Dqs_State_Flag [0][DGN-1:0] ;
  end

  /////////////////////////////////////////////////////////
  wire  [2:0]     O_Read_Error  = Rd_Error_Reg  ; //(O)Read Error  
  wire  [2:0]     O_Dqs_State   = Dqs_State_Reg ; //(O)DQS State 0:Dir ; 1:Error ;2:Change 
  wire  [2:0]     O_Read_Num    = Read_Num_Cnt  ; //(O)Read Data Number

  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

//222222222222222222222222222222222222222222222222222222222
//对齐DQS的数据
//********************************************************/
  /////////////////////////////////////////////////////////
  reg           Grp_Sync_Clr  = 1'h0  ;

  always  @(posedge Sys_Clk)  Grp_Sync_Clr  <=  ( Read_Start & (~Read_Ready)  ) ;

  /////////////////////////////////////////////////////////
  wire    [DGN-1:0]   Grp_Fifo_Wr_En              ; //(I) Write Enable
  wire    [DGN-1:0]   Grp_Fifo_Rd_Empty           ; //(O) FIFO Write Empty
  wire    [GCW-1:0]   Grp_Fifo_Wr_Data [DGN-1:0]  ; //(I) Write Data
  wire    [GCW-1:0]   Grp_Fifo_Rd_Data [DGN-1:0]  ; //(O) Read Data
  wire    [    3:0]   Grp_Fifo_Rd_Num  [DGN-1:0]  ; //(O) Read 

  wire                Grp_Fifo_Rd_En  ;
  wire    [DCW-1:0]   Ddr_Data_In     ;

  genvar k  ;
  generate
    for (k=0; k<DRAM_GROUP_NUM; k=k+1 )
    begin : Group_Data_Fifo
    /////////////////////////
      defparam    U1_Group_Data_Fifo.OUT_REG       = "No"                 ; //"Yes" Output Register Eanble ; "No"  Output Register Disble
      defparam    U1_Group_Data_Fifo.DATA_WIDTH    = GROUP_WIDTH_PER_CLK  ; //Data Width
      defparam    U1_Group_Data_Fifo.DATA_DEPTH    = 8                    ; //Address Width

      assign  Grp_Fifo_Wr_En  [k] = Group_DVal  [k] ;
      assign  Grp_Fifo_Wr_Data[k] = Group_Data  [k] ;

      Ddr_Ctrl_Sc_Fifo  U1_Group_Data_Fifo
      (
        .Sys_Clk      ( Sys_Clk               ) , //System Clock
        .Sync_Clr     ( Grp_Sync_Clr          ) , //Sync Reset
        .I_Wr_En      ( Grp_Fifo_Wr_En   [k]  ) , //(I) FIFO Write Enable
        .I_Wr_Data    ( Grp_Fifo_Wr_Data [k]  ) , //(I) FIFO Write Data
        .I_Rd_En      ( Grp_Fifo_Rd_En        ) , //(I) FIFO Read Enable
        .O_Rd_Data    ( Grp_Fifo_Rd_Data [k]  ) , //(I) FIFO Read Data
        .O_Data_Num   ( Grp_Fifo_Rd_Num  [k]  ) , //(I) FIFO Data Number
        .O_Wr_Full    (                       ) , //(O) FIFO Write Full
        .O_Rd_Empty   ( Grp_Fifo_Rd_Empty[k]  ) , //(O) FIFO Write Empty
        .O_Fifo_Err   (                       )   //(O) Fifo Error
      ) ;

      assign  Ddr_Data_In [(k+1)*DGW+DDW-1 : k*DGW+DDW] = Grp_Fifo_Rd_Data[k][GCW-1:DGW] ;
      assign  Ddr_Data_In [(k+1)*DGW    -1 : k*DGW    ] = Grp_Fifo_Rd_Data[k][DGW-1:  0] ;
    /////////////////////////

    end    
  endgenerate 

  /////////////////////////////////////////////////////////
  reg   [2:0]   WrEn_Dly_Cnt    = 3'h0  ; //计算最大写允许的相位差

  wire          Grp_WrEn_Any  = ( |Grp_Fifo_Wr_En ) ;
  wire          Grp_WrEn_All  = ( &Grp_Fifo_Wr_En ) ;

  always  @(posedge Sys_Clk)  
  begin
    if (Grp_WrEn_Any & (~Grp_WrEn_All))   WrEn_Dly_Cnt  <=  WrEn_Dly_Cnt + 3'h1  ;
    else if (Grp_Sync_Clr  )              WrEn_Dly_Cnt  <=  3'h0  ;
  end
  
  /////////////////////////////////////////////////////////  
  defparam  Grp_Fifo_WrEn_Dly.DATA_WIDTH        = 1     ;
  defparam  Grp_Fifo_WrEn_Dly.DELAY_LEN_MAX     = 8     ;

  Delay_Use_SRL8  Grp_Fifo_WrEn_Dly 
  (
    .Sys_Clk      ( Sys_Clk           ) , //System Clock
    .Sys_Rst_N    ( ~Grp_Sync_Clr     ) , //System Reset
    .I_Data_En    ( 1'h1              ) , //(I)Data Enable
    .I_Data_In    ( Grp_WrEn_All      ) , //(I)Data Input
    .I_Dly_Len    ( WrEn_Dly_Cnt      ) , //(I)Delay Length
    .O_Shift_Out  (                   ) , //(O)Shift Output
    .O_Data_Out   ( Grp_Fifo_Rd_En    )   //(O)Data Output
  );

  wire    Ddr_Data_Val  = Grp_Fifo_Rd_En  ; //DDR

  /////////////////////////////////////////////////////////
  wire              O_Ddr_DVal  = Ddr_Data_Val  ; //(O)DDR Data Valid 
  wire  [DCW-1:0]   O_Ddr_Data  = Ddr_Data_In   ; //(O)DDR Data 

//222222222222222222222222222222222222222222222222222222222

//333333333333333333333333333333333333333333333333333333333
//产生数据有效 （ Burst_Valid ） ，每个DDR Burst 产生一个 Burst_Valid
//输出读数据 （ Read_Data ），每个DDR Burst 输出一组数据
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]   Burst_Len_Cnt = 2'h0  ; //Burst计数，每次读间隔4个
  
  always  @(posedge Sys_Clk or negedge Sys_Rst_N)  
  begin
    if (~Sys_Rst_N)           Burst_Len_Cnt <=  2'h3  ;
    else if (Ddr_Data_Val)    Burst_Len_Cnt <=  Burst_Len_Cnt - 2'h1  ;
    else                      Burst_Len_Cnt <=  2'h3  ;
  end

  /////////////////////////////////////////////////////////
  reg   [DBW-1:0]   Read_Data   = {DBW{1'h0}} ;
  reg               Read_DVal   = 1'h0        ;   
  reg               Ddr_Bst_End = 1'h0        ;

  always  @(posedge Sys_Clk)  Read_Data   <=  { Ddr_Data_In , Read_Data[DBW-1:DCW]  } ;
  always  @(posedge Sys_Clk)  Read_DVal   <=  Ddr_Data_Val  & (~| Burst_Len_Cnt     ) ;
  always  @(posedge Sys_Clk)  Ddr_Bst_End <=  Ddr_Data_Val  & (Burst_Len_Cnt == 2'h1) ;

  /////////////////////////////////////////////////////////
  wire              O_Ddr_Bst_End = Ddr_Bst_End ; //(O)DDR Burst End
  wire  [DBW-1:0]   O_Read_Data   = Read_Data   ; //(O)Read Data
  wire              O_Read_DVal   = Read_DVal   ; //(O)Read Data Valid 

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333

endmodule

/////////////////       Ddr_Rd_Data       ////////////////







///////////////////////////////////////////////////////////
/**********************************************************
  Function Description:

  实现单组DDR数据的读取；根据DQS确定有效数据的位置
  通过输入的 Read_Start 和 Read_Ready 信号来确定数据的采样窗口
  通过 DQS状态( Dqs_State )给DDR的读校准提供DQS的相位信息 

    Read_Vaild  读有效信号，表示进行了一次读；
    Read_End    读结束信号，表示完成了一次Burst读；
    Read_Error  读错误指示, 可用于错误侦测和故障诊断   
      2:  Err_TimeOut     当在指定窗口没有搜索到DQS的头
      1:  Err_Sdq_Code    在读数据过程中出现与数据选择不匹配的DQS
      0:  Err_Overflow    数据结束后DQS仍然有效 
    Dqs_State   DQS状态 ，用于读校准  0:Dir ; 1:Error ;2:Change 
      2:  高电平表示DQS发生一次相位变化，从01到10或从10到01
      1:  DQS错误，高电平表示DQS在一次采集过程中出现不同DQS相位；
      0： DQS方向，这个为DDIO采集的DQS的第一个Bit
    Read_DVal   读数据有效
    Read_Data   读数据   

  Establishment : Richard Zhu
  Create date   : 2022-11-06
  Versions      : V0.1
  Revision of records:
  Ver0.1
  
  --  2022-11-06  (Ddr_Rd_Group_Data)
        创建文件并经过上板测试
  --  2022-11-08  (Ddr_Rd_Group_Data)
    1、 修改了在DQS反向时数据出错的BUG;
    2、 代码整理
  --  2022-11-12 （Ddr_Rd_Group_Data）
    1、 读数据方案修改； 避免DQS的错误对读状态的影响，确保数据读取成功率
    2、 根据 Read_Ready 信号确定数据是否读取完成，避免DQS的错误导致数据不够超出实际读取数量
    3、 产生三个错误指示 ； 可用于错误侦测和故障诊断      
        Err_TimeOut   当在指定窗口没有搜索到DQS的头
        Err_Sdq_Code  在读数据过程中出现与数据选择不匹配的DQS
        Err_Overflow  数据结束后DQS仍然有效 
    4、 取消了 Burst 计数器对 DDR 的 BL 的关系；无论 BL8还是BL4，读数据间隔都是4个时钟周期
    5、 修改 Read_Valid 的功能，Read_Valid 用于指示读取了一组数据
    6、 增加 Read_End ; 表示完成了一次Burst读；
  --  2023-03-20 ( Ddr_Rd_Group_Data )
    1、 修改了 Err_Dqs_Code 判决出错的BUG;
    2、 修改了 Dqs_Start 会在 Dqs_End 出现的BUG ;
    3、 添加了 Dqs_State 用于指示Dqs的方向和变化，用于错误边界的测量 

**********************************************************/

module  Ddr_Rd_Group_Data
(
  Sys_Clk         , //System Clock
  I_Ddr_Dqs       , //(I)DRAM DQS (0:High 1:Low)
  I_Ddr_Dq_Hi     , //(I)DRAM DQ Input (High)
  I_Ddr_Dq_Lo     , //(I)DRAM DQ Input (Low )
  I_Read_Start    , //(I)Read_Start
  I_Read_Ready    , //(I)Read Ready
  O_Read_Valid    , //(O)Read Valid 
  O_Read_End      , //(O)Read End   
  O_Read_Error    , //(O)Read Error
  O_Dqs_State     , //(O)DQS State 0:Dir ; 1:Error ;2:Change 
  O_Group_DVal    , //(O)DRAM Group Data Valid
  O_Group_Data      //(O)DRAM Group Data 
) ;

  //Define  Parameter
  /////////////////////////////////////////////////////////  
  parameter   DRAM_GROUP_WIDTH    = `GROUP_WIDTH  ;

  localparam  GROUP_WIDTH_PER_CLK = DRAM_GROUP_WIDTH * 2  ; 

  /////////////////
  localparam  DGW = DRAM_GROUP_WIDTH    ;
  localparam  GCW = GROUP_WIDTH_PER_CLK ;
  /////////////////////////////////////////////////////////

  // Signal Define
  /////////////////////////////////////////////////////////  
  input               Sys_Clk         ; //System Clock
  input   [    1:0]   I_Ddr_Dqs       ; //(I)DRAM DQS (0:High 1:Low)
  input   [DGW-1:0]   I_Ddr_Dq_Hi     ; //(I)DRAM DQ Input (High)
  input   [DGW-1:0]   I_Ddr_Dq_Lo     ; //(I)DRAM DQ Input (Low )
  input               I_Read_Start    ; //(I)Read_Start
  input               I_Read_Ready    ; //(I)Read Ready
  output              O_Read_Valid    ; //(O)Read Valid  
  output              O_Read_End      ; //(O)Read End  
  output  [    2:0]   O_Read_Error    ; //(O)Read Error
  output  [    2:0]   O_Dqs_State     ; //(O)DQS State 0:Dir ; 1:Error ;2:Change 
  output              O_Group_DVal    ; //(O)DRAM Group Data Valid
  output  [GCW-1:0]   O_Group_Data    ; //(O)DRAM Group Data 

  /////////////////////////////////////////////////////////

//000000000000000000000000000000000000000000000000000000000
//
//********************************************************/
  /////////////////////////////////////////////////////////
  //输入信号连接到外部接口，先打一拍
  reg   [    1:0]   Ddr_Dqs     =      2'h0   ; //DRAM DQS (0:High 1:Low)
  reg   [DGW-1:0]   Ddr_Dq_Hi   = {DGW{1'h0}} ; //DRAM DQ Input (High)
  reg   [DGW-1:0]   Ddr_Dq_Lo   = {DGW{1'h0}} ; //DRAM DQ Input (Low )

  always  @(posedge Sys_Clk)    Ddr_Dqs     <=  I_Ddr_Dqs     ;   
  always  @(posedge Sys_Clk)    Ddr_Dq_Hi   <=  I_Ddr_Dq_Hi   ;   
  always  @(posedge Sys_Clk)    Ddr_Dq_Lo   <=  I_Ddr_Dq_Lo   ;   

  /////////////////////////////////////////////////////////
  wire              Read_Start  = I_Read_Start  ; //Read_Start
  wire              Read_Ready  = I_Read_Ready  ; //Read Read 

  /////////////////////////////////////////////////////////
//000000000000000000000000000000000000000000000000000000000

//111111111111111111111111111111111111111111111111111111111
//处理组数据有效信号 （ Group_DVal  ）和读有效信号（ Read_Valid  ）
//********************************************************/
  /////////////////////////////////////////////////////////
  wire    Dqs_0     = (Ddr_Dqs  ==  2'h0) ;
  wire    Dqs_1     = (Ddr_Dqs  ==  2'h1) ;
  wire    Dqs_2     = (Ddr_Dqs  ==  2'h2) ;
  wire    Dqs_3     = (Ddr_Dqs  ==  2'h3) ;

  wire    Dqs_No_0  = (Ddr_Dqs  !=  2'h0) ;
  wire    Dqs_No_3  = (Ddr_Dqs  !=  2'h3) ;

  wire    Dqs_0_3   = (Ddr_Dqs  ==  2'h3) | (Ddr_Dqs  ==  2'h0) ;
  wire    Dqs_1_2   = (Ddr_Dqs  ==  2'h2) | (Ddr_Dqs  ==  2'h1) ;

  /////////////////////////////////////////////////////////
  wire    Head_Search   ;
  reg     Dqs_2_Reg     = 1'h0  ;
  
  always  @(posedge Sys_Clk)    Dqs_2_Reg  <=  (~Ddr_Dqs[0])  & I_Ddr_Dqs[0]  ;

  wire    Dqs_Start   = (((~Ddr_Dqs[1])  & I_Ddr_Dqs[1])  | Dqs_2_Reg ) & (~&I_Ddr_Dqs);

  /////////////////////////////////////////////////////////
  wire        Read_Idle   ;         //读空闲
  reg   [4:0] Read_Op_Cnt = 5'h1f ; //读操作计数器
                                    //Bit4：指示空闲
                                    //Bit3：指示搜索DQS起始位置

  wire    Rd_Start_En   = Read_Start & Read_Op_Cnt[4] ;

  always  @(posedge Sys_Clk)
  begin
    if (Rd_Start_En)                  Read_Op_Cnt   <=  Dqs_Start ? 5'h3  : 5'hf  ;
    else if ( Read_Op_Cnt[4])         Read_Op_Cnt   <=  5'h1f ;
    else if ( Read_Op_Cnt[3])         Read_Op_Cnt   <=  Dqs_Start ? 5'h3  : (Read_Op_Cnt  - 5'h1 ) ;
    else if (|Read_Op_Cnt[1:0])       Read_Op_Cnt   <=  {3'h0 , Read_Op_Cnt[1:0]} - 5'h1 ;
    else if (Read_Ready)              Read_Op_Cnt   <=   5'h3 ;
    else                              Read_Op_Cnt   <=  Read_Op_Cnt - 5'h1  ;   
  end

  assign  Read_Idle     =   Read_Op_Cnt[4]  ;
  assign  Head_Search   =   Read_Op_Cnt[3]  ;
  
  /////////////////////////////////////////////////////////
  reg     Data_En_Sel   = 1'h0  ; //数据采集选择；0：数据对齐；1：高位数据提前
  
  always  @(posedge Sys_Clk)  if (Head_Search)  Data_En_Sel <=  Dqs_1 ;
  
  /////////////////////////////////////////////////////////
  wire    Read_Last     ;         //一组数据的最后一个数据
  reg     Read_Valid    = 1'h0  ; //读允许，在读有效（ Read_Ready ）时 DQS 不为全1 
  reg     Read_End      = 1'h0  ; //读结束，标志本次操作结束

  assign  Read_Last     = (Read_Op_Cnt[4:3]  ==  2'h0) 
                        & (Read_Op_Cnt[1:0]  ==  2'h0)  ;

  always  @(posedge Sys_Clk)  Read_Valid  <=  ( Read_Op_Cnt[4:3]  ==  2'h0 )  
                                            & ( Read_Op_Cnt[1:0]  ==  2'h3 )  ;
  always  @(posedge Sys_Clk)  Read_End    <=  ~ Read_Ready  & Read_Last ;

  /////////////////////////////////////////////////////////
  wire   O_Read_Valid   = Read_Valid  ; //(O)Read Valid 
  wire   O_Read_End     = Read_End    ; //(O)Read End  
  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

//222222222222222222222222222222222222222222222222222222222
//根据不同的相位来合并输出数据 
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [DGW-1:0]   Dq_Hi_Reg   = 2'h0        ; //DQ高位寄存器
  reg               Group_DVal  = 1'h0        ; //组数据有效
  reg   [GCW-1:0]   Group_Data  = {GCW{1'h0}} ; //组数据

  always  @(posedge Sys_Clk)    Dq_Hi_Reg   <=    Ddr_Dq_Hi       ;
  always  @(posedge Sys_Clk)    Group_DVal  <=  ~ Read_Op_Cnt[3]  ;
  always  @(posedge Sys_Clk) 
  begin
    if (Data_En_Sel )
    begin
      Group_Data[GCW-1:DGW] <=  Ddr_Dq_Lo ; 
      Group_Data[DGW-1:  0] <=  Dq_Hi_Reg ; 
    end
    else 
    begin
      Group_Data[GCW-1:DGW] <=  Ddr_Dq_Hi  ; 
      Group_Data[DGW-1:  0] <=  Ddr_Dq_Lo  ; 
    end
  end 

  /////////////////////////////////////////////////////////
  wire              O_Group_DVal  = Group_DVal  ; //(O)DRAM Group Data Valid
  wire  [GCW-1:0]   O_Group_Data  = Group_Data    ; //(O)DRAM Group Data 

  /////////////////////////////////////////////////////////
//222222222222222222222222222222222222222222222222222222222

//333333333333333333333333333333333333333333333333333333333
//根据不同状态输出错误信息；可用于错误侦测和故障诊断
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   Dqs_Start_Flag  = 1'h0  ;
  reg   Err_TimeOut     = 1'h0  ; //当在指定窗口没有搜索到DQS的头

  always  @(posedge Sys_Clk)  
  begin
    if (Read_End)         Dqs_Start_Flag  <=  1'h0  ;
    else if (Dqs_Start)   Dqs_Start_Flag  <=  1'h1  ;
  end
  always  @(posedge Sys_Clk)  
  begin
    if (Read_Start)                     Err_TimeOut   <=  1'h0            ;
    else if (Read_Op_Cnt[3:0] ==  4'h8) Err_TimeOut   <=  ~Dqs_Start_Flag ; 
  end

  /////////////////////////////////////////////////////////
  reg   Err_Sdq_Code  = 1'h0  ; //在读数据过程中出现与数据选择不匹配的DQS

  always  @(posedge Sys_Clk)  
  begin
    if (Dqs_Start)            Err_Sdq_Code  <=  1'h0  ;  
    else if (~Head_Search)    Err_Sdq_Code  <=  Err_Sdq_Code  
                                          | ( Dqs_1 != Data_En_Sel  ) ;              
  end

  /////////////////////////////////////////////////////////
  reg   Err_Overflow  = 1'h0  ; //数据结束后DQS仍然有效

  always  @(posedge Sys_Clk)  
  begin
    if (Read_Start)     Err_Overflow  <=  1'h0      ;
    else if (Read_End)  Err_Overflow  <=  Dqs_No_3  ;  
  end

  /////////////////////////////////////////////////////////
  wire  [2:0]   Read_Error    ; //读错误指示, 可用于错误侦测和故障诊断   
                                //2:  Err_TimeOut     当在指定窗口没有搜索到DQS的头
                                //1:  Err_Sdq_Code    在读数据过程中出现与数据选择不匹配的DQS
                                //0:  Err_Overflow    数据结束后DQS仍然有效 

  assign        Read_Error[2] = Err_TimeOut   ; 
  assign        Read_Error[1] = Err_Sdq_Code  ;
  assign        Read_Error[0] = Err_Overflow  ;

  /////////////////////////////////////////////////////////
  reg       Dqs_Change  = 1'h0 ;  //DQS变化指示；高电平表示DQS发生一次相位变化，从01到10或从10到01
  reg       Dqs_Error   = 1'h0 ;  //DQS错误，高电平表示DQS在一次采集过程中出现不同DQS相位；
  reg       Dqs_Select  = 1'h0 ;  //DQS方向，这个为DDIO采集的DQS的第一个Bit
  
  always  @(posedge Sys_Clk)  if (Read_End)   Dqs_Select  <=  Data_En_Sel ;
  always  @(posedge Sys_Clk)  if (Read_End)   Dqs_Error   <=  Err_Sdq_Code;
  always  @(posedge Sys_Clk)  if (Read_End)   Dqs_Change  <=  Data_En_Sel ^ Dqs_Select  ;

  /////////////////////////////////////////////////////////
  wire    [2:0] Dqs_State  ;  //DQS状态，用于读校准  0:Dir ; 1:Error ;2:Change 
                              //2: Dqs_Change 高电平表示DQS发生一次相位变化，从01到10或从10到01
                              //1: Dqs_Error  DQS错误，高电平表示DQS在一次采集过程中出现不同DQS相位；
                              //0: Dqs_Select DQS方向，这个为DDIO采集的DQS的第一个Bit

  assign  Dqs_State[2]    = Dqs_Change    ;
  assign  Dqs_State[1]    = Dqs_Error     ;
  assign  Dqs_State[0]    = Dqs_Select    ;

  /////////////////////////////////////////////////////////
  wire  [2:0]   O_Dqs_State   = Dqs_State  ; //(O)DQS State 0:Dir ; 1:Error ;2:Change 
  wire  [2:0]   O_Read_Error  = Read_Error ; //(O)Read Error

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333

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

/*
  parameter   AXI_ID_WIDTH        = 8   ;   //AXI4总线ID的宽度
  parameter   AXI_DATA_WIDTH      = 128 ;   //AXI4总线数据的宽度
  parameter   DDR_DATA_WIDTH      = 16  ;   //DDR总线数据的宽度

  parameter   WR_DATA_FIFO_DEPTH       = 512 ;   //写数据FIFO深度
  parameter   WR_BURST_QUEUE_NUM      = 16  ;   //写最大地址队列深度

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