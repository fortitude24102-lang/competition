`timescale 1ns/1ps
module tb_gpu_pixel_pipe;
  reg clock=0;
  always #5 clock=~clock;
  reg reset=1, in_valid=0, out_ready=0;
  reg [2:0] op=0;
  reg [15:0] foreground=0, background=0, fill_color=0, color_key=0;
  reg [7:0] alpha=0;
  wire in_ready,out_valid,write_enable;
  wire [15:0] result_pixel;
  gpu_pixel_pipe dut(.*);
  integer sent=0, received=0, cycles=0, stalls=0;
  reg [31:0] rng=32'h2197abcd;
  reg [15:0] expected_pixel[0:9999];
  reg expected_write[0:9999];
  reg held=0;
  reg [15:0] held_pixel;
  reg held_write;
  initial begin
    repeat(2) @(negedge clock);
    if(out_valid || write_enable) $fatal(1,"reset must empty pipeline");
    reset=0;
    while(received<10000 && cycles<100000) begin
      rng=rng ^ (rng<<13); rng=rng ^ (rng>>17); rng=rng ^ (rng<<5);
      out_ready=(cycles<32) || rng[0];
      if(!in_valid || in_ready) begin
        in_valid=sent<10000 && ((cycles<32) || rng[1]);
        op=3'(sent%8);
        foreground=16'(sent); fill_color=16'(sent ^ 32'ha55a);
        background=16'hdead; color_key=(sent & 1) ? 16'(sent) : 16'hbeef; alpha=8'h80;
      end
      #1;
      if(held && (!out_valid || result_pixel!==held_pixel || write_enable!==held_write))
        $fatal(1,"output changed while stalled");
      if(out_valid) begin
        if(received>=sent) $fatal(1,"duplicate or zero-cycle output");
        if(result_pixel!==expected_pixel[received] || write_enable!==expected_write[received])
          $fatal(1,"transaction mismatch index=%0d pixel=%h",received,result_pixel);
      end
      held=out_valid && !out_ready;
      held_pixel=result_pixel; held_write=write_enable;
      if(held) stalls=stalls+1;
      if(out_valid && out_ready) received=received+1;
      if(in_valid && in_ready) begin
        expected_pixel[sent]=(op==1)?fill_color:(op==2)?foreground:(op==3)?foreground:16'b0;
        expected_write[sent]=(op==1)||(op==2)||((op==3)&&(foreground!=color_key));
        sent=sent+1;
      end
      if(cycles==31 && (sent!=32 || received!=31)) $fatal(1,"expected one-cycle latency and one pixel per cycle");
      @(negedge clock);
      cycles=cycles+1;
    end
    if(sent!=10000 || received!=10000 || stalls==0) $fatal(1,"lost transactions or no stalls");
    in_valid=0; out_ready=1;
    @(negedge clock);
    if(out_valid) $fatal(1,"extra transaction");
    // Color Key boundary vectors: transparent hit suppresses write, neighbours write.
    begin : color_key_boundary
      integer k;
      reg [15:0] fg [0:5];
      reg [15:0] key [0:5];
      reg        w [0:5];
      fg[0]=16'h0000; key[0]=16'h0000; w[0]=1'b0;
      fg[1]=16'h0000; key[1]=16'h0001; w[1]=1'b1;
      fg[2]=16'hffff; key[2]=16'hffff; w[2]=1'b0;
      fg[3]=16'hffff; key[3]=16'hfffe; w[3]=1'b1;
      fg[4]=16'hbeef; key[4]=16'hbeef; w[4]=1'b0;
      fg[5]=16'hbeef; key[5]=16'hbeee; w[5]=1'b1;
      for (k=0; k<6; k=k+1) begin
        in_valid=1'b1; op=3; foreground=fg[k]; color_key=key[k];
        background=16'h0; fill_color=16'h0; alpha=8'h0;
        @(negedge clock);
        if(out_valid !== 1'b1) $fatal(1,"color key boundary: missing output k=%0d",k);
        if(write_enable !== w[k]) $fatal(1,"color key boundary: write k=%0d got %b want %b",k,write_enable,w[k]);
        if(result_pixel !== fg[k]) $fatal(1,"color key boundary: pixel k=%0d got %h want %h",k,result_pixel,fg[k]);
      end
      in_valid=1'b0;
      @(negedge clock);
      if(out_valid !== 1'b0) $fatal(1,"color key boundary: trailing output");
    end
    // Reset discards a stalled in-flight transaction.
    in_valid=1; op=2; foreground=16'h1234; out_ready=0;
    @(negedge clock);
    reset=1;
    @(negedge clock);
    if(out_valid || write_enable) $fatal(1,"reset did not flush pending output");
    $display("PASS gpu_pixel_pipe: 10000 ordered transactions (Fill/Copy/ColorKey), %0d stalls, %0d cycles, color-key boundaries",stalls,cycles);
    $finish;
  end
endmodule


