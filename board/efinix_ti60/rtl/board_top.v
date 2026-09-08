`include "ddr3_controller/ddr3_parameter.vh"
module board_top #
(
parameter                       RANK_RATIO         = 1,       // # of unique CS outputs per rank
parameter                       CK_RATIO           = `CK_RATIO, 
parameter                       ASYN_AXI_CLK       = `ASYN_AXI_CLK, 
parameter                       RANKS              = `RANKS,
parameter                       CK_WIDTH           = `CK_WIDTH,       // # of CK/CK# outputs to memory   
parameter                       CKE_WIDTH          = `CKE_WIDTH,       // # of cke outputs
parameter                       CS_WIDTH           = `CS_WIDTH,       // # of unique CS outputs
parameter                       BANK_WIDTH         = `BANK_WIDTH,       // # of bank bits
parameter                       ROW_WIDTH          = `ROW_WIDTH,       // DRAM address bus width
parameter                       COL_WIDTH          = `COL_WIDTH,      // column address width
parameter                       DM_WIDTH           = `DM_WIDTH,       // # of DM (data mask)
parameter                       DQS_WIDTH          = `DQS_WIDTH,       // # of DQS (strobe)
parameter                       DQ_WIDTH           = `DQ_WIDTH,      // # of DQ (data)
parameter                       ODT_WIDTH          = `ODT_WIDTH,
parameter                       DQ_CNT_WIDTH       = `DQ_CNT_WIDTH,       // = ceil(log2(DQ_WIDTH))
parameter                       DQS_CNT_WIDTH      = `DQS_CNT_WIDTH,       // = ceil(log2(DQS_WIDTH))  
parameter                       DRAM_WIDTH         = `DRAM_WIDTH,       // # of DQ per DQS   
parameter                       DATA_WIDTH         = `DATA_WIDTH,
parameter                       ADDR_WIDTH         = `ADDR_WIDTH,    
parameter                       AXI_ID_WIDTH       = `AXI_ID_WIDTH,
parameter                       AXI_ADDR_WIDTH     = `AXI_ADDR_WIDTH,
parameter                       AXI_DATA_WIDTH     = `AXI_DATA_WIDTH
)
(

   // Clock and reset ports
   input                              axi_clk,      
   input                              core_clk,     // CORE CLK @ 100MHz
   input                              sdram_clk,    // SDRAM CK @ 400MHz
   input                              rx_cal_clk,   // SDRAM CK @ 400MHz
   input                              tx_cal_clk,   // SDRAM CK @ 400MHz
   input                              tx_cal_clk_90edge,   // SDRAM CK @ 400MHz
   input                              pll_locked,
   input                              user_pll_locked,
  //  input                              peripheralClk,
   //&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
   output  wire                       system_uart_0_io_txd,
   input                              system_uart_0_io_rxd,   
   input  [3:0]                       soc_gpio_IN,
   output [3:0]                       soc_gpio_OUT,
   output [3:0]                       soc_gpio_OE,
    // debug core ports

  input                               jtag_inst1_CAPTURE ,
  input                               jtag_inst1_DRCK    ,
  input                               jtag_inst1_RESET   ,
  input                               jtag_inst1_RUNTEST ,
  input                               jtag_inst1_SEL     ,
  input                               jtag_inst1_SHIFT   ,
  input                               jtag_inst1_TCK     ,
  input                               jtag_inst1_TDI     ,
  input                               jtag_inst1_TMS     ,
  input                               jtag_inst1_UPDATE  ,
  output                              jtag_inst1_TDO     ,

   // PLL status flags  
   output [2:0]                       pll_shift,  
   output [4:0]                       pll_shift_sel,
   output                             pll_shift_ena,  
   // memory interface ports
   output                             ddr_ck_hi,
   output                             ddr_ck_lo,
   output                             ddr_reset_n,
   output [CKE_WIDTH-1:0]             ddr_cke,     
   output [ROW_WIDTH-1:0]             ddr_addr,
   output [BANK_WIDTH-1:0]            ddr_ba,
   output                             ddr_cas_n,

   output [CS_WIDTH*RANK_RATIO-1:0]   ddr_cs_n,
   output                             ddr_ras_n,
   output                             ddr_we_n,
   
   input  [DQS_WIDTH-1:0]             ddr_dqs_in_hi,
   input  [DQS_WIDTH-1:0]             ddr_dqs_in_lo,
   input  [DQ_WIDTH-1:0]              ddr_dq_in_hi,
   input  [DQ_WIDTH-1:0]              ddr_dq_in_lo,
   
   output [DQS_WIDTH-1:0]             ddr_dqs_oe,
   output [DQS_WIDTH-1:0]             ddr_dqs_oe_n,
   output [DQ_WIDTH-1:0]              ddr_dq_oe,  
   output [DQS_WIDTH-1:0]             ddr_dqs_out_hi,
   output [DQS_WIDTH-1:0]             ddr_dqs_out_lo,
   output [DQ_WIDTH-1:0]              ddr_dq_out_hi,
   output [DQ_WIDTH-1:0]              ddr_dq_out_lo,
   output [DM_WIDTH-1:0]              ddr_dm_hi,
   output [DM_WIDTH-1:0]              ddr_dm_lo,
   output [ODT_WIDTH-1:0]             ddr_odt,

   input                              system_spi_0_io_data_0_IN,
   input                              system_spi_0_io_data_1_IN,
   output                             system_spi_0_io_ss,
   output                             system_spi_0_io_sclk_write,
   output                             system_spi_0_io_data_0_OUT,
   output                             system_spi_0_io_data_0_OE,
   output                             system_spi_0_io_data_1_OUT,
   output                             system_spi_0_io_data_1_OE

,
 input hdmi_tx_locked, hdmi_tx_slow_clk,
 output [9:0] tmds_data0_o,tmds_data1_o,tmds_data2_o,tmds_clk_o,
 output tmds_data0_TX_OE,tmds_data1_TX_OE,tmds_data2_TX_OE,tmds_clk_TX_OE,
 output tmds_data0_TX_RST,tmds_data1_TX_RST,tmds_data2_TX_RST,tmds_clk_TX_RST,
 output HPD_N
);
efinix_sapphire_adapter sapphire (
 .axi_clk(axi_clk),
 .core_clk(core_clk),
 .sdram_clk(sdram_clk),
 .rx_cal_clk(rx_cal_clk),
 .tx_cal_clk(tx_cal_clk),
 .tx_cal_clk_90edge(tx_cal_clk_90edge),
 .pll_locked(pll_locked),
 .user_pll_locked(user_pll_locked),
 .system_uart_0_io_txd(system_uart_0_io_txd),
 .system_uart_0_io_rxd(system_uart_0_io_rxd),
 .soc_gpio_IN(soc_gpio_IN),
 .soc_gpio_OUT(soc_gpio_OUT),
 .soc_gpio_OE(soc_gpio_OE),
 .jtag_inst1_CAPTURE(jtag_inst1_CAPTURE),
 .jtag_inst1_DRCK(jtag_inst1_DRCK),
 .jtag_inst1_RESET(jtag_inst1_RESET),
 .jtag_inst1_RUNTEST(jtag_inst1_RUNTEST),
 .jtag_inst1_SEL(jtag_inst1_SEL),
 .jtag_inst1_SHIFT(jtag_inst1_SHIFT),
 .jtag_inst1_TCK(jtag_inst1_TCK),
 .jtag_inst1_TDI(jtag_inst1_TDI),
 .jtag_inst1_TMS(jtag_inst1_TMS),
 .jtag_inst1_UPDATE(jtag_inst1_UPDATE),
 .jtag_inst1_TDO(jtag_inst1_TDO),
 .pll_shift(pll_shift),
 .pll_shift_sel(pll_shift_sel),
 .pll_shift_ena(pll_shift_ena),
 .ddr_ck_hi(ddr_ck_hi),
 .ddr_ck_lo(ddr_ck_lo),
 .ddr_reset_n(ddr_reset_n),
 .ddr_cke(ddr_cke),
 .ddr_addr(ddr_addr),
 .ddr_ba(ddr_ba),
 .ddr_cas_n(ddr_cas_n),
 .ddr_cs_n(ddr_cs_n),
 .ddr_ras_n(ddr_ras_n),
 .ddr_we_n(ddr_we_n),
 .ddr_dqs_in_hi(ddr_dqs_in_hi),
 .ddr_dqs_in_lo(ddr_dqs_in_lo),
 .ddr_dq_in_hi(ddr_dq_in_hi),
 .ddr_dq_in_lo(ddr_dq_in_lo),
 .ddr_dqs_oe(ddr_dqs_oe),
 .ddr_dqs_oe_n(ddr_dqs_oe_n),
 .ddr_dq_oe(ddr_dq_oe),
 .ddr_dqs_out_hi(ddr_dqs_out_hi),
 .ddr_dqs_out_lo(ddr_dqs_out_lo),
 .ddr_dq_out_hi(ddr_dq_out_hi),
 .ddr_dq_out_lo(ddr_dq_out_lo),
 .ddr_dm_hi(ddr_dm_hi),
 .ddr_dm_lo(ddr_dm_lo),
 .ddr_odt(ddr_odt),
 .system_spi_0_io_data_0_IN(system_spi_0_io_data_0_IN),
 .system_spi_0_io_data_1_IN(system_spi_0_io_data_1_IN),
 .system_spi_0_io_ss(system_spi_0_io_ss),
 .system_spi_0_io_sclk_write(system_spi_0_io_sclk_write),
 .system_spi_0_io_data_0_OUT(system_spi_0_io_data_0_OUT),
 .system_spi_0_io_data_0_OE(system_spi_0_io_data_0_OE),
 .system_spi_0_io_data_1_OUT(system_spi_0_io_data_1_OUT),
 .system_spi_0_io_data_1_OE(system_spi_0_io_data_1_OE)
);
wire rst_n,hs,vs,de;
wire [23:0] rgb;
assign HPD_N = 1'b0;
reset #(.IN_RST_ACTIVE("LOW"),.OUT_RST_ACTIVE("LOW"),.CYCLE(3)) video_reset
 (.i_arst(hdmi_tx_locked),.i_clk(hdmi_tx_slow_clk),.o_srst(rst_n));
