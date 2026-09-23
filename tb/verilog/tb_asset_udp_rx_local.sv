`timescale 1ns/1ps
module tb_asset_udp_rx_local;
 reg clk=0,reset=1,rx_valid=0,rx_last=0,meta_ready=0,payload_ready=0; reg [7:0] rx_byte; reg [15:0] rx_length; reg [31:0] current_session=32'h1234;
 wire rx_ready,meta_valid,payload_valid,payload_last; wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,meta_crc32,error_count; wire [15:0] meta_length,meta_flags; wire [7:0] payload_data;
 asset_udp_rx d(.*); always #5 clk=~clk;
 reg [7:0] p[0:35]; integer i;
 initial begin
  p[0]=8'h41;p[1]=8'h53;p[2]=8'h53;p[3]=8'h54;p[4]=0;p[5]=1;p[6]=0;p[7]=2;
  p[8]=0;p[9]=0;p[10]=18;p[11]=52;p[12]=0;p[13]=0;p[14]=0;p[15]=7;
  p[16]=0;p[17]=0;p[18]=0;p[19]=0;p[20]=0;p[21]=4;p[22]=0;p[23]=1;p[24]=0;p[25]=0;p[26]=0;p[27]=0;p[28]=0;p[29]=0;p[30]=0;p[31]=0;
  p[32]=8'haa;p[33]=8'hbb;p[34]=8'hcc;p[35]=8'hdd;
  #20 reset=0; rx_length=36; for(i=0;i<36;i=i+1) begin @(negedge clk); while(!rx_ready) @(negedge clk); rx_valid=1;rx_byte=p[i];rx_last=(i==35); end @(negedge clk);rx_valid=0;rx_last=0;
  @(negedge clk); if(!meta_valid) $fatal(1,"metadata missing"); meta_ready=1; @(negedge clk); meta_ready=0; payload_ready=1; for(i=0;i<4;i=i+1) begin @(negedge clk); if(!payload_valid||payload_data!==p[32+i]) $fatal(1,"payload mismatch"); end $display("PASS asset rx legal packet");$finish;
 end
endmodule
