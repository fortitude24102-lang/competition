`timescale 1ps/1ps
// Catches a producer/FIFO restart retaining the old HDMI row origin.
// Uses the real FIFO, line RAM, scaler and HDMI encoder, not a FIFO stub.
module tb_hdmi_warm_reset;
    reg gpu_clk=0, pixel_clk=0, gpu_reset=1, pixel_reset=1;
    reg [15:0] gpu_pixel=0;
    reg gpu_valid=0, gpu_line_last=0, gpu_frame_last=0;
    wire gpu_ready, protocol_error, video_de;
    wire [15:0] video_rgb565;
    integer trial, checked_pixels=0;
    reg checking=0;
    hdmi_subsystem dut (
        .gpu_clk(gpu_clk), .pixel_clk(pixel_clk),
        .gpu_reset(gpu_reset), .pixel_reset(pixel_reset),
        .gpu_pixel(gpu_pixel), .gpu_valid(gpu_valid),
        .gpu_line_last(gpu_line_last), .gpu_frame_last(gpu_frame_last),
        .gpu_ready(gpu_ready), .protocol_error(protocol_error),
        .video_rgb565(video_rgb565), .video_de(video_de)
    );
    always #5000 gpu_clk=~gpu_clk;
    always #3367 pixel_clk=~pixel_clk;
    function automatic [15:0] pattern(input integer x, input integer y);
        pattern=16'h1000+x+y*1024;
    endfunction
    task automatic put(input integer x, input integer y);
        @(negedge gpu_clk);
        gpu_valid=1; gpu_pixel=pattern(x,y);
        gpu_line_last=(x==959); gpu_frame_last=0;
        @(posedge gpu_clk);
        while(!gpu_ready) @(posedge gpu_clk);
        @(negedge gpu_clk); gpu_valid=0;
    endtask
    task automatic run_trial(input integer prefix, input integer pulse_ps);
        integer x,y;
        // Start from a known origin, then stop part-way through a source row.
        gpu_reset=1; #51000; gpu_reset=0;
        for(x=0;x<prefix;x=x+1) put(x,0);
        wait(dut.u_line_buffer.write_index==prefix);
        #1100; gpu_reset=1; #(pulse_ps); gpu_reset=0;
        checked_pixels=0; checking=1;
        fork
            begin
                for(y=0;y<4;y=y+1)
                    for(x=0;x<960;x=x+1) put(x,y);
            end
            begin
                wait(checked_pixels==4*1920);
                checking=0;
                if(protocol_error) $fatal(1,"line marker mismatch after warm reset");
            end
        join
        $display("PASS warm reset prefix=%0d pulse_ps=%0d: two complete source rows aligned",prefix,pulse_ps);
    endtask
    always @(negedge pixel_clk) begin : check_output
        integer h,v,x,y;
        h=dut.u_scale.h_count; v=dut.u_scale.v_count;
        if(checking && video_de && v>=41 && v<45) begin
            x=(h-192)>>1; y=(v-41)>>1;
            if(video_rgb565!==pattern(x,y))
                $fatal(1,"horizontal origin mismatch at x=%0d y=%0d got=%h expected=%h",x,y,video_rgb565,pattern(x,y));
            checked_pixels=checked_pixels+1;
        end
    end
    initial begin
        #37000; gpu_reset=0; #46000; pixel_reset=0;
        run_trial(1,2700);
        run_trial(319,51000);
        run_trial(640,2700);
        run_trial(959,51000);
        $display("PASS HDMI warm reset geometry (pixel_reset remained deasserted)");
        $finish;
    end
    initial begin #(5ms); $fatal(1,"warm reset timeout"); end
endmodule
