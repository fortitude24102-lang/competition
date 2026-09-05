//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : lb2_axi_clk.v
// Version        : 1.1
// Date Created   : 2023-04-23 10:37:59
// Last Modified  : 2023-04-23 10:37:59
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/


module lb2_axi_clk #(
parameter                       USER_DW    = 256,
parameter                       USER_MW    = 32,
parameter                       BANK_WIDTH = 3,
parameter                       COL_WIDTH  = 12,
parameter                       RANK_WIDTH = 2,
parameter                       ROW_WIDTH  = 16,
parameter                       ADDR_WIDTH = RANK_WIDTH + BANK_WIDTH + ROW_WIDTH + COL_WIDTH
)
(
input                           axi_clk, 
input                           core_clk, 
input                           rstn,   
input                           axi_rstn,   
input                           axi_user_en,  
input           [2:0]           axi_user_cmd,
input           [ADDR_WIDTH-1:0]axi_user_addr, 
output                          axi_user_ready, 

input                           axi_user_wren,   
input           [USER_DW-1:0]   axi_user_wdata,
input           [USER_MW-1:0]   axi_user_mask,
input                           axi_user_end,                                 
output                          axi_user_wrdy,  
   
output          [USER_DW-1:0]   axi_user_rd_data,      
output                          axi_user_rd_end,       
output                          axi_user_rd_valid, 

//----------------local bus----------------//
output                          lb_user_en,  
output          [2:0]           lb_user_cmd,
output          [ADDR_WIDTH-1:0]lb_user_addr, 
input                           lb_user_ready, 

output                          lb_user_wren,   
output          [USER_DW-1:0]   lb_user_wdata,
output          [USER_MW-1:0]   lb_user_mask,
output                          lb_user_end,                                 
input                           lb_user_wrdy,  
   
input           [USER_DW-1:0]   lb_user_rd_data,      
input                           lb_user_rd_end,       
input                           lb_user_rd_valid

);
//Parameter Define

//Register Define


//Wire Define
wire                            u1_wrreq;
wire    [ADDR_WIDTH+2:0]        u1_data;
wire                            u1_almfull;
wire                            u1_full;
wire                            u1_progfull;
wire                            u1_empty;
wire                            u1_rdreq;
wire    [ADDR_WIDTH+2:0]        u1_q;

wire                            u2_wrreq;
wire    [USER_DW+USER_MW:0]     u2_data;
wire    [USER_DW+USER_MW:0]     u2_q;
wire                            u2_almfull;
wire                            u2_full;
wire                            u2_empty;
wire                            u2_rdreq;

wire                            u3_wrreq;
wire    [USER_DW:0]             u3_data;
wire    [USER_DW:0]             u3_q;
wire                            u3_almfull;
wire                            u3_full;
wire                            u3_empty;
wire                            u3_rdreq;
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
KyXhRyK6T50HjAqlwtCc/ljNUzeni+ABRq4LmW3SnDaiEmurNpYO7KMRbPxdkM9I
IyWSp23XI1DR6gay6+L95liXwRvh1AdHIFSAF82smz8OcE/C3PzEeJsrMwmG8lMh
yHed1Tqctm8GSzYGCuk2hSkXGiXdcmaZQSG0M437c+U0NtOKeB8iLO8Iebtn46Ge
p7A1wwysitf3wjGa5vLC4vJ3dcMb7rIwJQbVbzziiBplxJE91tHC0PeF5cteo9S3
u3VjzcYktMKgvgKXzU9hRoB3+ozIQgoqznNctmgHmptKtJRGLgECrn4cYMUmMtXA
iUynoDvCviArmq5G5iFtWw==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
n8L/g0RuflxUZg87YcYLGlWuAhj9J+ZD4iDI2Ynqu84QOCg+T+ytlw1C7qeF2Ufb
tiFKKCoe7WK7xlXvjG3qU+Ue1QhJWYvQnxveERY2P/LWZMpdVHv0KsRKlY85yR2P
ysGoFijIRNOav8OE3pEKvMRgQ6qgTEqeF+lw82/lurs=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=8032)
`pragma protect data_block
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
S7o6vY+tgJ5Ez2Q/kKofzw==
`pragma protect end_protected
endmodule



