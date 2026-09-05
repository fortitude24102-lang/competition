//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : wr_drive.v
// Version        : 1.4
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2023-05-30 15:35:30
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module wr_drive#(
parameter                       AXI_DW = 32,
parameter                       AXI_AW = 32
)
(
//Globle Signals
input                           rstn,
input                           clk,
//axi work mode
input           [1:0]           r_axi_mode,
//seq interface
input           [AXI_AW-1:0]    addr,
output  wire                    addr_ready,
input                           addr_valid,
input           [1:0]           r_addr_mode,
input           [AXI_DW-1:0]    data,
output  wire                    data_ready,
input                           data_valid,
input           [7:0]           len,
output  wire                    len_ready,
input                           len_valid,
//check interface
input                           read_end,
//data fifo interface
output  wire                    u1_wrreq,
input                           u1_full,
output  wire    [AXI_DW-1:0]    u1_data,
//addr+len fifo interface
output  wire                    u2_wrreq,
input                           u2_full,
output  wire    [AXI_AW+7:0]    u2_data,
input           [AXI_AW-1:0]    u2_q,
input                           u2_empty,
//bresp fifo interface
output  wire                    u4_wrreq,
input                           u4_full,
output  wire    [1:0]           u4_data,
//Master AXI4 Write Bus Interface
output  wire    [7:0]           m_axi_awid,
output  wire    [AXI_AW-1:0]    m_axi_awaddr,
output  wire    [7:0]           m_axi_awlen,
output  wire    [2:0]           m_axi_awsize,
output  wire    [1:0]           m_axi_awburst,
output  wire                    m_axi_awlock,
output  wire    [3:0]           m_axi_awcache,
output  wire    [2:0]           m_axi_awprot,
output  reg                     m_axi_awvalid,
input                           m_axi_awready,
output  wire    [AXI_DW-1:0]    m_axi_wdata,
output  wire    [AXI_DW/8-1:0]  m_axi_wstrb,
output  reg                     m_axi_wlast,
output  reg                     m_axi_wvalid,
input                           m_axi_wready,
input           [7:0]           m_axi_bid,
input           [1:0]           m_axi_bresp,
input                           m_axi_bvalid,
output  wire                    m_axi_bready
);

// Parameter Define 
parameter AXSIZE     = AXI_DW/8;
parameter AXSIZE_WTH = $clog2(AXSIZE);

// Register Define
reg     [7:0]                   burst_cnt;
reg                             waddr_wait;
reg                             burst_wait;
reg     [7:0]                   r_len;
reg     [AXI_AW-1:0]            r_addr;

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
Ni83FCKvSl4Nuw8KAU0o11zwgLIqB+Oj7h2XkknLnMxTe/FGiNlzEoCP0Ilw/y+2
K40dmFbZ4W6g6RzN2gxgGSsPndZPg8MbUByvv3dxz3ZfCXYe9rvRs2Fla57hAuCC
9qoJgnHXJ40UR82oJ+sx0EpMZJ0ItkQ9k/k+qmbJebmU5SOpAug+ZsoBuHHq/Qda
6GbkDarelr7CvwMdLou9k+LIA6MSKUZxxjhwkORHrQobvpoqi83IoX33MjRxgqyN
mwE1AJoje3/COArCvlIOJDM//Sd/rOui08bMhwtezSPTsDYVE/ozkhInSki9zZhM
6eYZW/yPT8B6bP0BfOyMDw==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
AbczPFEJ5YKvMWzNXp7Zgj/F7KNWN0DlUFQs8DdU3XRu74cgoQm5QcB3jt7eNxj8
M0bMZ2DcAmTl+IOpAHC/gmQjssj6kxovbTrBIVr28EDNLAlO7BVDuafG14b8kDbv
v4dakXEVmiweTDDBJGFYq4toryQV8KZ4xjqwzlG3jEU=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=7344)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