color_bar_rgb #(.HS_POLORY(1'b1),.VS_POLORY(1'b1),.SYMBOL_WIDTH(8),.SYMBOL_NUM(3),.PAR_PIXEL_NUM(1),
 .HFP(88),.HST(44),.HACT(1920),.HBP(148),.VFP(4),.VST(5),.VACT(1080),.VBP(36),.TEST_MODE(2'd2)) bars
 (.clk(hdmi_tx_slow_clk),.rst_n(rst_n),.hs(hs),.vs(vs),.de(de),.i_cfg_vid(24'b0),.o_vid_data(rgb));
hdmi_tx_adapter hdmi (.pixelclk(hdmi_tx_slow_clk),.rst(~rst_n),.red(rgb[23:16]),.green(rgb[15:8]),.blue(rgb[7:0]),.hs(hs),.vs(vs),.de(de),
 .tmds_data0_o(tmds_data0_o),
 .tmds_data1_o(tmds_data1_o),
 .tmds_data2_o(tmds_data2_o),
 .tmds_clk_o(tmds_clk_o),
 .tmds_data0_TX_OE(tmds_data0_TX_OE),
 .tmds_data1_TX_OE(tmds_data1_TX_OE),
 .tmds_data2_TX_OE(tmds_data2_TX_OE),
 .tmds_clk_TX_OE(tmds_clk_TX_OE),
 .tmds_data0_TX_RST(tmds_data0_TX_RST),
 .tmds_data1_TX_RST(tmds_data1_TX_RST),
 .tmds_data2_TX_RST(tmds_data2_TX_RST),
 .tmds_clk_TX_RST(tmds_clk_TX_RST));
endmodule
