//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : len_gen.v
// Version        : 1.4
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2023-05-30 09:34:40
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module len_gen (
//Globle Signals
input                           rstn,
input                           clk,
//User input information
input                           mode_en,
input           [2:0]           len_mode,
input           [7:0]           flen,
//prbs
input           [7:0]           rlen,
//len interface
output  reg     [7:0]           len,
input                           len_ready,
output  reg                     len_valid,
output  reg     [2:0]           r_len_mode,
output  reg     [8:0]           rule_len
);
// Parameter Define 
parameter State_idle  = 4'd0;
parameter State_mode  = 4'd1;
parameter State_rmode = 4'd2;
parameter State_fmode = 4'd3;
parameter State_imode = 4'd4;
parameter State_rule_rmode = 4'd5;
parameter State_rule_imode = 4'd6;
parameter State_nmode = 4'd7;
parameter State_trs   = 4'd8;

// Register Define
reg     [3:0]                   cur_state;
reg     [3:0]                   next_state;
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
fakfJ9ilB6hmsp26GCp2akuY2DLzdXZEnuu2zgb+YeRo4zfsrbyEXGD0FV3Z7iWI
4Hj+ZNf2uISWICw9SgVEMgXLndABN/Z90WeOqswHBQ3gSi8644Tz2K1GsG65LDNc
WvHG7CaEjRbh5qT/2x7wLvKokf8R7c+tlvxIgrWDcWPGEXo6ff46cwok3F6fmoN8
uY5sP/8HpxWaTuBEPBy98fnGyvizQxcm5IyBpt4e+4F/i1IXlY0XOgaztIkFwF36
JyrhSEVVd9T/se4hQh8llV7IhjqM6SjEsbWOQ9Ny3Zod5GCEDqdkZbyZd5rGkORx
tVmpk35uCn56kF0Tgjs4TQ==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
MiTcPNX4EQe7l2Y6xVrfBENXao01aAsrTw6jb+a0DttAgv1U6hdgd/ZcfYyicWPc
8/Mag4jwIVFjpY3abIv71EFimyNyfYbJTU6UpY+O85w7NQKMglJNZAk/HfusES+a
1Oq/ugNDdGeYzcttIR4pG4OQ9cZs5QtyO3Nq++Hj82A=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=3952)
`pragma protect data_block
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
hYeIt8f4buf4BC7SZeP1KA==
`pragma protect end_protected
endmodule
