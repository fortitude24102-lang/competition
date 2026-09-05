//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : ddr_phy_rdlvl_dqs.v
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

module ddr_phy_rdlvl_dqs #(
parameter                       TCQ             = 100,
parameter                       DQS_CHECK_TIME  = 512,
parameter                       DQS_CNT_WIDTH   = 3,
parameter                       DQS_WIDTH       = 2
)
(
input                           clk,
input                           rst,
input                           rd_dqs_start,
input           [1:0]           dqs_bit_sample_err,

output          [7:0]           rd_level_dqs_check,
output  reg                     rdlvl_dqs_check_ena,
output  reg                     rd_level_dqs_done,
output  reg                     rdlvl_all_dqs_done,
output  reg                     rdlvl_dqs_shift_ena,
output  reg     [2:0]           rdlvl_dqs_phise_shift,
output  reg     [2:0]           rdlvl_shift
);

//Parameter Define
localparam              PHISE_TAPS     = 8;
localparam              PLL_SHIFT_NUM  = 4;
localparam              WIAT_CNT       = 25;
localparam              PLL_BLANK_NUM  = 64;
localparam              TAP_WTH        = clogb2(PHISE_TAPS);
localparam              WIAT_WTH       = clogb2(WIAT_CNT);
localparam              DQS_CHECK_WTH  = clogb2(DQS_CHECK_TIME); 
localparam              PLL_SHIFT_WTH  = clogb2(PLL_SHIFT_NUM); 
localparam              BLANK_NUM_WTH  = clogb2(PLL_BLANK_NUM);
            
localparam              IDLE           = 3'h0;
localparam              RD_DQS_WAIT    = 3'h1;
localparam              RD_DQS_CHECK   = 3'h2;
localparam              PLL_SHIFT      = 3'h3;
localparam              RD_DQS_LOOP    = 3'h4;
localparam              PLL_BLANK      = 3'h5;
localparam              DQS_CHECK_DONE = 3'h6;

//Register Define
reg     [2:0]                   cur_state;
reg     [2:0]                   next_state;
(* async_reg = "true" *)reg     [1:0]                   dqs_bit_sample_r1;
reg     [1:0]                   dqs_bit_sample_r2;
reg     [1:0]                   dqs_bit_sample_r3;
reg     [1:0]                   dqs_bit_sample_r4;
reg     [WIAT_WTH-1:0]          wait_cnt;
reg     [DQS_CHECK_WTH-1:0]     rd_level_dqs_cnt;
reg     [PLL_SHIFT_WTH-1:0]     pll_shift_cnt;
reg     [TAP_WTH-1:0]           rd_level_shift_cnt;
reg     [BLANK_NUM_WTH-1:0]     pll_blank_cnt;
reg     [PHISE_TAPS-1:0]        dqs_dynmic_shift;
reg                             check_err;
reg                             check_err_r;
reg     [TAP_WTH-1:0]           rising_tap;
reg                             rising_tap_vld;
reg     [TAP_WTH-1:0]           next_rising_tap;
reg                             next_rising_tap_vld;
reg     [TAP_WTH-1:0]           first_rising_tap;
reg                             first_rising_tap_vld;
reg     [TAP_WTH-1:0]           failling_tap;
reg                             failling_tap_vld;
reg     [TAP_WTH-1:0]           next_failling_tap;
reg                             next_failling_tap_vld;
reg                             replace_flag;
reg     [TAP_WTH-1:0]           calibrate_tap;
reg                             last_flag;
reg                             clean_flag;
//Wire Define
wire    [TAP_WTH-1:0]           calibrate_1tmp;
wire    [TAP_WTH-1:0]           calibrate_2tmp;
wire    [TAP_WTH-1:0]           calibrate_3tmp;
wire                            case_1tmp;
wire                            case_2tmp;
wire                            case_3tmp;
wire    [TAP_WTH-1:0]           tap_cnt;  

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
cIEbk6KxpFDWts14L/GLSGDTM4PsjSv1TpohSzmIqExvFQc1Fe843cZGg8QVRUkA
Y4loq5aIGZR2wyw076R4UNR+JcJ1F4qZ+3bZGXhDSwl/IOEquFgaVgFQ3ZIhHne8
uYClndiIolucRuqdOZAmiOREHhgXV6W62jKsTYafRUExDrNN6jbGUEDCCHG1JuWL
lvhCrk8vXvvYF/hU80JAWCSN3kWJBEuRBpxsf93rxItWnP/c9GwMX/bOn5wJMmA7
LWR8j8YCAR9wTNjWS/CVAUmC6UhM4h2K0tu2cnyj885pFURT4Sqj+2f7goyM+ShP
PLqV9G/OR3X2f7FZ1T6dbg==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
XaRndn9HoW13gbrwVbMJbW4lBtLGc3ie8rhAWHzciBZNhwu1TL+Z16iOQZxOudTX
MD2ercMASUpmD2IEz1iN5/nTxybMuzgos9gYFHvaBRWckAvPnT2ShslYJX85i82F
Q4dJdX7vvcNhOC+RMiuE1ick5GdARYzFJGaeruP2ggU=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=13728)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
