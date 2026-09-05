//////////////////PRBSAnyGENERATOR////////////////////
////DATAWIDTH       数据宽度,可从1到N比特
////POLYNOMIAL      PRBS多项式的系数，如：1000000000000011对应X^15+X^1+1(X^0)
////PrbsInitValue   PRBS初始值，可按需设置

////LDI             装载PRBS初始值
////EN              时钟使能
////PrbsValue       输出PRBS值
////Author:   kqc
//////////////////PRBSAnyGENERATOR////////////////////

`timescale 1ns/1ps

//parameter DATAWIDTH =31, POLYNOMIAL =16'b1000000000000011;
module PrbsAnyGenerator
       #(parameter DATAWIDTH = 1 ,  POLYNOMIAL =6'b101001)
       (
        input                  rstn, CLK,
        input                  LDI, 
        input  [DATAWIDTH-1:0] PrbsInitValue,
        input                  EN,
        output [DATAWIDTH-1:0] PrbsValue
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
jSNZ9pSopsA6GLjhq4Lm5ppdne5nqUfKLb+PxqiTuyyjuwSwzdZJ23T4+v53QCKj
9tCN8pjCg8Y1fEXZTz44QqSPX3vZXLRksZAPcFfC7LSKG1giSENuNdeb8dvF2zvF
UWOnP6xJZZuwGpFqJU/5OU2XA5HYGWxELaGbk55hVhBNJpL2Nw+mmzlU5YlmW6rn
NMYNODlmyAhWtm1sUque+lPvMwn7ZsGpGpO2iG+LnQF3/Zh1duHWeuwnxxr24uUj
ITRKcqfotWJ5OL2vyofINJjnXGryXQbLyXSc9w/Bdqg05KfUL1UwZRPWMo2jtH2x
UiFU0M+PzKuwCVRAwb68GA==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
CkNpxg4qfrY9wTtnoBmB9FLcF5hFA9u4b6V1N6vywrt4FABAMupN/lYuqzFGVxUJ
hgW7UtkoONcWgLpLw0y9YwmsFFDTW5ydpE6S/XBkJM/0ijJFTccfN5Y7SDqNt2do
LwydInZdS1FSzEbhtmjwGKwKQc6pe8Yy95LRmRL2GbI=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=1888)
`pragma protect data_block
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
w/v+qhtUU/gBLK/YTtT6UA==
`pragma protect end_protected
endmodule
