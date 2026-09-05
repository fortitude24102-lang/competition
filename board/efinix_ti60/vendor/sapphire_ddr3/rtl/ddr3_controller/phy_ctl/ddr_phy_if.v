//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : ddr_phy_if.v
// Version        : 1.3
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


  `timescale 1ps/1ps
module ddr_phy_if #(
parameter                       tCK          = 1500,        
parameter                       WL           = 5,           
parameter                       nCL          = 5,                   
parameter                       CK_RATIO     = 4,           
parameter                       BANK_WIDTH   = 2,
parameter                       RANK_RATIO   = 1,           
parameter                       DQ_WIDTH     = 64,
parameter                       DQS_WIDTH    = 8,
parameter                       DM_WIDTH     = 8,
parameter                       ROW_WIDTH    = 14,
parameter                       CS_WIDTH     = 1,
parameter                       ODT_WIDTH    = 1,
parameter                       CKE_WIDTH    = 1       

)(
// clock & reset
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

input                           phy_cmd_wr_en,
input                           phy_data_wr_en,
input           [31:0]          phy_ctl_wd,
input                           phy_ctl_wr,
output                          phy_ctl_full,
output                          phy_cmd_full,
output                          phy_data_full,
output                          wl_sm_start,
output  reg     [1:0]           dqs_bit_sample_err,
output  reg                     dq_bit_sample_ok,
output  reg                     ddr_dq_vld_r,
input                           dq_check_en,
input                           rdlvl_dqs_check_ena,
input                           idelay_ld,
input                           wrlvl_rank_done,
input                           wr_level_delay,
input                           mpr_rdlvl_dly,
input                           mpr_rdlvl_en,
input                           dqs_invert,
// From/to calibration logic/soft PHY
input                           init_calib_complete,
input           [CK_RATIO-1:0]  mux_cke,
input           [CS_WIDTH*RANK_RATIO*CK_RATIO-1:0] 
                                mux_cs_n,
input           [CK_RATIO-1:0]  mux_ras_n,
input           [CK_RATIO-1:0]  mux_cas_n,
input           [CK_RATIO-1:0]  mux_we_n,
input           [CK_RATIO*BANK_WIDTH-1:0] 
                                mux_bank,
input           [CK_RATIO*ROW_WIDTH-1:0]  
                                mux_address,
input           [1:0]           mux_odt,
input           [2*CK_RATIO*DQ_WIDTH-1:0] 
                                mux_wrdata,
input           [2*CK_RATIO*DM_WIDTH-1:0] 
                                mux_wrdata_mask,
input                           mux_reset_n,
output                          phy_rddata_valid,
output           [2*CK_RATIO*DQ_WIDTH-1:0]
                                phy_rd_data,
output           [8-1:0]        debug_fifo,                                
output           [8-1:0]        overflow_fifo,                                
// DDR bus signals
output                          ddr_ck_hi,
output                          ddr_ck_lo,
output           [CKE_WIDTH-1:0]ddr_cke,
output                          ddr_reset_n,
output           [CS_WIDTH*RANK_RATIO-1:0]
                                ddr_cs_n,
output                          ddr_ras_n,
output                          ddr_cas_n,
output                          ddr_we_n,
output           [BANK_WIDTH-1:0]
                                ddr_ba,
output           [ROW_WIDTH-1:0]ddr_addr,
               
input            [DQS_WIDTH-1:0]ddr_dqs_in_hi,
input            [DQS_WIDTH-1:0]ddr_dqs_in_lo,
input            [DQ_WIDTH-1:0] ddr_dq_in_hi,
input            [DQ_WIDTH-1:0] ddr_dq_in_lo,

output  reg                     phy_dqs_oe,
output  reg                     phy_dq_oe,
output           [DQS_WIDTH-1:0]ddr_dqs_out_hi,
output           [DQS_WIDTH-1:0]ddr_dqs_out_lo,
output  reg      [DQ_WIDTH-1:0] ddr_dq_out_hi,
output  reg      [DQ_WIDTH-1:0] ddr_dq_out_lo,
output  reg      [DM_WIDTH-1:0] ddr_dm_hi,
output  reg      [DM_WIDTH-1:0] ddr_dm_lo,
output  reg      [ODT_WIDTH-1:0]ddr_odt

);

//Parameter Define
localparam CWL_M =  WL ;//+ nAL;
localparam CMD_WTH = (CKE_WIDTH+3+ (CS_WIDTH*RANK_RATIO)+BANK_WIDTH+ROW_WIDTH) *CK_RATIO;
localparam DFIFO_WTH =2*CK_RATIO*(DQ_WIDTH + DM_WIDTH);
localparam FIFO_DEPTH =16;
localparam WR  = 4'b0100;
localparam RD  = 4'b0101;
localparam POS = 2'b10;
localparam NEG = 2'b01;

//Register Define
reg                             u1_wrreq_r;
reg     [CMD_WTH+1:0]           u1_data_r;
reg                             u2_wrreq_r;
reg     [31:0]                  u2_data_r;
reg                             u4_wrreq;
reg     [2*CK_RATIO*(DQ_WIDTH)-1:0]    
                                u4_data;
reg     [CK_RATIO-1:0]          rd_data_cke  ;
reg     [CS_WIDTH*RANK_RATIO*CK_RATIO-1:0]
                                rd_data_cs_n ;
reg     [CK_RATIO-1:0]          rd_data_ras_n;
reg     [CK_RATIO-1:0]          rd_data_cas_n;
reg     [CK_RATIO-1:0]          rd_data_we_n ;
reg     [CK_RATIO*BANK_WIDTH-1:0]
                                rd_data_ba   ;
reg     [CK_RATIO*ROW_WIDTH-1:0]       
                                rd_data_addr ;
reg                             rd_data_cke_r1;
reg                             mux_odt_r1;
reg                             mux_odt_r2;
reg                             mux_odt_r3;
reg     [WL+1:0]                mux_odt_delay;
reg                             rd_data_cs_n_r1;
reg                             rd_data_ras_n_r1;
reg                             rd_data_cas_n_r1;
reg                             rd_data_we_n_r1;
reg     [BANK_WIDTH-1:0]        rd_data_ba_r1   ;
reg     [ROW_WIDTH-1:0]         rd_data_addr_r1 ;
reg                             ddr_ctl_wren;
reg                             wr_cmd_en;
reg     [1:0]                   mem_dqs_out;
reg     [2*CK_RATIO*DQ_WIDTH-1:0]
                                mem_dq_out   ;
reg     [2*DQ_WIDTH-1:0]        mem_dq_out_r1;
reg     [2*CK_RATIO*DM_WIDTH-1:0]      
                                mem_dm_out   ;
reg     [2*DM_WIDTH-1:0]        mem_dm_out_r1;
reg     [DQ_WIDTH-1:0]          ddr_dq_in_hi_r1;
reg     [DQ_WIDTH-1:0]          ddr_dq_in_hi_r2;
reg     [DQ_WIDTH-1:0]          ddr_dq_in_hi_r3;
reg     [DQ_WIDTH-1:0]          ddr_dq_in_lo_r1;
reg     [DQ_WIDTH-1:0]          ddr_dq_in_lo_r2;
reg     [DQ_WIDTH-1:0]          ddr_dq_in_lo_r3;
reg     [DQS_WIDTH-1:0]         ddr_dqs_in_hi_r1;
reg     [DQS_WIDTH-1:0]         ddr_dqs_in_hi_r2;
reg     [DQS_WIDTH-1:0]         ddr_dqs_in_hi_r3;
reg     [DQS_WIDTH-1:0]         ddr_dqs_in_lo_r1;
reg     [DQS_WIDTH-1:0]         ddr_dqs_in_lo_r2;
reg     [DQS_WIDTH-1:0]         ddr_dqs_in_lo_r3;
reg     [1:0]                   wr_data_cnt;
reg     [2*CK_RATIO-1:0]        rd_dq_ena;
reg     [WL+2:0]                wr_data_en;
reg     [WL+4:0]                wr_ctl_en;
(* async_reg = "true" *)reg     idelay_ld_r1;
(* async_reg = "true" *)reg     idelay_ld_r2;
(* async_reg = "true" *)reg     idelay_ld_r3;
reg                             wrcal_delay;
reg                             rdlvl_check_ena_r1;
reg                             rdlvl_check_ena_r2;
reg                             rdlvl_check_ena_r3;
reg                             rdlvl_check_ena;
reg                             wrlvl_check_ena;
(* async_reg = "true" *)reg     dq_check_en_r1;
(* async_reg = "true" *)reg     dq_check_en_r2;
(* async_reg = "true" *)reg     dq_check_en_r3;
reg                             dq_in_hi_r1;
reg                             dq_in_hi_r2;
reg                             dq_in_lo_r1;
reg                             dq_in_lo_r2;
reg     [1:0]                   dq_bit_sample_cnt;
reg     [DQS_WIDTH-1:0]         dqs_sample_err;
(* async_reg = "true" *)reg     ddr_rden_r1;
(* async_reg = "true" *)reg     ddr_rden_r2;
(* async_reg = "true" *)reg     ddr_rden_r3;
reg     [1:0]                   dqs_sample_reslut[DQS_WIDTH-1:0];
(* async_reg = "true" *)reg     ddr_wren_r1;
(* async_reg = "true" *)reg     ddr_wren_r2;
(* async_reg = "true" *)reg     ddr_wren_r3;
(* async_reg = "true" *)reg     ddr_wren_r4;
(* async_reg = "true" *)reg     ddr_wren_r5;
reg     [3:0]                   stable_cnt[DQS_WIDTH-1:0];
reg     [DQS_WIDTH-1:0]         dq_in_hi_or_prev;
reg     [DQS_WIDTH-1:0]         flag_ck_posedge;
reg     [DQS_WIDTH-1:0]         flag_ck_negedge;
reg     [DQS_WIDTH-1:0]         rd_data_edge_detect_r;
reg     [nCL+6:0]               rd_data_en_ctl;
reg                             rd_data_en;
reg                             wl_dqs_out_en ;
reg                             wl_dqs_en     ;
reg                             wl_dqs_en_r1  ;
reg                             wl_dqs_en_r2  ;
//Wire Define
wire                            u1_wrreq_ns;
wire    [CMD_WTH+1:0]           u1_data_ns;
wire                            u1_wrreq;
wire    [CMD_WTH+1:0]           u1_data;
wire                            u1_almfull;
wire                            u1_full;
wire                            u1_progfull;
wire                            u1_empty;
wire                            u1_rdreq;
wire    [CMD_WTH+1:0]           u1_q;
wire                            u2_wrreq_ns;
wire    [31:0]                  u2_data_ns;
wire                            u2_wrreq;
wire    [31:0]                  u2_data;
wire    [31:0]                  u2_q;
wire                            u2_almfull;
wire                            u2_full;
wire                            u2_empty;
wire                            u2_rdreq;
wire                            u3_wrreq;
wire    [2*CK_RATIO*(DQ_WIDTH/8+DQ_WIDTH)-1:0] 
                                u3_data;
wire    [2*CK_RATIO*(DQ_WIDTH/8+DQ_WIDTH)-1:0] 
                                u3_q;
wire                            u3_almfull;
wire                            u3_full;
wire                            u3_empty;
wire                            u3_rdreq;
wire    [2*CK_RATIO*(DQ_WIDTH)-1:0]    
                                u4_q;
wire                            u4_almfull;
wire                            u4_full;
wire                            u4_empty;
wire                            u4_wrreq_temp;
wire                            u4_rdreq;
wire    [2*DQ_WIDTH-1:0]        ddr_dq_data;
wire                            cmd_fifo_afull;
wire                            cmd_fifo_full;
wire                            ctl_fifo_full;
wire                            ctl_fifo_afull;
wire    [CMD_WTH+1:0]           phy_din;
wire    [3:0]                   ddr_cmd;
wire    [2:0]                   phy_cmd;
wire    [5:0]                   phy_data_offset;
wire                            wr_data_en_ns;
wire                            wr_data_en_temp;
wire                            wr_ctl_en_temp;
wire                            dqs_bit_and_hi;
wire                            dqs_bit_and_lo;
wire                            wr_dqs_en0;
wire                            wr_dqs_en1;
wire                            wr_dq_in_en;
wire    [DQ_WIDTH/8-1:0]        dq_in_hi_or;
wire    [DQ_WIDTH/8-1:0]        dq_in_lo_or;
wire    [DQ_WIDTH-1:0]          ddr_dq_out_hi_temp1;
wire    [DQ_WIDTH-1:0]          ddr_dq_out_lo_temp1;
wire    [DM_WIDTH-1:0]          ddr_dm_hi_temp1;
wire    [DM_WIDTH-1:0]          ddr_dm_lo_temp1;
wire    [DQ_WIDTH-1:0]          ddr_dq_out_hi_temp2;
wire    [DQ_WIDTH-1:0]          ddr_dq_out_lo_temp2;
wire    [DM_WIDTH-1:0]          ddr_dm_hi_temp2;
wire    [DM_WIDTH-1:0]          ddr_dm_lo_temp2;
wire    [2*DQ_WIDTH-1:0]        mem_dq_out_r0;
wire    [2*DM_WIDTH-1:0]        mem_dm_out_r0;
wire    [1:0]                   dqs_sample_edge  [DQS_WIDTH-1:0];
wire    [1:0]                   dqs_sample       [DQS_WIDTH-1:0];
wire    [DQS_WIDTH-1:0]         dqs_sample_r     [1:0]          ;
wire    [5:0]                   u1_rdata_cnt;
wire    [5:0]                   u1_wdata_cnt;
wire                            u1_rdreq_temp;
reg     [1:0]                   u2_rd_cmd_cnt;
wire                            u2_rdreq_temp;
wire    [5:0]                   u2_rdata_cnt;
wire    [5:0]                   u2_wdata_cnt;
reg                             rd_ctl_en;
reg     [1:0]                   u1_rd_cmd_cnt;
reg                             rd_cmd_en;
wire    [4:0]                   u1_rddata_count;
wire    [4:0]                   u2_rddata_count;
wire                            ddr_rden;
wire                            ddr_wren;
reg                             ddr_rden_dly;
reg                             ddr_wren_dly;
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
TFKkjooAB6OBZTgXZWW55/HS+nTteE8ZeJEfj/zkEd4fHG+u8xgM+HPwNI6/JQzT
DPiDcyLLIZXERdD8xGsyTLXurNqsywVdSd3NM7G/OYhHwN8edJ0wJ0JHLn2O8yU9
3XSQuGf+xGsjwiyuK1FtGQjQ/IJvOfYxWwDwQm0+DLKAa/iygsdq/3K27yrZi/qS
qARmajNEtFvkEfgjJPYr70mAhKflrW9RvtQUoQ1Qsvmx2vZB5R2fNwC0FuYbeh6B
7YylTHZdjXwXOpoC/JRTP/k4NdLNYUTvPXU3T1QBGaOTQEM4mHxErHXFTAgZPCy5
1fde1ARPX1vbVyzWxkNXzQ==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
NZnQtWJnLYDpce4hUttSRS/zbofIV48urMB/V5ZIUd+ypjgRw56CMfFW7fzYSxtn
Tn9hKrZkVDvrJ+RB8E1CmBE2kmsqPRs+r6qGIh6Ps8kmqaKtlYCyGtPpsrqI1GvK
Jmis0UnDn2ftZ2yAkqZEVG1nDfylIHjThkLBAfhXM+U=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=29408)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
