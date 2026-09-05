//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : phy_ctl.v
// Version        : 1.2
// Date Created   : 2023-02-23 10:37:59
// Last Modified  : 2023-02-23 10:37:59
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ps / 1 ps

module phy_ctl # (

parameter                       DEBUG_WIDTH     = 25,
parameter                       TCQ             = 100,     
parameter                       AL              = "0",     
parameter                       BANK_WIDTH      = 3,       
parameter                       BURST_MODE      = "8",     
parameter                       CK_WIDTH        = 1,       
parameter                       CL              = 5,
parameter                       COL_WIDTH       = 12,      
parameter                       CS_WIDTH        = 1,       
parameter                       CKE_WIDTH       = 1,       
parameter                       CWL             = 5,
parameter                       DM_WIDTH        = 8,       
parameter                       DQ_WIDTH        = 64,      
parameter                       DQS_CNT_WIDTH   = 3,       
parameter                       DQS_WIDTH       = 8,       
parameter                       DRAM_WIDTH      = 8,       
parameter                       RX_CLK_SEL        = 5'b00100, //rx_cal_clk  PLL out sel
parameter                       TX_CLK_SEL        = 5'b01000, //tx_cal_clk  PLL out sel
parameter                       TX_CLK_90EDGE_SEL = 5'b00001, //tx_cal_clk_90edge  PLL out sel
parameter                       CK_RATIO        = 4,       
parameter                       RANK_RATIO      = 1,       
parameter                       RTT_NOM         = "60",    
parameter                       RTT_WR          = "120",   
parameter                       tCK             = 2500,    
parameter                       tRFC            = 110000,  
parameter                       tREFI           = 7800000, 
parameter                       RANKS           = 4,
parameter                       ODT_WIDTH       = 1,
parameter                       ROW_WIDTH       = 16      
)
(
input                           core_clk,            // CORE CLK @ 100MHz
input                           sdram_clk,           // SDRAM CK @ 400MHz
input                           rx_cal_clk,          // SDRAM CK @ 400MHz
input                           tx_cal_clk,          // SDRAM CK @ 400MHz
input                           tx_cal_clk_90edge,   // SDRAM CK @ 400MHz
input                           sdram_rst,
input                           rx_clk_rst,
input                           tx_data_rst,
input                           rst,
input                           tx_clk_rst,
// PLL status flags  
output  reg [2:0]               pll_shift,  
output  reg [4:0]               pll_shift_sel,
output                          pll_shift_ena,   
// debug port 
output      [2:0]               rdlvl_shift, 
output      [2:0]               wrlvl_shift, 
output      [DEBUG_WIDTH-1:0]   ddr_phy_debug, 
output                          phy_mc_ctl_full,
output                          phy_mc_cmd_full,
output                          phy_mc_data_full,
output                          init_calib_complete,
output                          phy_rddata_valid,
output      [2*CK_RATIO*DQ_WIDTH-1:0]           
                                phy_rd_data,
input       [CK_RATIO-1:0]      mc_ras_n,
input       [CK_RATIO-1:0]      mc_cas_n,
input       [CK_RATIO-1:0]      mc_we_n,
input       [CK_RATIO*ROW_WIDTH-1:0]             
                                mc_address,
input       [CK_RATIO*BANK_WIDTH-1:0]            
                                mc_bank,
input       [CS_WIDTH*RANK_RATIO*CK_RATIO-1:0] 
                                mc_cs_n,
input                           mc_reset_n,
input       [1:0]               mc_odt,
input       [CK_RATIO*CKE_WIDTH-1:0]      
                                mc_cke,

input       [3:0]               mc_aux_out0,
input       [3:0]               mc_aux_out1,
input                           mc_cmd_wren,
input                           mc_ctl_wren,
input       [2:0]               mc_cmd,
input       [1:0]               mc_cas_slot,
input       [5:0]               mc_data_offset,
input       [5:0]               mc_data_offset_1,
input       [5:0]               mc_data_offset_2,
input       [1:0]               mc_rank_cnt,
input                           mc_wrdata_en,
input       [2*CK_RATIO*DQ_WIDTH-1:0]     
                                mc_wrdata,
input       [2*CK_RATIO*(DQ_WIDTH/8)-1:0] 
                                mc_wrdata_mask,
// DDR bus signals
output                          ddr3_ck_hi,
output                          ddr3_ck_lo,
output      [CKE_WIDTH-1:0]     ddr3_cke,
output                          ddr3_reset_n,
output      [CS_WIDTH*RANK_RATIO-1:0]
                                ddr3_cs_n,
output                          ddr3_ras_n,
output                          ddr3_cas_n,
output                          ddr3_we_n,
output      [BANK_WIDTH-1:0]    ddr3_ba,
output      [ROW_WIDTH-1:0]     ddr3_addr,

output                          ddr3_dqs_oe,
output                          ddr3_dq_oe,
input       [DQS_WIDTH-1:0]     ddr3_dqs_in_hi,
input       [DQS_WIDTH-1:0]     ddr3_dqs_in_lo,
input       [DQ_WIDTH-1:0]      ddr3_dq_in_hi,
input       [DQ_WIDTH-1:0]      ddr3_dq_in_lo,
        
output      [DQS_WIDTH-1:0]     ddr3_dqs_out_hi,
output      [DQS_WIDTH-1:0]     ddr3_dqs_out_lo,
output      [DQ_WIDTH-1:0]      ddr3_dq_out_hi,
output      [DQ_WIDTH-1:0]      ddr3_dq_out_lo,
output      [DM_WIDTH-1:0]      ddr3_dm_hi,
output      [DM_WIDTH-1:0]      ddr3_dm_lo,
output      [ODT_WIDTH-1:0]     ddr3_odt  
  
  );
