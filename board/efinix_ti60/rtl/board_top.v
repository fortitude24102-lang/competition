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
wire gpu_stream_clk, gpu_stream_reset;
wire [15:0] gpu_display_pixel;
wire gpu_display_valid, gpu_display_line_last, gpu_display_frame_last;
wire gpu_display_ready, gpu_vblank;
wire [11:0] gpu_scanout_level;
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
 .system_spi_0_io_data_1_OE(system_spi_0_io_data_1_OE),
 .gpu_stream_clk(gpu_stream_clk),
 .gpu_stream_reset(gpu_stream_reset),
 .gpu_display_pixel(gpu_display_pixel),
 .gpu_display_valid(gpu_display_valid),
 .gpu_display_line_last(gpu_display_line_last),
 .gpu_display_frame_last(gpu_display_frame_last),
 .gpu_display_ready(gpu_display_ready),
 .gpu_scanout_level(gpu_scanout_level),
 .gpu_vblank(gpu_vblank)
);
wire rst_n;
wire display_vblank, fifo_full, fifo_empty, display_protocol_error;
wire display_underflow_event;
wire [15:0] display_underflow_count;
wire [15:0] display_rgb565;
wire display_hs, display_vs, display_de;
assign HPD_N = 1'b0;
reset #(.IN_RST_ACTIVE("LOW"),.OUT_RST_ACTIVE("LOW"),.CYCLE(3)) video_reset
 (.i_arst(hdmi_tx_locked),.i_clk(hdmi_tx_slow_clk),.o_srst(rst_n));
hdmi_subsystem display (
 .gpu_clk(gpu_stream_clk),.gpu_reset(gpu_stream_reset),
 .pixel_clk(hdmi_tx_slow_clk),.pixel_reset(~rst_n),
 .gpu_pixel(gpu_display_pixel),.gpu_valid(gpu_display_valid),
 .gpu_line_last(gpu_display_line_last),.gpu_frame_last(gpu_display_frame_last),
 .gpu_ready(gpu_display_ready),.fifo_level(gpu_scanout_level),
 .vblank_gpu(gpu_vblank),.vblank(display_vblank),
 .fifo_full(fifo_full),.fifo_empty(fifo_empty),.protocol_error(display_protocol_error),
 .underflow_event(display_underflow_event),.underflow_count(display_underflow_count),
 .video_rgb565(display_rgb565),.video_hs(display_hs),.video_vs(display_vs),.video_de(display_de),
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
