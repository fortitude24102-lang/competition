//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : memory_test.v
// Version        : 1.6
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2024-01-05 14:09:25
// Abstract       : ---
//
//Copyright (c) 2020-2024 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module memory_test#(
parameter                       AXI_DW = 32,//axi data width
parameter                       AXI_AW = 32,//axi addr width
parameter                       MEM_AW = 32,//axi saddr to (saddr + (2**MEN_AW - 1)) address space;recommend axi addr width 
parameter                       DDR_CLK_PERIOD  = 32'd800_000_000,
parameter                       AXI_CLK_PERIOD  = 32'd100_000_000,
parameter                       DDR_DATA_WIDTH  = 32
)                                                      
(
//Globle Signals
input                           rstn,
input                           clk,
//User input information
input                           mode_en,//0:stop;1:work
input           [1:0]           addr_mode,//00:imode;01:fmode;10:rmode;
input           [1:0]           axi_mode,//01:Write Only; 10:Read Only; 00:Read and Write;
input           [AXI_AW-1:0]    saddr,//start addr
input           [AXI_AW-1:0]    faddr,//fixed addr
input           [1:0]           data_mode,//00:imode;01:fmode;10:rmode;
input           [AXI_DW-1:0]    fdata,//fixed data
input           [2:0]           len_mode,//00:imode;01:fmode;10:rmode;
input           [7:0]           flen,//fixed len
//Master AXI4 Write Bus Interface
output  wire    [7:0]           m_axi_awid,
output  wire    [AXI_AW-1:0]    m_axi_awaddr,
output  wire    [7:0]           m_axi_awlen,
output  wire    [2:0]           m_axi_awsize,
output  wire    [1:0]           m_axi_awburst,
output  wire                    m_axi_awlock,
output  wire    [3:0]           m_axi_awcache,
output  wire    [2:0]           m_axi_awprot,
output  wire                    m_axi_awvalid,
input                           m_axi_awready,
output  wire    [AXI_DW-1:0]    m_axi_wdata,
output  wire    [AXI_DW/8-1:0]  m_axi_wstrb,
output  wire                    m_axi_wlast,
output  wire                    m_axi_wvalid,
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
output  wire                    m_axi_arvalid,
input                           m_axi_arready,
input           [7:0]           m_axi_rid,
input           [AXI_DW-1:0]    m_axi_rdata,
input           [1:0]           m_axi_rresp,
input                           m_axi_rlast,
input                           m_axi_rvalid,
output  wire                    m_axi_rready,
// error informaton interface
output  wire                    error,
output  wire    [15:0]          err_cnt,
output  wire    [AXI_AW-1:0]    err_addr,
output  wire    [7:0]           err_position,
output  wire    [AXI_DW-1:0]    ref_data,
output  wire    [AXI_DW-1:0]    err_data,

//ddrtest efficiency statistic
input           StatiClr  , //(I)Staistics Couter Clear
output  [23:0]  TestTime  , //(O)Test Time      
output  [47:0]  OpTotCyc  , //(O)Total Operate Cycle Counter
output  [47:0]  OpActCyc  , //(O)Actual Operate Cycle Counter
output  [ 9:0]  PcsOpEffic, //(O)Operate Efficiency
output  [ 9:0]  OpEffic   , //(O)Operate Efficiency
output  [ 9:0]  RdOpEffic , //(O)Read Operate Efficiency
output  [ 9:0]  WrOpEffic , //(O)Write Operate Efficiency
output  [15:0]  BandWidth , //(O)BandWidth
output  [9:0]   WrPeriMin , //Write Minimum Period For One Burst
output  [9:0]   WrPeriAvg , //Write Average Period For One Burst
output  [9:0]   WrPeriMax , //Write maximum Period For One Burst
output  [9:0]   RdPeriMin , //Read Minimum Period For One Burst
output  [9:0]   RdPeriAvg , //Read Average Period For One Burst
output  [9:0]   RdPeriMax , //Read maximum Period For One Burst
output          TimeOut    //(O)TimeOut
);

// Prameter Define

// Register Define