//Parameter Define
localparam              CLK_PERIOD = tCK * CK_RATIO;

//Register Define

//Wire Define 
wire    [2*CK_RATIO*DQ_WIDTH-1:0]phy_wrdata;
wire    [CK_RATIO*ROW_WIDTH-1:0] phy_address;
wire    [CK_RATIO*BANK_WIDTH-1:0]phy_bank;
wire    [CS_WIDTH*RANK_RATIO*CK_RATIO-1:0] 
                                phy_cs_n;
wire    [CK_RATIO-1:0]          phy_ras_n;
wire    [CK_RATIO-1:0]          phy_cas_n;
wire    [CK_RATIO-1:0]          phy_we_n;
wire                            phy_reset_n;
wire    [3:0]                   calib_aux_out;
wire    [CK_RATIO-1:0]          calib_cke;
wire    [1:0]                   calib_odt;
wire                            write_calib;
wire                            wl_sm_start;
wire                            wl_sm_start_dly;
wire                            calib_ctl_wren;
wire                            calib_cmd_wren;
wire                            calib_wrdata_en;
wire    [2:0]                   calib_cmd;
wire    [1:0]                   calib_seq;
wire    [5:0]                   calib_data_offset_0;
wire    [5:0]                   calib_data_offset_1;
wire    [5:0]                   calib_data_offset_2;
wire    [1:0]                   calib_rank_cnt;
wire    [1:0]                   calib_cas_slot;
wire    [CK_RATIO*ROW_WIDTH-1:0]mux_address;
wire    [3:0]                   mux_aux_out;
wire    [3:0]                   aux_out_map;
wire    [CK_RATIO*BANK_WIDTH-1:0]
                                mux_bank;
wire    [2:0]                   mux_cmd;
wire                            mux_cmd_wren;
wire    [CS_WIDTH*RANK_RATIO*CK_RATIO-1:0]   
                                mux_cs_n;
wire                            mux_ctl_wren;
wire    [1:0]                   mux_cas_slot;
wire    [5:0]                   mux_data_offset;
wire    [5:0]                   mux_data_offset_1;
wire    [5:0]                   mux_data_offset_2;
wire    [CK_RATIO-1:0]          mux_ras_n;
wire    [CK_RATIO-1:0]          mux_cas_n;
wire    [1:0]                   mux_rank_cnt;
wire                            mux_reset_n;
wire    [CK_RATIO-1:0]          mux_we_n;
wire    [2*CK_RATIO*DQ_WIDTH-1:0]              
                                mux_wrdata;
wire    [2*CK_RATIO*(DQ_WIDTH/8)-1:0]          
                                mux_wrdata_mask;
wire                            mux_wrdata_en;
wire    [CK_RATIO-1:0]          mux_cke ;
wire    [1:0]                   mux_odt ;  
    
