//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : test_seq.v
// Version        : 1.2
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2023-05-30 15:36:20
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module test_seq#(
parameter                       AXI_DW    = 32,
parameter                       AXI_AW    = 32,
parameter                       MEM_AW    = 20
)
(
//Globle Signals
input                           rstn,
input                           clk,
//User input information
input                           mode_en,
input           [1:0]           addr_mode,
input           [1:0]           axi_mode,
input           [AXI_AW-1:0]    saddr,
input           [AXI_AW-1:0]    faddr,
input           [1:0]           data_mode,
input           [AXI_DW-1:0]    fdata,
input           [2:0]           len_mode,
input           [7:0]           flen,
//fifo empty
input                           u1_emptyo,
input                           u2_emptyo,
input                           u3_emptyo,
input                           u4_emptyo,
//prbs
input           [MEM_AW-1:0]    raddr,
input           [AXI_DW-1:0]    rdata,
input           [7:0]           rlen,
//seq interface
output  wire    [AXI_AW-1:0]    addr,
input                           addr_ready,
output  wire                    addr_valid,
output  wire    [1:0]           r_addr_mode,
output  wire    [1:0]           r_axi_mode,
output  wire    [AXI_DW-1:0]    data,
input                           data_ready,
output  wire                    data_valid,
output  wire    [7:0]           len,
input                           len_ready,
output  wire                    len_valid
);

// Parameter Define 

// Register Define

// Wire Define
wire    [2:0]                   r_len_mode;
wire    [8:0]                   rule_len;
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
LNkTlRcIl2K5nXxU76I6ASMaZwyFTDMZEYj7oLngoZYePdcx0IoF2pFIL+RYTec0
AIZ+4lsucSrwUjRcr27uv00aHlhtUW8DB/nKAibvlNzqn3K4KkSAJ6aYdl6lMTdc
bQwgSYWl4CwyqhQLXNvESuliXI0QrYGKgWuAk4oi1SYyLcrLVpEaR3pFHssDhBXP
06LUOa8knpTauzjX3XZa9X3ZUpUGo29hMYQ8PxEcba2v1NqaLgAukY9r9nS+OSiE
yz1+qJC5KtH9o8ruVstJ5jeHiLhqYuycPmkZ6brEYQ+BpD8KLoyNPaAiIRoXjBha
CdmbWhh+M2AjtPwqNwGLJQ==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
fHCPGGiQDtaBN6MzLHt8umaWSJIQzL1Xzl7pXaRpB3ijwL5Qebl+2yBZGZs7cPRe
eTI+Q7LETqOBROoOt4jeA6O9tsOKbfbHoz+Vvo0i/D/0z1R/SmIH99cLiUhTFMag
7IriypFtkQ7Vxry4Us7mhUBotCuqxLSGD76Fw6tzh8o=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=4128)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
