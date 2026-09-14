`timescale 1ns/1ps
module tb_underflow_pulse_cdc;
    reg pixel_clk = 1'b0;
    reg gpu_clk = 1'b0;
    reg pixel_reset = 1'b1;
    reg gpu_reset = 1'b1;
    reg scale_underflow = 1'b0;
    wire underflow_pulse_gpu;
    integer pulse_count = 0;
    reg previous_pulse = 1'b0;

    underflow_pulse_cdc dut (
        .pixel_clk(pixel_clk),
        .pixel_reset(pixel_reset),
        .scale_underflow(scale_underflow),
        .gpu_clk(gpu_clk),
        .gpu_reset(gpu_reset),
        .underflow_pulse_gpu(underflow_pulse_gpu)
    );

    always #7 pixel_clk = ~pixel_clk;
    always #5 gpu_clk = ~gpu_clk;

    always @(posedge gpu_clk) begin
        if (!gpu_reset && underflow_pulse_gpu) begin
            if (previous_pulse)
                $fatal(1, "underflow pulse was wider than one GPU clock");
            pulse_count = pulse_count + 1;
        end
        previous_pulse = underflow_pulse_gpu;
    end

    task automatic wait_gpu(input integer cycles);
        repeat (cycles) @(posedge gpu_clk);
    endtask

    task automatic wait_pixel(input integer cycles);
        repeat (cycles) @(posedge pixel_clk);
    endtask

    task automatic expect_pulses(input integer expected, input [8*48-1:0] phase);
        begin
            wait_gpu(10);
            if (pulse_count != expected)
                $fatal(1, "%0s: got %0d GPU pulses, expected %0d", phase, pulse_count, expected);
        end
    endtask

    task automatic begin_episode(input integer source_cycles);
        begin
            @(negedge pixel_clk);
            scale_underflow = 1'b1;
            wait_pixel(source_cycles);
            @(negedge pixel_clk);
            scale_underflow = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb/verilog/underflow_pulse_cdc.vcd");
        $dumpvars(0, tb_underflow_pulse_cdc);

        wait_gpu(3);
        pixel_reset = 1'b0;
        wait_gpu(3);
        gpu_reset = 1'b0;
        expect_pulses(0, "startup");

        // A seven-cycle source episode still produces exactly one GPU pulse.
        begin_episode(7);
        expect_pulses(1, "long source episode");

        // A later episode is a distinct event.
        wait_pixel(3);
        begin_episode(4);
        expect_pulses(2, "separate source episode");

        // Independent idle resets must not replay an old toggle.
        pixel_reset = 1'b1;
        wait_gpu(3);
        pixel_reset = 1'b0;
        expect_pulses(2, "pixel reset while idle");
        gpu_reset = 1'b1;
        wait_gpu(3);
        gpu_reset = 1'b0;
        expect_pulses(2, "GPU reset while idle");

        // Reset during an active episode suppresses a replay until the source goes low.
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        expect_pulses(3, "third source episode");
        pixel_reset = 1'b1;
        wait_gpu(3);
        pixel_reset = 1'b0;
        expect_pulses(3, "pixel reset while active");
        @(negedge pixel_clk);
        scale_underflow = 1'b0;
        wait_pixel(3);
        begin_episode(3);
        expect_pulses(4, "episode after pixel reset rearm");

        // A GPU reset during an active source level must baseline, not replay it.
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        expect_pulses(5, "fifth source episode");
        gpu_reset = 1'b1;
        wait_gpu(3);
        gpu_reset = 1'b0;
        expect_pulses(5, "GPU reset while active");

        $display("PASS underflow CDC: one GPU pulse per episode and independent resets suppress replay");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "underflow CDC timeout");
    end
endmodule
