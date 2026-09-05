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
////预处理功能开始         
function [15:0] SearchPolynomialCof(input [63:0] Polynomial);
integer i,n;
begin
  n = 0;
  for(i=1;(i<64&&(n<2)); i=i+1)
  begin
    if(Polynomial[i]==1)
    begin
      if(n==0)
        SearchPolynomialCof[7:0] = i;
      else
        SearchPolynomialCof[15:8] = i;
      n=n+1;
    end
  end
end
endfunction     

localparam COF_H = (SearchPolynomialCof(POLYNOMIAL)>>8);
localparam COF_L = (SearchPolynomialCof(POLYNOMIAL)&16'h00ff);
////预处理功能结束      
       
localparam SHIFTERWIDTH = (DATAWIDTH<COF_H)?COF_H:DATAWIDTH;


reg    [SHIFTERWIDTH-1:0] LastPrbsValue;
reg    [SHIFTERWIDTH-1:0] NewPrbsValue ;


always @(negedge(rstn), posedge(CLK))
begin
    if(rstn == 1'b0)
      LastPrbsValue <= {(SHIFTERWIDTH){1'b1}};
    else
    begin 
    if(LDI)
      LastPrbsValue <= PrbsInitValue;
    else if(EN)
    begin
      LastPrbsValue <= NewPrbsValue;
    end
    end
end


genvar  i;

reg    [DATAWIDTH-1:0]  XorParam2, XorParam1;

generate
begin
  for(i=DATAWIDTH; i>0; i=i-1)
  begin: XORUT
    
    always @(*)
    begin
      if((COF_H>(DATAWIDTH-i)))
        XorParam2[i-1] <= LastPrbsValue[(COF_H-1)-(DATAWIDTH-i)];
      else
        XorParam2[i-1] <= NewPrbsValue[COF_H+i-1];
    end

    always @(*)
    begin
      if((COF_L>(DATAWIDTH-i)))
        XorParam1[i-1] <= LastPrbsValue[(COF_L-1)-(DATAWIDTH-i)];
      else
        XorParam1[i-1] <= NewPrbsValue[COF_L+i-1];
    end
    
    always @(*)
    begin
      NewPrbsValue[i-1] <= XorParam2[i-1] ^ XorParam1[i-1]; 
    end
  end
end
endgenerate

integer j;
generate
begin
  if(DATAWIDTH<COF_H)
  begin
    always @(*)
    begin
      for(j=DATAWIDTH; j<COF_H; j=j+1)
        NewPrbsValue[j] <= LastPrbsValue[j-DATAWIDTH]; 
    end
  end
end
endgenerate


assign  PrbsValue    = LastPrbsValue[SHIFTERWIDTH-1:SHIFTERWIDTH-DATAWIDTH];

//Encryption end
endmodule
