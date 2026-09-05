//***************************************************************/
//   ______   _   _   _                  _            _
//  |  ____| | | (_) | |                | |          | |
//  | |__    | |  _  | |_    ___   ___  | |_    ___  | | __
//  |  __|   | | | | | __|  / _ \ / __| | __|  / _ \ | |/ /
//  | |____  | | | | | |_  |  __/ \__ \ | |_  |  __/ |   <  
//  |______| |_| |_|  \__|  \___| |___/  \__|  \___| |_|\_\
//
// Moudel Name    : check.v
// Version        : 1.4
// Date Created   : 2023-03-06 10:37:59
// Last Modified  : 2023-09-18 15:09:38
// Abstract       : ---
//
//Copyright (c) 2020-2023 Elitestek,Inc. All Rights Reserved.
//
//***************************************************************/
//Modification History
//1.initial
//***************************************************************/
`timescale 1 ns / 1 ns
module check#(
parameter                       AXI_DW = 32,
parameter                       AXI_AW = 32    
)
(
//Globle Signals
input                           rstn,
input                           clk,
//axi word mode
input           [1:0]           r_axi_mode,
//gen valid
input                           addr_valid,
//data fifo rd interface
output  wire                    u1_rdreq,
input           [AXI_DW-1:0]    u1_q,
input                           u1_empty,
//caddr fifo  wr interface
input           [AXI_AW-1:0]    u3_data, //connect u2_q[AXI_AW+7:8]
input                           u3_wrreq,
output  wire                    u3_empty,
//read end interface
output  wire                    read_end,
//ERR information interface
output  reg                     error,
output  reg     [15:0]          err_cnt,
output  reg     [AXI_AW-1:0]    err_addr,
output  reg     [7:0]           err_position,
output  reg     [AXI_DW-1:0]    ref_data,
output  reg     [AXI_DW-1:0]    err_data,
//AXI4 read data interface
input           [7:0]           m_axi_rid,
input           [AXI_DW-1:0]    m_axi_rdata,
input           [1:0]           m_axi_rresp,
input                           m_axi_rlast,
input                           m_axi_rvalid,
output  wire                    m_axi_rready
);
// Prameter Define
parameter AXSIZE     = AXI_DW/8;
parameter AXSIZE_WTH = $clog2(AXSIZE);
// Register Define
reg     [7:0]                   burst_cnt;

reg     [AXI_AW-1:0]            err_addr_ff;
reg     [7:0]                   err_position_ff;
reg     [AXI_DW-1:0]            ref_data_ff;
reg     [AXI_DW-1:0]            err_data_ff;

reg     [AXI_AW-1:0]            err_addr_ff1;
reg     [7:0]                   err_position_ff1;
reg     [AXI_DW-1:0]            ref_data_ff1;
reg     [AXI_DW-1:0]            err_data_ff1;

reg                             err_ctrl;
reg     [AXSIZE-1:0]            data_check;

// Wire Define
//caddr fifo rd interface
wire                            u3_rdreq;
wire    [AXI_AW-1:0]            u3_q;

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
Y4bECr6QDu0FKhF095w9s1M/fHyhR+FD3bpagv6e6+TETTyiY3r+d08SGcrToyUf
uYI4r12JTqXB3fuDBMiXS0kgM9w4ZS3Lg1ZlZxmu7DQqDWS+SUpUiCQGFLHCeBZX
kaLlg83TCA0nFom48hHvkA5khL1P5C6XFlA1NL97t6lRxUmtE0hcTNJaqq4Rpdlu
YZZf610Dr63ltQaTpYVXxb+rwKIc8eIEbV76c4pr912Lu7sC7wOXZRZmgIPG9P4X
MZG9mvAdN64BoUhREMhoZb3GAabznOS4QgZWzP7oy5x6VJY5WWOT2/PTgGyJcG1c
yD6tkAabGUZux8PMfqLvyw==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
Na2P7wUi4XKyLE5uIfMTcQuMYVGAIfwj0m8mUu56LpJup03fSnrUeVGVD2tgbZp4
HMz+Yfle22QlRPHXgjFWNGhZE5bDRTCShKgQD9PI68HN1PawHFlceCyIl7kSA/4W
EhNFdeNQ8y2BIUq4DqJcrufClal4l8iPNA0oEWaxDWU=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=7232)
`pragma protect data_block
TSin00yMt9E8iqeg54AS7yAEV9v0q6jJzAPLQHUmpNA3axUspBkK8NH0mUCmjetS
zQgC9+1deennDt+swgwBtFEGrVghA1ZrzjxFU0Et0KgTkMO0aPr3K70wb3h/Lzzm
ArY+mB7HDy0SbsdaPAiCNqddg+h9WFIihCC4EK45uF/nKF+c4d/MJ3rLrMRru1Cj
5F2WaAfHSSSjFaMFcqcqfz1DufuUJfhRJxepDkncRLjgP37bmb2fNswoSvZ+MExn
R2UYMetG+2Hh5T6zT8HhYNwqE/NwJEdH1Gl9mpmEJiV+PXusdvlpWNFldppY8D6F
rOnpY7Puzyf4k3IUCngqqLyzdfydHkQqoyxkDhYnCnpJAzxeXp4O5A1IZqorVgOv
GvCV12VUOZlyamkLYHWsPQ0RuSpOLroIMbh+vrhA3sJvwnCXKpNLfjPVszUCoo9c
ZXyzv0KSQONjKWQFCZhJa2JssT2q6/cfROQnnyflKXITFWCJ6fE0RN8wedk86w2t
ojvbfjclyMIfnu1Bz2c1Gbk8U+D8EufvVl5ppa71GZZa/10cIBPbKt+Pk923wLnu
pdcKKkLrQwLnaU2jGrDArKQOm676wTcFmaHKt3ecQF+UkO4ri06Xg/M5DuXB/8Wa
ahnCYIN4+/51wEJoPQaZl+NOnUSjjapYIWcN4DLe70DVcNebbFKctsiV0TIzU5CV
FviyZGsKJsiq2sT5Ds+O9oziV9LcI5o7Q/RT/qAHufBQLGyuCu5EI2WTtTOIiwMY
+2zzKCUENBLANHiTXXpR0xhHnHBhRigXhkn43Rq5DN4PMBtUfqG0jIa+pRvpfkgD
JOQAQGsvzDuUd3sGRkzMwqja5/R2ZYK4Qan+di5N4UlN1ZKyD3FAVKhoO8it97aq
ymPwcFLSJBpajNhjqtoT7Wx8l4mBZ8YZ5DGqwn2V8Kx7St2vlC5F7Lk3RBuHbgQI
uaWsWE5dalQrOW/iMS3kY4YpS7HiTNnl21lT0y+4SUNbzbKwovQveRjsa7CDxMF6
7Fyq2sKYwi2+s52WrQiQuNjaDCRiDCU/W3yQE7Ujr+TWPpwsIMFcyWG3diPd7vAj
LIy01lZdOGnqOkY4VCaaIFT1UFPcVTsQQgjsdL93OKBtzBYjnxc18N/OSMZOHMxL
DqHoNVAPbysb4TJi2v6UPy7dqe9jSZcrndK2TOz7M+/EUw2e7wyP+3SqFxB3CLTm
3b7HwU19Xc+3mFf5tmkfD2enduK5aD6NnwJ7cln3wpOAk8YpXX2NEdf7CPYSnXld
CGG2xst8mljJYCvcU5Mp1wyaWGRRnbDQmYzwhGEhzOgUvt1mX4Zn7pXzAgFIw3Ve
ebN/8HwZnyVw93AwBMclKkaMxVUNoER/dy+U1CqMxi7DImEuXPN5vb6ce3YHb9uZ
S0BGJbd2DqVf1qZhln9R4gfvnnY6ZwnGNcFIwzgs8u3xboFvlt3tWpM9z/bQ3vY0
niFBQkxitxI+0N1TdnU0ljzsSSHaQL9K87rhDGnqFBil0Syr/eNib3s9DOagfFP/
bHf14ttqEQaGqMlTUgs2+kM/GGs5JWsunv1BpJv4uKl66+wYFyihwHxfqMe+4ib6
JBEeENZB0vEV+eI2azchPboP60szZ3ew/0sBrkErTUhbwIqo6Ugm+ferFnL8HzUh
v/O+0XzrkVtR0YG76LhU7NXMj7S5QUD2be290+PBx8PS7dCIGpR9MrzQfP7I92Oa
O6lM+EAyrFwbDfPtdE+rywm78memyvWzxJejYvz4jS4LBorP8GX5cEXdhEabcucI
I3KwuW+ZBRo77XZBmlH599X5hTfUJ2nEKqDfdOqPN1g3SqNj46g2tYZy3b8wADMR
w15gPjJJls9BgwemoVQwrJ2K4OHiZ03KYhRE28lxpZrg0gPcgvSm/j04OUFMNQWV
NEavNu0MceT2Eg15vbpuc6QcNqhTYUKmKnjwYYZJ2w4Yt7HIqaeX8l/gvm2X7529
seTMeoxh7Scl0aS2dxg7jgKUToZy3grDF7D+JgbEhK/y1zBf5zBq4Xpn3mXyH+y4
TiMghk6AC1miEHuQ+Of9xu+64JyyVJa+r9fNPMCwZvrRblju8c0RCNWiwX35UIPQ
NEr0SVwERuDANG4XnL7kUGVYrPKzVy/I0RHAiagvRVoUqwh6rTTKAt7DTeqR/Mnc
Dbn9JmL18ShZaL5Dcskk+Koqvip97n8/+Jo9JZR/H+7mmLR+6aATUef8BFvXPXeu
vOQi6FP8Rduh+qXKPtZnyf6GjiMb+t7B8GJfosjj9mSxKhN1k85nprTTuhtJnW5J
cr5fxWnsZhTd1jwe0lg2YxXHY5o2B+FW7I9v76CgXlPNDEVQf+sX7d/6ohIzti8W
2uUMLVyhOx2lseeSqyn/RIGWbncDcRQAQ3+Lbo96FFkc1fiBV4PSRb3d1uvZxWh6
l7VBzq9aCXqM9cnJqb4py//U4Zf8BbJkbnJxdyVcdI9Wdj3emRKCXD/0LC+KNazX
a3TzMV7m1V3llsr1i1yYJ1SFocGg3GYZL9oNYRHYSfB/o2wXsPo6NTbUtJEQCvsb
VFR29MgA8X9ygiLgAHgONlTWhpKjAXCw9WNwSVRq8vgh6zVL9rlx84fA3I/dUQV4
bXH9FOgKwe8Z14j1IxMPLBhvXHuoiD5ogKBYXvt4whQ4TmvxU+dyYaW1N1gifVTi
4GG+N+y7XWMedzcrE9moMba4f8WU9j9jdgxFqNeLyX3Br1Vrs0GbvqLU9w5ldsjM
QgzlmpVaJMl4qlQlOyhN8tuW/e9QbKm6YuPGWlqQz29cv7mc/aBWgu6zAmALsS46
YRcKufMfEzY1ne8U58PWp6o9y4lHalEaQY0+sErL8Tgt6AeFN1yzm3C0woCH8/ow
1pHFkgArrfDXjZk99HcAhE8TXL+NEtOuYLrIlU99zUVWzqyG1WKoi03DTUxA8OJj
5gZoY2r5LB2mp+A21ROhuXdc6el1IOUTv5cJvIZiCRFMn1+LTWlqsvRqrjK2I3By
zdtOGBjGwDSFI1O+Qe9zbfc0tBEr7xon/7YA1aHcV/oat4QTdSxpLZZvLfm+r2AD
Jqv9C4eTPM/ksRBSYhfwc58Y0DBE87NEH/8FKAIdRa2X9KZpXeK+7b026IvKBgjF
2tYiTeG8HhgMPq+UY1lpBpIGlOCJq/hMQwF9ujKns/vU5V8tRs8ReEqUQs5XsDWb
+P0dmrlSoGLkSrmAMgHNRESBCSGo8rX5FO3pOsB4vcZ/v12fGNNpa+W4ZMy3dk9F
Me+t0o9jyuEHdkhjUL9QuyS9qVGgmwjdkw02EUU1694EBW6LMDJxolRIsUHHjAlz
cQzswH571letKBZCL7nxrM9QrFAQSTK0XqLWfqSSVmkahAxo7mngXCx4niEkVYrX
fhPMDEzj41yiFQXemR2CWtCxq2iFqu26EEFz5Rxf+Pql2dcZ9+cBLmNh0/2mc92b
DpvLzbHZQB/wgJsLXDfvgCBMsqTnJgqABH66GMhnovNgbQLJLlldpKA6endDoGDx
m8tDnn5dXFQf4wpZgShvZ1eV7PQw220RHeSDqNvk2VEN8dET62iVjncALmgQbd18
l2o560SXlzEfb/B9miqYey1Hn81QmQ4vKTO4puz3nRGtvNVSc6V6hDrv4z4stzZ1
6WA2jKRwAUi2P8hxUkTzcgxIQ6l1Jkx2O3qEEkqptxwvT2EAwv3pTL9kquIE3c1F
GEDaZVJ0uhQSMofc7rFrtqIHTsjQDN9pT+OKeEX/4GGKuSlEz4CwDqDx/nz5afeX
ZIzRq+i0kkAqUVXbwtWJpAQVR7iHNS4NT+rAZANar2ZuZhvU9+3oCuS5bNAJ/e0S
7qtjqmuOWtzEfyRGdEFHC7MtzzCrpRWtaV8xj2oUEKVwOKfrKDmRcwM3JtzuEiGT
wsa4epn23rt8bAE9RtLm9GKXKRqPIEftF5sNQQYoNv3xkPda1jwOsygLrXkmcvGs
zKU0+NaQH4lK9ZHRREc4En5FF4UGbGEQsdhBJNrqCcUQYZi2WR0boj67878sZvfM
6402HI7T9B3PYuCuxrll90CqWlDrauf8NnSha3A3CyvRwdjXYgc/zj2Yw2mRNJnU
cUuzKTKFaqbiVcUSStsey2zrXUvPg0gHZUt02B/adiCb7jpZhmOe8b6GEOD3q9sL
eNmYGDOI5iLyj6+3Oqj2MB21Un5QhElplofgD1mVCxfc7Rei+TlpP4NFHzU3Bksm
eDB33n5ReQcnsJtzEuxBeVNIaZV8oyI/vWMuj4AGtnDe9c3/jiLkiySw+s4ZvsLF
ydYKPbQwOWxaPvHf4Z4liRFqvbu0XmT+G37hjCwQjaDMUKYhUOqw41P1bQAmy/U5
+EqAHzqpszO2fZ/TzpIN++hYzPfnrP/jhCbk2mUrVEyTEQKDt+vaYVaxeJ5tmkvy
c9ddNyorUzXqa2nqHCDcIc9iQpVKn6wH513OonoA+zpNRTbbGvNSrm4b5LtswM5c
OprLmqfJ75sdBceR+L9KsXTP/+MnFezig1KpSWlDAnlRMxkjzHlHQKPHxq1NwwSs
oP+RkSD4uR5SHlgamZiWwuts+hJEGCKuYQtnsEbP+JIU7Wj8wiYtvSbkjv0nk/jF
O2BxyCg+sowy7jrQW5Ihz32Q/iL0aMWAL43fq0gELFfkR6zyyBm0Th1e5cEi/S4B
/YBh3EprHfnmIAeiKPGIHjw41kwMOq8b9k1M/WGcyorwixGbd3Chm8B3x+RBInJ1
Cbon3BefIYI3OqHRTTt8SaPFI4SJJlMRtUo1l0Spheo0WrQqA9Bg3VYgCufHzNSq
7745Q9a7FbDzJZ4DySc6JvafHCs+7twET2oCDR2tFjYNnrMdLTsGtdNNYLSRizTH
NEMvtt8cuhekNYMzZF4s0VIN9NDIsp+sMyGBsRe3hpWejAkK2mcpjjawnYMgF6Ox
hXblgnSOpJa8H39vkkfg9NBFRJBCilneLGOULko+2AtdtG/r1O6/APBYlO4N+1US
18YbYAVjYk5xD2M69O3vILqqleXUgpJQleef4Dwfx354o/C4nqROPBWgn+HoFH05
GNRraBkCJ6cd1lIdyMzpq9hufP5SZf1UmOBTFlEUKBKNihFuh8kTjIaZ6wFL6uXH
ucYYztzq0TUgO4D/TErglJVV1MLZF1x3Wi8KfG6LfnTd0Vp28W901Mm/EsouhYBq
vF+ZFFzke48ik3n8Gpxb6bYFNQIKESxCZWPQWbMcDpZbD4E4WYpUvWUx1wJI1uA6
tkljDOz0vmhlv07+nVzAYO5jonUAxn06xR/MfTf4JnfsZKsZDyNyQtTzL/LTVp+R
qHD+PTWKN6NLobZO9fF7WbH3d7ZVxxraz4j1HleV+wtt1KZ1RHW5UwWaNpkuZABW
yC6mP6BIJvnAV53JLfE6NyRcK6cVJTrXshW1w2ktDL6PBin1qrouNJhvk1KeIuZo
9HXA3BXa8zGlTFKXtGFnoPknjZSfm161sld6zas6NgT+EaMph3nRcuoKMYcINjXs
jkinouclgI9wLyNcbcEJokaiY/cB0+w3bEGV3r4oYGgnnNh+grC41mZhz1kyXd5+
gPhSQWBPBZfs+aYj3QWts+odVivlhgJ2t4NtnnolTzjp24WrqE6oPCGKWeScY1vn
VNtuIKamwDvmHytWm7VTOqMxPm2sJVi1f15FggSZiVOKerJCoCiisMDJ2SqQpo1M
leGszGaso84nqL7Y1kzrtFhBedhYLyoC6k9rYR5D7zGXkNexLFJkwlZ3OTOM5TR0
1vEeyhNx++r0Vmm3dhUlp41LPInT6yBFUzx/SeUWeNg6keOT7yYZSJnQJ0bbAhRc
QWuAQswStEVAaQqSe1sgeWLTHjfCqQg65zClu7Jv3L9N4+d9ecpsUAJOMU6fpWgU
woFTtZN1LPALUl01O6Ny7zE+nuzL4I/GWch00jRzJdaFBBPM+p+5qZf5Gw+XfVK5
6zWeaQr4MWIH+dh7k/cF3sULKUdjB+AFuD5TCyJVufTFj7r0B10vXSxFYflLDKAm
gYkXbd8blf8VyErFNzaWEh5sU822WfUA1JAjh6IrCfE5pKwzp9yuXwXeXHuEPt1D
l5vrcg8z6xSVPksYUo19cyhqLmh46NyhBlBMBP5H/O9DfMOJ5uFgpqyTet866Ia/
4keZnLnUHxYwmm3sjmWBlf1iRhg4hfPCHCjDs/UZOdPG2U7zP9HA1Ri4y+5pePPt
Cx4NsTXpfxxjmx8FfMPI3p42a7uVge5BValJWsTDXpc6U0BMouRvUmNt0A+wcKWc
2qcb+HGMfN+wgWfHSaoc6ZTLArJXEoZkeWzb+BjMnvZxr5TeCyH44bjbfwz8v07I
alUqF9NeROxnGfgNqjK6qS1bAKWyA0CUC33ct4NfWWPAH1Sni/YoA81nmA1/gXZ7
PPl2G6mcG6+3D6bXfdw+x4jiv42SQra96LNHbkvVaHelKUFWbrFjBcBieX2MfsKH
SHyM5blRiwW7J+dEBHiTnX7OYeJLUe7pgry8uZhePo6M0Td+aMNhkbrSECcuPFLq
s+vLptv4dKWh2/n8ELCYmaXImEANV3IoqLkAzDcCYZ1giWMJWK7bjZKTCqyxlVL8
81mJcHFRNOrm+WxZbExxxTYaqukMY1MJ7+Y/aG4u1euGBxlDR9UV2HMZEi7aYBDm
+mFwJb4daKRB6/FMdQ0DJyYngAGckg1iL9cbfpatNsJBXaaLqTSJ0dZd8WrO7kTI
XQbRkLQryDOuKHAAlIUr07R6ts0WECVPtr0zzh6tMqEmDFzNKpVMaaJiUfmfjbrB
BAVe8by70S5K2AAlEufBZyh9Ej/3isaU8bBExglTm0dXzQRv/SRMOjn0co7mg/uL
s+k2qvc9j1MCbzTu4DL8bTQAwbonEBOsK5ct3RiNY7IUtzd1UckbAGy20mQuusgG
HVp7xHTIqew51uleEJNBjmeJmCPWyeqXvP1aco9un7sP49XZiu8xE+0rfg31838/
8Sse6jpe1tHIq7I+dojAipuilE50f3RqN70sxMyiMkhD2Ai4a0yMBYQ5RA7zTlch
R3S/v+zo+oR2E1Gx9T+SXaZRgrL2EE4jA7l7Ubr21esZPEthOPIyAl5ZyX4ACN26
1aeQK++CKYKiGD/kJ20L88qzFAjapAuFzOtJg8E4k8MjCNJQeEDh+JcrPN7JwbA/
v/e/7BidiM0fuqNkvbMEX7Zsm9Bs4El6BWJMuF6VhEc0guJwyJmXuuo900d4FItl
nB0E1+8ZSQCPaXCdTeWiGiQwnGW+PbaS3RT/UlAdFRJj7JvPd04hsIQJzDss2MNM
EMTC1qNVdBD1jVW7foZ7YiAFCoUAKpm0SRQyRlTA2fsN4Y2IrTKYqm8DobeeUwTo
QsCiRquJIvkIvZ+D4CWH90SkZ/k38nBi8xhp9ONMsR+qunydrxVNpbOw8TvMH7x+
BDTvSi3nM/GAZzGpqdZuOFj9ddw6PfuyMahAEfUruqCgydRBOKtad4r3UxYvC+Lr
NAtcepX/FL4VyaLk5mokO5X90dt/AsjfhF83npg4ePOQY21j0mK4bsuDxMaEo0df
AXC/6k9CgWwHTiypqtiiMD/vfZvICknzGw8s5zsTtHB3ga1WdEA6mW6d5xL1iV3S
QBjnSFUAPLPf92o4fB+VsQnkoa2hO9Df9J/2Gx50QEHQhUmZ5nb1XKTIWvj+aUmf
WL8KpZGkEjn0/ApAjul2oHml7sxAWimENe3quzwA3JmdR98fX4od9IykdBSmmlpn
fLwm8OiFtMRaygF3Gwvxu/ZZnUeU+dgznRO+OtSIAOaK/rUmn5Nu/Pkj5WXBE1s7
B/HKH4ZTKGJfCo8t+cmFcGpwG3EO8pb0SdNRuk3hwM+iKBb+z6fw5f1OmIeMLjvV
59qPMVmnjwph6KToD7GqqzMJ3hOGvWPKW+qWGvoDa/xou6djXiNo5YB3dOzoyHEU
mddL2Dbk2aXxBQhpGcG6VONRq4f7Rbw5BxCmKewVcF9I/wI+Fqrro+ZWEKVisOoo
cAXClvDkbTII7+sy213pC9DApBznDtng5XFHOJUTS1rhzbSP182WDMiRuE+PDvI5
f6S5aidhz/xMEKY3ZjjGGR2LLShjjo1+wrlGI9uNxsxPWvmbtcpcrkG5Fxw420Tv
+lTx78LSTPc8hMxXcgMU5Z3Nq+wr9DdyP1Gl5FBNCY4Yqac8sLFdF3PsaHvMuy/z
xJC1Lgc5cJZQdlo/aVgX6I5j9BVYnFZib+aRrqEkQ3hbCV9Ag/9xwlN2s2fVycuR
dW8mE92EYrPVw8gzdcSbMlDk8i2GVLE1Hy6nm8vyx73UAY0INrHh7bQ36xrowdfU
5uUItnT7E2h7MceqrSLiwIRmlisR2IJ7IEghKdgmPw2Z65sfcT37mGPJs5yDGPnn
mg3E5rbNhxztUx4z9MzkyRPu8s3Ksi6o+ht1EU/N+QRok1R6GLlh9mI5Bg4Kzopj
O2PNShHk4M6DlE+KWK7Gyebf6y4iIJmP37c2hKutjuOtjW3ziKzuzN4spR3gvVUa
tqCvvPCV2NCL/itJ1UeuxopNxdo0Tn9p4VKwxTv322DNXdUFGpFIdhHiz7896POz
wRMfBizRhPS3okhPSbouctagUJH8BzMd0NtyCMLtRPt9n0ugHi4qu/egs8uCWp4L
m3webLI6lWAozNZFDM9KAkHa3VJ0skdQ5xTEMkCDGRrsZk5mlspS1wgiH58L8PYl
azMRb6E0rZanqLuA3isSVNc8LPiSP/U3g8hm8rV+UehFeB4B2XUws53NGp3mRN0O
BqT+JiH9Ur86q+oL+886fDjYdYyWF/vG9/AxEnTZarYeLLpN60mcSrX2Lco2j4Bf
LRwrBADGKuA/MxVOJIzWtC1MgfXLXdIQrtMltGFFJ49xVZRXMg+DVgurrEfmiV0P
/kwSj1ruagyN1uUOXolohS3RAit7Zifr8jTC+Lic2Fk9gi1O471UxRvOpgKZfdGN
6T+2vDqMHJNyXo6uVdomX3ak7jg27jF6x4lj3KHyaXXIB/TESKQOMGJie5lUJMuO
iNHxArSRWqYFnUwqSlnatrxSJCCLEzolBTbBqu16xCtrFghpC7XYpwHSYEfmkijJ
7JxVMAvc0vn7DXBoWsmsNrfzA1wFNhv7rg26GHKKeoLB4xQoR2WFZuX3GXb0spZk
S69SVJKuBAZkbmL2UDU7hyWHtF2GSihNVW3fhQC6IdSPQEJcu1HljzrmZLDkHXfS
l/xeDjfW/PBhNFzYXSkqx19G/nzG1qADiDWUELx++tMZlQW20UMZH58xNGhahXs3
cv+nBmEOgT8P2o/id51UL8y0f+upTkwnqge66YYRaJTG18NPqo42LHixq8AJjzxb
plGFSQYZEip5iVdRZbgaBwOD1oG5NvgvJ7mvBbxlzr3m1VxhjdND9+m+MP6lGN/i
E2HkQbe7aZTqqOtaQtfEDwb0iwxdV6DmtVAHFWxhN/hiq4ijauGhCCncBPpm3Rdt
0A3sFtvOrl5iiLUOywIxffmMuXH/frgSEoXggxVlDF8uDM6j3avc2XbsOXvgLN0C
UqKu4T5Vfy2kuWc+twwOJ2d7v04N+IzVOI0GSNv0P11EvLdR6ecsJv481eMBFqep
JvC4h9YVk4TZnF7pspOoAaYjX5bDsUWC7v/+cDWGO5M=
`pragma protect end_protected
endmodule
