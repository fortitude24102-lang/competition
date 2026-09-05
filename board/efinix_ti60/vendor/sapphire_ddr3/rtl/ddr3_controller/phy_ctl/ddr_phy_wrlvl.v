//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : ddr_phy_wrlvl.v
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

module ddr_phy_wrlvl # (
parameter                       TCQ         = 100,
parameter                       DQ_WIDTH    = 64,
parameter                       DRAM_WIDTH  = 8,
parameter                       DQS_WIDTH   = 2
)
(
input                           clk,
input                           rst,
input                           wr_level_start,
input                           write_calib,
input                           wl_sm_start,
input                           dq_bit_sample_ok,

output          [7:0]           wrlvl_dq_check,
output  reg                     dqs_invert ,
output  reg                     dq_check_en ,
output  reg                     wrlvl_rank_done ,
output  reg                     wr_level_done ,
output  reg                     wrlvl_shift_ena,  
output  reg     [2:0]           wrlvl_phise_shift,
output  reg     [2:0]           wrlvl_shift
   );

//Parameter Define
localparam              PHISE_TAPS     = 8;
localparam              PLL_SHIFT_NUM  = 4;
localparam              WL_DQS_NUM     = 16;
localparam              PLL_BLANK_NUM  = 64;

localparam              PLL_SHIFT_WTH  = clogb2(PLL_SHIFT_NUM); 
localparam              WL_DQS_WTH     = clogb2(WL_DQS_NUM); 
localparam              TAP_WTH        = clogb2(PHISE_TAPS);
localparam              BLANK_NUM_WTH  = clogb2(PLL_BLANK_NUM);
 
localparam              IDLE           = 3'h0;
localparam              WLDQSEN_WAIT   = 3'h1;
localparam              DQS_WAIT       = 3'h2;
localparam              WL_EADG_CHECK  = 3'h3;
localparam              PLL_SHIFT      = 3'h4;
localparam              SEND_DQS_INC   = 3'h5;
localparam              SEND_DQS_INVERT= 3'h6;
localparam              DQ_CHECK_DONE  = 3'h7;

//Register Define
reg     [2:0]                   cur_state;
reg     [2:0]                   next_state;  
reg     [WL_DQS_WTH-1:0]        wrlvl_check_cnt;
reg     [PLL_SHIFT_WTH-1:0]     pll_shift_cnt;
reg     [2:0]                   wr_level_shift_cnt;
reg     [BLANK_NUM_WTH-1:0]     pll_blank_cnt;
(* async_reg = "true" *)reg                             dq_bit_ok_r1;
reg                             dq_bit_ok_r2;
reg                             dq_bit_ok_r3;
reg     [7:0]                   dq_dynmic_shift;
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
reg     [3:0]                   check_err_cnt;
reg                             dqs_invert_r1;
reg                             dqs_invert_r2;

//Wire Define
wire    [TAP_WTH-1:0]           calibrate_1tmp;
wire    [TAP_WTH-1:0]           calibrate_2tmp;
wire    [TAP_WTH-1:0]           calibrate_3tmp;
wire                            case_1tmp;
wire                            case_2tmp;
wire                            case_3tmp;
wire    [TAP_WTH-1:0]           tap_cnt;  
wire                            dqs_invert_edge;
//wire    [7:0]                 check_debug = 8'b01111111;
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
PtTCCjQt0Vf2kK2o9q4W89Yb6/y2F5FMNzTy1PZwmJ9xNWSHGvCIC4kF+4eDQnL4
kf4dAntqMspk4FvPapgP90IRao9qXgQ0FO5LwmwQyELR7jfWCtA6GXv9QmxD8PlO
s+rNn2tjInuvaO/AS4bitPTXEP6dH1EcILo+9RUf+ngpjecihKFvcgilzcRCD4wG
kr5T6rzvFPIgSziB8qMo8w6OHLxTrSNj5EXmuNKtjieNDnabik7C5UPfmuHwfQX8
dYDL7Ak27d33FEunhSqePN1TMZbE8MKCoHJSMo2oOe5dRBjdV2PpiaNjya6YikTk
8eUwTfhSvrdikdF+fIsv8w==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
f/hI8jGS9Fu/yThNSrFWyJqBjtpFgzDAeiDCN5iZPu6hdeG6jnm7TCeRyl3ehz26
LQFVP4JvkTyW/Afbv+r+jTl7xu40lQocfrRsYJDggZAdM5uxxWe4Wko1AbW3m+AG
85Xdec1blOATbJQZnKH2vXhOCM+xm+JHmIAeDF/XonQ=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=15504)
`pragma protect data_block
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
6F30N8KuDPIBhPAEPzTC9YGiNUZNhE+ZL2jC/WGYYDthOCHh/GTZJL3Nm70jxPyW
/4RGjZICZeWUmltT1QNcnfQinGsnGDdHZa6Oril+z5omm2h0qHQCt/35aDi/pnx4
htnBdjlw64npjX2Ts/+Yt3A704aowVFsXRKQEF5rCMJsEo4RzVLhK/66iGS/UgoJ
A8wIwBgD2yyBQQy7EMqBK90UGkDvA3lrQ8ZV0vXRA7YWAcPZsUFZ8IORujxjVQuD
hau9A/vTThkQmu+l42XupZ5CNlnMV7yVrQoRmbCSn+6WUaOozYuNgtJJgO+hsgyP
LVBhXzml8Zb+clJP9AcJmCbvSxbPjQ7aUySoMBWv3GxB2R1/NmvRu8ZZHWtxVsUV
j1cD5EGTYbnf6s1new2lUgPAQ8EknZ1WKmqgwBFWo1SpAWudvTCWbq1gqwJpV9dh
AqPKyV6UgLoZmBimNQAb/ZhBDfu5ucKCQO3JWlT/YzyG51NTSS8DsIE628L9vxlS
V0H/ehI0b3W+ZMc7g0ndkB7jHgZ5DClq1oDk1ato2V7ru3mEicrfabyHdQXwHYx5
OKbv25c5kNrp6iW2depfyhtmT2QzYkruOq56ZYpirxZIGEjqNUaUtBtoBfJ2BOlx
LtPEqacgwW3i1ZOyuyrUuSwnq1sVeI3BrGvHNeWEl0TE94h8GkFjATQfBBIQc0Xq
6YgmHhjl/4C6LKnXiSd2soMbOOqnzztyd8BN6UHU1yUNTpcQsmRpysMNy+8QJwyZ
u9q/OQaIpN8YvJ00hmJzaR4s7alRSvhyuaUhGIC+c5+aAgluDXCjQXPC4Xe4aaoI
gFBWawz+UhPkrq8bmozwXmrN+hWmLmC0k9XzB8noQA+roJMezY1fmJZExWajaBXw
OjIhJXR4Zwp4/LCJ4lBCQueaLo8qTPVVSmpwSB+c6IY/eGI3XUlzs/U9JJxW4YUD
q+BtIHJRGlyOCY1eZAaRyoxKzDM0KmI2hczygndkRO61OWZDLgxmVWDGFtdgVcKn
TLu2xKQVFFEWdZ68MaM9MiZ40EHTVGSWTlachraVuWQQfg9N1fsHV9jC0MGg0U7G
se4KOQMKjXfjB/6jhKs9ffHAexXklg4/e6R5Ig9SLznfdNgtB+BQzw1upfoRgXZy
+ZTRGb+lYnUFDWwg9tFuYLvdD6VX29wMajPW/UFMSkBabrPG05InhyYtHH+tqQhR
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
`pragma protect end_protected
endmodule
