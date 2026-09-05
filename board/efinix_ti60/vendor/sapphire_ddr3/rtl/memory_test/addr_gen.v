//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : addr_gen.v
// Version        : 1.4
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2023-05-30 15:35:06
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module addr_gen#(
parameter                       AXI_DW    = 32,
parameter                       AXI_AW    = 32,
parameter                       MEM_AW    = 20
)
(
input                           rstn,
input                           clk,
//User input information
input                           mode_en,
input           [1:0]           addr_mode,//00,imode;01,fmode;10,rmode;
input           [1:0]           axi_mode,//01:Write Only; 10:Read Only; 00:Read and Write;
input           [AXI_AW-1:0]    saddr,
input           [AXI_AW-1:0]    faddr,
//prbs
input           [MEM_AW-1:0]    raddr,
//len interface
input           [7:0]           len,
input           [7:0]           rlen,
input           [7:0]           flen,
input           [8:0]           rule_len,
input           [2:0]           r_len_mode,
//fifo empty
input                           u1_emptyo,
input                           u2_emptyo,
input                           u3_emptyo,
input                           u4_emptyo,
//addr interface
output  reg     [AXI_AW-1:0]    addr,
input                           addr_ready,
output  reg                     addr_valid,
output  reg     [1:0]           r_axi_mode,
output  reg     [1:0]           r_addr_mode
);
// Parameter Define 
parameter State_idle  = 3'd0;
parameter State_mode  = 3'd1;
parameter State_rmode = 3'd2;
parameter State_fmode = 3'd3;
parameter State_imode = 3'd4;
parameter State_nmode = 3'd5;
parameter State_trs   = 3'd6;
parameter State_wait  = 3'd7;
parameter AXISIZE = AXI_DW/8;
parameter AXSIZE_WTH = $clog2(AXISIZE);
// Register Define
reg     [2:0]                   cur_state;
reg     [2:0]                   next_state;
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
R/fC6a7GLaxBgoXyDSDHp8QUE6MyBu56D01CeOdjxssE7lUvtglxedr8ILGCQQje
xzt1o7fYPcdkK2VOtnnmpcKbfG4jp7oUZvQZVcmaEy0iBKlbizN4zqLZ9HZJ3mWk
6FzoilmcnischoJBH65ZAUHZoE2CMyAikEeYxdkipaATWUmuUunZ2MsTa2D5rthD
8cJ2Fwf2oGaxc03JOBcOI3RrlrG/JrszndWb2rRn9eRZNCOkaFc/ezL/hluT3WXx
hECm4Drf+8TCHDQsBCBChDQehC8RZKoLM5wl3Jgp1DNjUO9S6PMYC2uSRg/OWkOF
ZnyqcdgCtyUQ9WWSyru+Ig==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
mL3QMSiaIKwy7HVLrHrhjS7rw5Jms/OYnjMgrJQ+w3dZ+18BMpGnBHE09AsG1M6h
ngOfvULdXpEclSsHLyCZkfwfJVDTrHyILNiCZ+wX8R0P5m8GFcd4aY3hheHPjY0c
ukRiWRMsl5wx7EmZsV1Q11gaQmgnixGOIR/p+AfCHU4=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=4864)
`pragma protect data_block
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
VxyfuQhR0FZAXqeCrGnf1Q==
`pragma protect end_protected
endmodule
