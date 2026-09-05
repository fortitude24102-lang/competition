
module simple_dual_port_ram
#(
   parameter DATA_WIDTH       = 8,
   parameter ADDR_WIDTH       = 9,
   parameter OUTPUT_REG       = "TRUE",
   parameter RAM_INIT_FILE    = "",
   parameter RAM_INIT_RADIX   = "HEX"
)
(
   input [(DATA_WIDTH-1):0]   wdata,
   input [(ADDR_WIDTH-1):0]   waddr, raddr,
   input                      we, wclk, re, rclk,
   output [(DATA_WIDTH-1):0]  rdata
);

   localparam MEMORY_DEPTH = 2**ADDR_WIDTH;
   localparam MAX_DATA     = (1<<ADDR_WIDTH)-1;
   
   reg [DATA_WIDTH-1:0] ram[MEMORY_DEPTH-1:0];
   wire [DATA_WIDTH-1:0] r_rdata_1P;
   reg [DATA_WIDTH-1:0] r_rdata_2P;
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
JL0As3bUJkfhHwUm1wgSuXPO3FwahynkSdoYRUFKI/+DwTp2rOPo7tl+1RQg3Nr+
pjSAxtgg7jvowrZDZFDu5T+Ox7dANzI+w+nlwkFTViFXDkYd7bhjMEmuxpqSFW9n
0d23Yvnekd5P3g5Z3AltT3CO41SHd2OnRxojhNfWu4BMx8ArwOnS/hBkI+PHtoI1
qdCOuu07d85IDdh1ZsLn2+8yvSN1keLuI4Er6ldagSbUjT82PfkibCdvOAaCQfVe
i2sv+/LjTjeoKfjFU6lmCYNpLKOy31+XCHnDzS+MkrgQrSS/fGkAjbZ9kVVclXP6
At0MFiP+63PAal6TayTmEw==
`pragma protect key_keyowner="Mentor Graphics Corporation"
`pragma protect key_keyname="MGC-VERIF-SIM-RSA-1"
`pragma protect key_method="rsa"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=128)
`pragma protect key_block
SOph2B/0MHyqtbqJ2SOwNG9lQO00veglDG1PviKkyZ0rghIvza4CfVsgHTDrpMjQ
2WXsjhEZhMqs/oIfmCDWb4XkgZq+P/E0J38ZkqluSahdkkH/PQ7za/G38jBaxloB
7OYGVCaDc5IbVOCqyrKOLxl5C+HZR7ur/IHRwld5chs=
`pragma protect data_method="aes256-cbc"
`pragma protect encoding=(enctype="base64", line_length=64, bytes=960)
`pragma protect data_block
+GFs+yOQqB8jpq+vGyAuCUnR/HjsugqJyMBgN24TSkgKuRWcWuQ7UTLqSr5xS7iJ
F5sy0iWFVxxfV5jpcTR61naXQ/FN9wji4Zu8xLQAAodU1nEaSdOJwsHhNqFbU86l
jeZLBSorJ3p4X9irYXv3vht/UJ4dvAr0T5Kv+N59kZ0ijGE6Nw36z4rfHgqaPlT9
7VNlCYlydZke3+7J2AC4FjPbalAe9fFpAoq1S+prGNxW4+HdGa77kkxXShSTY0f9
jSXutMuDPLDFs0qBP/T/HVnRIjvf2kxUdyrT37K+OW6TeFNPfKPrck7aNwdswI4L
yPWkIYH00tOqNAsDiIE8npw1jCxtHrEmVRO2NjFsp++xgo2b5QxGfbmX7JzfPKv8
K1VWUoQCEUK1qlTenVCqcMZ64K8WYuzG2r2jcP8P/UrQt4lhM56pQ67u7wwrjR9R
bU7mmqyPzZb2/04oiCteu5SatuqDk9hIntnWOT0bymZYPlS+ut+THKUjC2ffl0yJ
QQCKITMv7Zz1z0zRrsHfIK4aMWLNbTzRUkbQJeo1sJwiTHfcFDlfB/MtsdKZxNWQ
i9vnd1zY5Emhp5suGQblUFC5TH5iR5Yqj2bi1YsjfjyolDDa7o7iCP0lDR/sG8rE
8qDyO6ZG9GnPZcDBnDuo4TNuxXIMlxs8tImZElr3XyYLZiAnHU+eaKGarXqRsNwU
2yjqCJyMn2R8vCZaJZFcYC1DCHkxKZ22f7hCoNhaF92gq+YoBdj1j8KcDGP41llX
gfar+Zy9CslrokxM1KqLo0of0QrdJczg2Il/+MRUYjax5WdyEBnw3bs79RjFcwL5
DUmbEROq5nmCv29ZuvdF1punf4kfmye7hNhmly4sBrNSUUufIVaRV6/MiOeb/rz8
GWmGgd56JGTy0KT0eMCttucWQCsob5aX3BqYyYa16DiSDK2LrZkwD9yc6KSXHRMA
G92S+od6l9JiREjJP92Y/khBenqzRxCAS4GBUSGhMOmtDztz/EOfTxkTbV+aBEYk
9G0F5Tl9aeOV07oA4azbrkqxZuiB4n4k9eaAjCuU0VtJKFVT7JMciI2uKw1Z8Pvv
JC3cua7ftUQs+qpAr721B8I6klFLDIPuRlpVpX5clfhHYRp/eB8aNOZnMojTstnU
wkndljTgTU/RV6ItTEz7hkzBH8KtVdsX5Ssl0+0jbzBy7VvZ74vB8fy19f/UVf79
fIXST/qXtAOO5h8wsE5/YDNV5luh3y0wAu926NDmTdRRHlUvq+imE1EFYSBGtXBq
`pragma protect end_protected

endmodule
