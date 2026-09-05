//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : data_gen.v
// Version        : 1.4
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2023-05-30 15:36:43
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module data_gen#(
parameter                       AXI_DW = 32
)
(
//Globle Signals
input                           rstn,
input                           clk,
//User input information
input                           mode_en,
input           [1:0]           data_mode,
input           [AXI_DW-1:0]    fdata,
//prbs
input           [AXI_DW-1:0]    rdata,
//data interface
output  reg     [AXI_DW-1:0]    data,
input                           data_ready,
output  reg                     data_valid
);
// Parameter Define 
parameter State_idle  = 3'd0;
parameter State_mode  = 3'd1;
parameter State_rmode = 3'd2;
parameter State_fmode = 3'd3;
parameter State_imode = 3'd4;
parameter State_nmode = 3'd5;
parameter State_trs   = 3'd6;
parameter AXISIZE = AXI_DW/8;
// Register Define
reg     [2:0]                   cur_state;
reg     [2:0]                   next_state;
reg     [1:0]                   r_data_mode;
reg     [7:0]                   idata;

// Wire Define

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
dPvLtF2zoyMzuPV/rC+wNhiyugQbwxs917XzVXzGGuCFemz07X+F00FOuNnvMbQA
jkexb+bpTw2f9s21li8vyvv6VCBaU2QI1vVKIr05nFlebshTN/UdFuK/t5UuRhqQ
qEgIjYTCzSygMRWc6ESzcvzBmQ3ASxCroYXc7J0l8mWtGKdzKqGNvkqooRzKKyZC
ZOyguYf2lFu9aSRdcne18tsyPTh+Ke5RanignL2v5zXd+mk/4idT1IfkbkjX+XQF
muDwl2N0Ag76h3/4zqV7nErxw1fe1oRe3ZRCvgPnfXhzazRwDQVkpH3UADGQuclg
WWMXW2TfkqU91CpdN0lT/Q==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
FKwM3MEXQqSjmslmkLkoqIezs8f76vMKc2Q5zBcivIhwvfJkV1+W8XBh51BihZYI
iwxE+iDau/wsMDg0344aDSoBMynKd7YWKPTZKROA3GJYyzkh9KDSDBlcUMgerPw+
kpoJbHf/HSwbDZ0VKYt8tBDzVSYsDc68Z2fg46V9Bjw=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=3200)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
