`timescale 1ns/1ps
// Testbench only: production pixel RTL is used without any modification.
module tb_bullet_pixels;
 reg clock=0;
 always #5 clock=~clock;
 reg reset=1,in_valid=0,out_ready=0;
 reg [2:0] op=0;
 reg [15:0] foreground=0,background=0,fill_color=0,color_key=0;
 reg [7:0] alpha=0;
 wire in_ready,out_valid,write_enable;
 wire [15:0] result_pixel;
 gpu_pixel_pipe dut(.*);
 integer f,fields,n=0,stalls=0,keys=0,alphas=0,fills=0,copies=0;
 reg [15:0] expected;
 reg expected_write;
 initial begin
  $dumpfile("generated/verification/bullet-demo/bullet_pixels.vcd");
  $dumpvars(0,tb_bullet_pixels);
  repeat(2) @(negedge clock);
  reset=0;
  f=$fopen("generated/verification/bullet-demo/pixels.txt","r");
  if(!f) $fatal(1,"missing host-emitted pixel vectors");
  while(!$feof(f)) begin
   fields=$fscanf(f,"%h %h %h %h %h %h %h %h\n",op,foreground,background,
    fill_color,color_key,alpha,expected,expected_write);
   if(fields==8) begin
    if(n==64) $dumpoff;
    if(n==518400) $dumpon;
    if(n==532000) $dumpoff;
    in_valid=1; out_ready=0;
    #1;
    if(!in_ready) $fatal(1,"pipeline not ready for fresh input n=%0d",n);
    @(negedge clock);
    if(!out_valid || result_pixel!==expected || write_enable!==expected_write)
     $fatal(1,"bullet pixel mismatch n=%0d op=%0d got=%h/%b want=%h/%b",
      n,op,result_pixel,write_enable,expected,expected_write);
    in_valid=0;
    if(n%17==0) begin
     repeat(2) begin
      @(negedge clock);
      if(!out_valid || result_pixel!==expected || write_enable!==expected_write)
       $fatal(1,"output changed under backpressure n=%0d",n);
      stalls=stalls+1;
     end
    end
    case(op)
     1:fills=fills+1;
     2:copies=copies+1;
     3:keys=keys+1;
     4:alphas=alphas+1;
     default:$fatal(1,"unexpected scene opcode");
    endcase
    out_ready=1;
    @(negedge clock);
    if(out_valid) $fatal(1,"duplicate output n=%0d",n);
    n=n+1;
   end else if(fields!=-1) $fatal(1,"malformed vector n=%0d",n);
  end
  $fclose(f);
  // This scene now uses keyed aircraft instead of Fill emitter markers.
  if(copies!=587520 || !keys || !alphas || fills!=0 || !stalls)
   $fatal(1,"incomplete frame coverage");
  $display("PASS bullet RTL: %0d pixels COPY=%0d KEY=%0d ALPHA=%0d FILL=%0d stalls=%0d",
   n,copies,keys,alphas,fills,stalls);
  $finish;
 end
 initial begin
  #30000000;
  $fatal(1,"bullet simulation watchdog");
 end
endmodule