wire                            dqs_locked_start;
wire                            dqs_locked_done;
wire                            rdlvl_all_dqs_done;
wire    [1:0]                   dqs_bit_sample_err;
wire                            rdlvl_dqs_check_ena;
wire    [DQS_WIDTH-1:0]         wrlvl_dqs_hi;
wire    [DQS_WIDTH-1:0]         wrlvl_dqs_lo;
wire    [DQS_WIDTH-1:0]         ddr_dqs_out_hi;
wire    [DQS_WIDTH-1:0]         ddr_dqs_out_lo;
wire                            wr_level_start;  
wire                            wrlvl_dqs_oe;  
wire                            calib_dq_oe;  
wire                            calib_dqs_oe;  
wire                            wr_level_done;  
wire                            wrlvl_rank_done; 
wire                            wr_level_delay; 
wire                            dqs_invert; 
wire                            dq_check_en; 
wire                            dq_bit_sample_ok; 
wire                            rdlvl_dqs_shift_ena;
wire                            wrlvl_shift_ena;
wire    [2:0]                   rdlvl_dqs_phise_shift;
wire    [2:0]                   wrlvl_phise_shift;
wire    [DM_WIDTH-1:0]          ddr_dm_hi;
wire    [DM_WIDTH-1:0]          ddr_dm_lo;
wire                            phy_rddata_valid_w;
wire    [2*CK_RATIO*DQ_WIDTH-1:0]              
                                phy_rd_data_w;
wire                            mpr_rddata_valid;
wire    [2*CK_RATIO*DQ_WIDTH-1:0]              
                                mpr_rd_data;
wire                            wrcal_rddata_valid;
wire    [2*CK_RATIO*DQ_WIDTH-1:0]
                                wrcal_rd_data;
wire                            mpr_rdlvl_dly;
wire                            idelay_ld;
wire                            wrcal_resume;
wire                            wrcal_pat_resume;
wire    [31:0]                  phy_ctl_wd;  
wire                            phy_dqs_oe;
wire                            phy_dq_oe;
wire                            phy_ctl_full;
wire                            phy_cmd_full;
wire                            phy_data_full;
wire    [2:0]                   shift;  
wire    [4:0]                   shift_sel;
wire                            shift_ena; 
wire                            phy_rst; 
wire    [6:0]                   init_cur_state;
wire    [7:0]                   rd_level_dqs_check;
wire    [7:0]                   wrlvl_dq_check;
reg                             pll_shift_wl_sel;
wire    [16-1:0]                debug_fifo;
wire    [16-1:0]                overflow_fifo;
//Encryption begin
`pragma protect begin_protected
`pragma protect version=1
`pragma protect encrypt_agent="ipecrypt"
`pragma protect encrypt_agent_info="http://ipencrypter.com Version: 20.0.8"
`pragma protect author="author-a"
`pragma protect author_info="author-a-details"

`pragma protect key_keyowner="Efinix Inc."
`pragma protect key_keyname="EFX_K01"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=256)
`pragma protect key_block
MRooqW/DTKPBQOc5XhhEdjT/LGHxJEKaNhTUMu399O3adTuxUuGnWWv/Pa534NiD
d6Xovy6kt4oXeZWf7benYUxrGTmgow39KgklrD9mr8r2N7A0H+mfEJDedwgPrrvK
aW8vHzXGq2PriJMwpwu7YFuQrLUnFkRC1mGPXIEgbNtykWIIxOkcu2qXhkvu+yjQ
iU0MUHY56eEYHIuYZ1o1EjEhjCUdwSWjSaKqfPaB9yd2byQMzLglrEW+zTkN+A0f
8IuY6FvafcP/rPds4wl3+rIqDRQ9irRmNiP7itr2za74Yk03tJ6nSZyzPUR/s2JN
SEcvflK3N52g4tZ8HBectA==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
NpHPCJbhlJU+BzNRou5MfkMNCYL5UZbdtdRy+fkblX/NQz+DYxGxeILZlNZCgMPy
ZsC3VVPYOROYTPvlD0AlasXfB/Aogg9jDcumG3/W8JWczMAx+qCFbEBbZSwDxI1z
o3JnbslYO+HJFzzZcv4S4jrPNzSPZSKDnPZ2+Qc6Fg8=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=22672)
`pragma protect data_block
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
jHClAETKcVJfJLNPbds7uQ==
`pragma protect end_protected
endmodule
