//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : ddr_mpr_rdlvl.v
// Version        : 1.0
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
module ddr_mpr_rdlvl # (
parameter                       TCQ               = 100,
parameter                       DQS_CNT_WIDTH     = 3,
parameter                       CK_RATIO          = 4,
parameter                       DRAM_WIDTH        = 8,      // # of DQ per DQS
parameter                       DQ_WIDTH          = 64,
parameter                       DQS_WIDTH         = 2
)
(
input                           clk,
input                           rst,
input                           mpr_rdlvl_en,

input                           phy_rddata_valid,
input           [2*CK_RATIO*DQ_WIDTH-1:0]     
                                phy_rd_data,
output  reg                     mpr_rdlvl_dly

);
//Parameter Define

//Register Define
reg     [DRAM_WIDTH-1:0]        mux_rd_fall0_r;
reg     [DRAM_WIDTH-1:0]        mux_rd_fall1_r;
reg     [DRAM_WIDTH-1:0]        mux_rd_rise0_r;
reg     [DRAM_WIDTH-1:0]        mux_rd_rise1_r;
reg     [DRAM_WIDTH-1:0]        mux_rd_fall2_r;
reg     [DRAM_WIDTH-1:0]        mux_rd_fall3_r;
reg     [DRAM_WIDTH-1:0]        mux_rd_rise2_r;
reg     [DRAM_WIDTH-1:0]        mux_rd_rise3_r;
reg                             mpr_rd_rise0_prev_r;
reg                             mpr_rd_fall0_prev_r;
reg                             mpr_rd_rise1_prev_r;
reg                             mpr_rd_fall1_prev_r;
reg                             mpr_rd_rise2_prev_r;
reg                             mpr_rd_fall2_prev_r;
reg                             mpr_rd_rise3_prev_r;
reg                             mpr_rd_fall3_prev_r;
reg                             rd_active_r;
reg                             rd_active_r1;
reg                             rd_active_r2;
reg                             rd_active_r3;
reg                             rd_active_r4;
reg                             rd_active_r5;
reg     [3:0]                   mpr_rdlvl_cnt;
reg     [2:0]                   stable_idel_cnt;
reg                             inhibit_edge_detect_r;
reg                             idel_mpr_pat_detect_r;

//Wire Define   
wire    [DQ_WIDTH-1:0]          rd_data_rise0;
wire    [DQ_WIDTH-1:0]          rd_data_fall0;
wire    [DQ_WIDTH-1:0]          rd_data_rise1;
wire    [DQ_WIDTH-1:0]          rd_data_fall1;
wire    [DQ_WIDTH-1:0]          rd_data_rise2;
wire    [DQ_WIDTH-1:0]          rd_data_fall2;
wire    [DQ_WIDTH-1:0]          rd_data_rise3;
wire    [DQ_WIDTH-1:0]          rd_data_fall3;
wire    [DQS_CNT_WIDTH:0]       rd_mux_sel_r;

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
cdgQIQ75TOJrdr7Ert/d50T8kiTgYxGm9h+v35XewGJqs+MOJ9SIlXeQzsAbjZ+y
6X4lsmkvk1iY9nFvPvvwr1zwgbnyQzihHDwDqcJniBrwWsvNZ8dI7jF7v6OR7ZGV
q4R5qWH4D12/JQXLFlqZx30CBLNR2UHLUmNLJqZX5kdtJGQbS6ShmAELazGAEOwc
H0nYrtenXIb+LE7Yn1IN2TU8dyVmpLP1Isk4M0mERbvxUkVW8gDsWN0+yiFx3K7p
uNplfvd8GA8HroFUNGDIXArk36ThZl3DJ4n1b3MLm8WrcW001isEDEoRXeiAu8ou
jnz9ltd9QpRPQpaEMGbS8A==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
auvslFX1kADzKUykw641bsHdKzwuxX/LFngjji/XKb4TcvGzCUV+eKvAn2LICcOd
OCQOtkEaKftPiBPQJlMJ/71v8qHEo4/5bqLFw+RFu6VJmWlE/0IliD14Qi8rk5KX
QY+4WftLSOOj4s2YRAD/ZNUVG9vX4RRue+MoaGvA0O8=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=9408)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
