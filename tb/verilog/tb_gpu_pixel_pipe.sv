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
        background=16'hdead; color_key=16'hbeef; alpha=8'h80;
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
        expected_pixel[sent]=(op==1)?fill_color:(op==2)?foreground:16'b0;
        expected_write[sent]=(op==1 || op==2);
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
    // Reset discards a stalled in-flight transaction.
    in_valid=1; op=2; foreground=16'h1234; out_ready=0;
    @(negedge clock);
    reset=1;
    @(negedge clock);
    if(out_valid || write_enable) $fatal(1,"reset did not flush pending output");
    $display("PASS gpu_pixel_pipe: 10000 ordered transactions, %0d stalls, %0d cycles",stalls,cycles);
    $finish;
  end
endmodule


