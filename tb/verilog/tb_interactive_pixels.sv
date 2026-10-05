`timescale 1ns/1ps
module tb_interactive_pixels;
 reg clock=0,reset=1,in_valid=0,out_ready=0;
 always #5 clock=~clock;
 reg [2:0] op=0;
 reg [15:0] foreground=0,background=0,fill_color=0,color_key=0;
 reg [7:0] alpha=0;
 wire in_ready,out_valid,write_enable;
 wire [15:0] result_pixel;
 gpu_pixel_pipe dut(.*);
 integer f,fields,n=0,keys=0,alphas=0,copies=0;
 reg [15:0] expected;
 reg expected_write;
 initial begin
  repeat(2) @(negedge clock);
  reset=0;
  f=$fopen("generated/verification/v3/game/pixels.txt","r");
  if(!f) $fatal(1,"missing interactive pixel vectors");
  while(!$feof(f)) begin
   fields=$fscanf(f,"%h %h %h %h %h %h %h\n",op,foreground,background,color_key,alpha,expected,expected_write);
   if(fields==7) begin
    in_valid=1; out_ready=0; #1;
    if(!in_ready) $fatal(1,"fresh pixel blocked n=%0d",n);
    @(negedge clock);
    if(!out_valid || result_pixel!==expected || write_enable!==expected_write) $fatal(1,"pixel mismatch n=%0d",n);
    in_valid=0;
    if(n%17==0) repeat(2) begin
     @(negedge clock);
     if(!out_valid || result_pixel!==expected || write_enable!==expected_write) $fatal(1,"backpressure changed pixel");
    end
    case(op)
     2:copies=copies+1;
     3:keys=keys+1;
     4:alphas=alphas+1;
     default:$fatal(1,"unexpected interactive opcode");
    endcase
    out_ready=1;
    @(negedge clock);
    if(out_valid) $fatal(1,"duplicate pixel");
    n=n+1;
   end else if(fields!=-1) $fatal(1,"malformed vector");
  end
  $fclose(f);
  if(copies!=518400 || !keys || !alphas) $fatal(1,"incomplete interactive frame");
  $display("PASS interactive RTL: pixels=%0d COPY=%0d KEY=%0d ALPHA=%0d",n,copies,keys,alphas);
  $finish;
 end
 initial begin #30000000; $fatal(1,"interactive pixel watchdog"); end
endmodule
