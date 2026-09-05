//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : ui_wrapper.v
// Version        : 1.1
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

`timescale 1 ps / 1 ps

module local_bus_ctl #(
parameter                       TCQ        = 100,
parameter                       CK_RATIO   = 2, 
parameter                       USER_DW    = 256,
parameter                       USER_MW    = 32,
parameter                       BANK_WIDTH = 3,
parameter                       COL_WIDTH  = 12,
parameter                       CWL        = 5,
parameter                       BUF_AW     = 5,
parameter                       RANKS      = 4,
parameter                       RANK_WIDTH = 2,
parameter                       ROW_WIDTH  = 16,
parameter                       ADDR_WIDTH = RANK_WIDTH + BANK_WIDTH + ROW_WIDTH + COL_WIDTH,
parameter                       MEM_ADDR_ORDER = "BANK_ROW_COLUMN"
)
(

input                           clk, 
input                           rst,   
input                           mc_user_en,  
input           [2:0]           mc_user_cmd,
input           [ADDR_WIDTH-1:0]mc_user_addr, 
output                          mc_user_ready, 

input                           mc_user_wren,   
input           [USER_DW-1:0]   mc_user_wdata,
input           [USER_MW-1:0]   mc_user_mask,
input                           mc_user_end,                                 
output                          mc_user_wrdy,  
   
output reg      [USER_DW-1:0]   mc_user_rd_data,      
output reg                      mc_user_rd_end,       
output reg                      mc_user_rd_valid,      

input           [BUF_AW-1:0]    wr_data_addr, 
input                           wr_data_en,             
input                           wr_data_offset,           
output reg      [USER_DW-1:0]   wr_data,          
output reg      [USER_MW-1:0]   wr_data_mask,     
input           [USER_DW-1:0]   rd_data,           
input           [BUF_AW-1:0]    rd_data_addr, 
input                           rd_data_en,             
input                           rd_data_end,            
input                           rd_data_offset,  

output          [BANK_WIDTH-1:0]mc_bank,                 
output          [2:0]           mc_cmd,                    
output          [COL_WIDTH-1:0] mc_col,                   
output          [BUF_AW-1:0]    mc_data_buf_addr,

output          [RANK_WIDTH-1:0]mc_rank,                           
output          [ROW_WIDTH-1:0] mc_row,                                   
output                          mc_use_addr,  
input                           accept_ns             

  );
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
IgVEPrmdJKXXIX6Vk6rimC24JvYj3vW4bYZ9BAwrYEzoE36TMPuVPrSPaOqAyhxV
2wS4HpJrJpTpcO4+B+zhfeUzYE4I/vCsb5FgUBgYMJiuzLOvdjvXY5KU1fLpTX/V
C8+qFdjKXKlPG2G1W0dr6CTvsRjJ4I5XrCUU2Y7FDPYFgU6WZStLk9tH/yP6AOf0
kFy5k8CWQwYxDWyuQHqkz5GHY8/Cj7nHz3hcqj+iwx4WPGNkndB9FD0pCrtQ6kaA
so14KXABH5khKKMWR+Njm7wCbeKXZjq9TNpdpJKfflHTKek2M3axUMtDYj+uBQ9A
Z+w5qoAlq5AK6z4+ecvGxA==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
JQUGWlKj9TbPBnPcHicVXd1oJiD+ANzGqLLz6O+d+XS03aPwzyhabB0CwYcyc3jk
79fWvTug7nhB68WX2EFTjYWG69YT5fuH4h/H9bVjqUTwvyci/R05zBn7gOb4gwXU
WBkp21IIp6dTHijAcU8fkSyRHaZNN4/AWeQK/RN5tv0=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=8736)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