// Wire Define
//seq interface
wire    [AXI_AW-1:0]            addr;
wire                            addr_ready;
wire                            o_addr_ready;
wire                            rw_addr_ready;
wire                            addr_valid;
wire    [1:0]                   r_addr_mode;
wire    [1:0]                   r_axi_mode;
wire    [AXI_DW-1:0]            data;
wire                            data_ready;
wire                            o_data_ready;
wire                            rw_data_ready;
wire                            data_valid;
wire    [7:0]                   len;
wire                            len_ready;
wire                            o_len_ready;
wire                            rw_len_ready;
wire                            len_valid;
//fifo empty
wire                            u1_emptyo; 
wire                            u2_emptyo;
wire                            u3_emptyo;
wire                            u4_emptyo;
//prbs interface
wire    [MEM_AW-1:0]            raddr;
wire    [7:0]                   rlen;
wire    [AXI_DW-1:0]            rdata;
//Master AXI4 RW Write Bus Interface
wire    [7:0]                   rw_axi_awid;
wire    [AXI_AW-1:0]            rw_axi_awaddr;
wire    [7:0]                   rw_axi_awlen;
wire    [2:0]                   rw_axi_awsize;
wire    [1:0]                   rw_axi_awburst;
wire                            rw_axi_awlock;
wire    [3:0]                   rw_axi_awcache;
wire    [2:0]                   rw_axi_awprot;
wire                            rw_axi_awvalid;
wire    [AXI_DW-1:0]            rw_axi_wdata;
wire    [AXI_DW/8-1:0]          rw_axi_wstrb;
wire                            rw_axi_wlast;
wire                            rw_axi_wvalid;
wire                            rw_axi_bready;
//Master AXI4 RW Read Bus Interface
wire    [7:0]                   rw_axi_arid;
wire    [AXI_AW-1:0]            rw_axi_araddr;
wire    [7:0]                   rw_axi_arlen;
wire    [2:0]                   rw_axi_arsize;
wire    [1:0]                   rw_axi_arburst;
wire                            rw_axi_arlock;
wire    [3:0]                   rw_axi_arcache;
wire    [2:0]                   rw_axi_arprot;
wire                            rw_axi_arvalid;
wire                            rw_axi_rready;
//Master AXI4 Only Write Bus Interface
wire    [7:0]                   o_axi_awid;
wire    [AXI_AW-1:0]            o_axi_awaddr;
wire    [7:0]                   o_axi_awlen;
wire    [2:0]                   o_axi_awsize;
wire    [1:0]                   o_axi_awburst;
wire                            o_axi_awlock;
wire    [3:0]                   o_axi_awcache;
wire    [2:0]                   o_axi_awprot;
wire                            o_axi_awvalid;
wire    [AXI_DW-1:0]            o_axi_wdata;
wire    [AXI_DW/8-1:0]          o_axi_wstrb;
wire                            o_axi_wlast;
wire                            o_axi_wvalid;
wire                            o_axi_bready;
//Master AXI4 Only Read Bus Interface
wire    [7:0]                   o_axi_arid;
wire    [AXI_AW-1:0]            o_axi_araddr;
wire    [7:0]                   o_axi_arlen;
wire    [2:0]                   o_axi_arsize;
wire    [1:0]                   o_axi_arburst;
wire                            o_axi_arlock;
wire    [3:0]                   o_axi_arcache;
wire    [2:0]                   o_axi_arprot;
wire                            o_axi_arvalid;
wire                            o_axi_rready;

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
Ra3HJU9wIlCZf1YLKtAPi6n4L8xEQXhVWAKWvEZESHWGkRTQxsLLeKU2eWnst/o+
uQPOn5y72Np9ZE0kON4B6OnlV1WcIi3QfIxRE7TOSBVE034H0irQYjqwZo61HbBn
+5320xp1VrkxWNXAgfRd1hzfiisOAG0OnJwpfjl4hRwcqS4aBi7P7qPcEzUo3xGY
h2WpP7P1o0tmOm1W361DIC48xWCMqM3Qazx8anix75q72DUYsQbMk3zVPkrf7Sgu
6Us/FVDBJ+h4w0thF2R+n2ZQXi0kcwPUhaQVPYRTopsTQYLx4JJRWl9rp9DJrCC3
nSli8HdzDqPPIp4f8TJMKQ==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
kJvJF+ps55Y/oWFzYqyjqYOsM2dJLlkqU8hRmorlB+qMh59OHn2p3fT176TojAmt
nbd15cCLPN469dN2a0RpqZY4OGHqKiweI1qVWxQe8h8otVScf4wshdRssO+oL5es
ZMLF1FTZhxE5OfLAgZCa7gKfqrjSo/ydMXpVjxiABIk=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=18640)
`pragma protect data_block
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
hSd8pK8Tk8wm4C7AjUvujA==
`pragma protect end_protected
endmodule
