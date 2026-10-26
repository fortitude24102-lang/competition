`timescale 1ns/1ps
module tb_nav_keys;
 reg clk=0,reset=1;always #5 clk=~clk;
 reg [4:0] keys_n=31;reg [15:0] address=8;reg [31:0] core_data=32'h001abcde;
 wire [31:0] data;
 efinix_nav_keys dut(clk,reset,keys_n,address,core_data,data);
 initial begin
  #12;reset=0;repeat(3)@(negedge clk);
  if(data!==32'h003abcde)$fatal(1,"idle/status preservation");
  keys_n=5'b11110;@(negedge clk);if(data[31:27]!==0)$fatal(1,"missing synchronizer");
  repeat(2)@(negedge clk);if(data[31:27]!==1)$fatal(1,"UP polarity/order");
  keys_n=5'b01001;repeat(3)@(negedge clk);if(data[31:27]!==5'b10110)$fatal(1,"combined keys");
  address=0;core_data=32'hdeadbeef;#1;if(data!==core_data)$fatal(1,"nonstatus modified");
  reset=1;address=8;core_data=0;#1;if(data!==32'h00200000)$fatal(1,"reset false key");
  $display("PASS five input synchronization, active-low mapping and status-only overlay");$finish;
 end
endmodule
