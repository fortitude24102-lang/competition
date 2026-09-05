//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : rd_drive.v
// Version        : 1.4
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2023-05-30 15:35:41
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module rd_drive#(
parameter                       AXI_DW = 32,    
parameter                       AXI_AW = 32
)    
(
//Globle Signals
input                           rstn,
input                           clk,
input           [1:0]           r_axi_mode,
//addr fifo interface 
output  wire                    u2_rdreq,
input           [AXI_AW+7:0]    u2_q,
input                           u2_empty,
//bresp fifo interface 
output  wire                    u4_rdreq,
input           [1:0]           u4_q,
input                           u4_empty,
//Master AXI4 Read Bus Interface
output  wire    [7:0]           m_axi_arid,
output  reg     [AXI_AW-1:0]    m_axi_araddr,
output  reg     [7:0]           m_axi_arlen,
output  wire    [2:0]           m_axi_arsize,
output  wire    [1:0]           m_axi_arburst,
output  wire                    m_axi_arlock,
output  wire    [3:0]           m_axi_arcache,
output  wire    [2:0]           m_axi_arprot,
output  reg                     m_axi_arvalid,
input                           m_axi_arready
);
// Parameter Define
parameter AXSIZE     = AXI_DW/8;
parameter AXSIZE_WTH = $clog2(AXSIZE);

// Register Define

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
K3y7TIyOYBPw43bg4fxF+wZykIo5zUC9X+CIM0db4geOJe3IhGPLxtUYGr2Q3tOy
vaHcJN6u/Snw5YJIaBUoUIbfzFc0GiQegooJeM9JV/8vxDSaXkoHxZT0N4FFexis
AkV6mDXHLER0XriQrJSxRXPbM7LAH6XmSTImMrG6QPqhLAc+mOl7mYJDuhuD7Txl
X+l37wZysIwMQ3E78IwEdAvVh+KlgxdTNmBnlkxtCNTARuOfikJvJyeakcRMLHYG
rdlWwhCFtNn7HPHNs6yE6rQ2CfP3L77KCXps78HQ97g8vRHYpa5LLwhnIoqj6ysJ
TZA9xricYIyLeH6E4tfSsw==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
o9V+EKjE+arKvDdjH1PmsrjGO0uDc5A65FxfWyb4U4Z2xYqFKHpbLkmwISjbuwRs
JUur385ZfYe0yr2XUAii4TdDZ0fxMJ672d1WmKIdAQcKfM2TTw8v5ySwtt8AeMLi
W/U2giP9c3chWK8oxxZbV7J+2duSLv8N2h2mW2okBO8=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=1568)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
