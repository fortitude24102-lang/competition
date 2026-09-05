//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : axi4_onlym_gen.v
// Version        : 1.4
// Date Created   : 2023-03-15 10:37:59
// Last Modified  : 2023-05-30 15:36:01
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module axi4_onlym_gen#(
parameter                       AXI_DW = 32,
parameter                       AXI_AW = 32
)
(
//Globle Signals
input                           rstn,
input                           clk,
input           [1:0]           r_axi_mode,//01b:Write Only; 10b:Read Only;
input           [AXI_AW-1:0]    addr,
input           [7:0]           len,
input           [AXI_DW-1:0]    data,
input                           addr_valid,
//gen ready
output  wire                    addr_ready,
output  wire                    len_ready,
output  wire                    data_ready,
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
output  wire                    m_axi_bready,
//Master AXI4 Read Bus Interface
output  wire    [7:0]           m_axi_arid,
output  wire    [AXI_AW-1:0]    m_axi_araddr,
output  wire    [7:0]           m_axi_arlen,
output  wire    [2:0]           m_axi_arsize,
output  wire    [1:0]           m_axi_arburst,
output  wire                    m_axi_arlock,
output  wire    [3:0]           m_axi_arcache,
output  wire    [2:0]           m_axi_arprot,
output  reg                     m_axi_arvalid,
input                           m_axi_arready,
input           [7:0]           m_axi_rid,
input           [AXI_DW-1:0]    m_axi_rdata,
input           [1:0]           m_axi_rresp,
input                           m_axi_rlast,
input                           m_axi_rvalid,
output  wire                    m_axi_rready
);

// Prameter Define
parameter AXSIZE = AXI_DW/8;
parameter AXSIZE_WTH = $clog2(AXSIZE);

// Register Define
reg     [7:0]                   burst_cnt;
reg                             burst_wait;
reg                             waddr_wait;
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
jeYs3KsH+j8MTb8Uq25fhyHQ0tdBoZ1MC6OwgBA1pqBHx/ofW4RpdSru4cXT/Wrn
n5YJMzSmNO/vxUGS881bk0JUgu+Y/tBEp9h96wEQVYMMduC82u1FbLk7ELcOrh/x
Xz2tgXHcLfQESiA2OFwikya7un5QYPKVqB9UfJRNjgo/CVW4MVFWY4ewHRWm+Sg9
JVM9r/Dr3Z71xwU9NFG6O9y1Z+8imNnt7W6EFm2dJ+Vl8XVxi0qHx87eoFJyRh9K
jHjluciC356wazm0E3hvNYw9HMlciUJwKpl62+5530EU39rP10H9DI62+yh3fo0C
4ee0+k52c8q+vG5PAIrfDg==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
FnNclI3xAloOY9GKHhHVA1Zsnp3iEbAoPEgBC1IKaXCzmp+gksYYwllPD9LEuOiY
fg5gyOkmKmiWgc9oRNvtzboUSo2HTbNa7OS1GPE/po0jeR9156oIHMFXwStk3JvQ
8d/EPkvaIrSTkbklnphe/XL44FHpRy7hef7cXuDQRfk=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=4576)
`pragma protect data_block
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
no6M+0/z9ENXlOO9LFD34g==
`pragma protect end_protected
endmodule
