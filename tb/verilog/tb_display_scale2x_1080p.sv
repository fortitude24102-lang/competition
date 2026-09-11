`timescale 1ps/1ps
module tb_display_scale2x_1080p;
    reg clk=0, reset=1;
    wire [9:0] line_read_index;
    wire line_begin,line_done;
    wire [15:0] rgb565;
    wire hs,vs,de,vblank;
    wire [11:0] expected_h=dut.h_count==12'd2199 ? 12'd0 : dut.h_count+1'b1;
    wire [11:0] expected_offset=expected_h-12'd512;
    wire [9:0] expected_index=expected_h>=12'd512 && expected_h<12'd1792 ? expected_offset[10:1] : 10'd0;
    integer de_count=0,scaled_count=0,begin_count=0,done_count=0;
    display_scale2x_1080p dut(
        .clk(clk),.reset(reset),.line_pixel(16'h1234),.line_valid(1'b1),
        .line_read_index(line_read_index),.line_begin(line_begin),.line_done(line_done),
        .rgb565(rgb565),.hs(hs),.vs(vs),.de(de),.vblank(vblank),.underflow()
    );
    always #3367 clk=~clk;
    initial begin #20000 reset=0; end
    always @(negedge clk) if(!reset) begin : check
        reg [11:0] h,ax;
        reg [10:0] v,ay;
        reg scaled;
        h=dut.h_count; v=dut.v_count; ax=h-12'd192; ay=v-11'd41;
        scaled=de && ax>=12'd320 && ax<12'd1600 && ay>=11'd60 && ay<11'd1020;
        if(de) de_count=de_count+1;
        if(scaled) begin
            scaled_count=scaled_count+1;
            if(rgb565!==16'h1234) $fatal(1,"scale mapping mismatch");
        end else if(rgb565!==0) $fatal(1,"non-black border/blanking");
        if(line_begin) begin_count=begin_count+1;
        if(line_done) done_count=done_count+1;
        if(line_read_index!==expected_index) $fatal(1,"prefetch mapping mismatch");
        if(h==12'd2199 && v==11'd1124) begin
            if(de_count!=1920*1080 || scaled_count!=1280*960 || begin_count!=480 || done_count!=480)
                $fatal(1,"geometry counts de=%0d scaled=%0d begin=%0d done=%0d",de_count,scaled_count,begin_count,done_count);
            $display("PASS scale: 2200x1125 timing, 1280x960 centered image, 320/60 borders and 480 double-line handshakes");
            $finish;
        end
    end
    initial begin #(20ms); $fatal(1,"scale timeout"); end
endmodule
