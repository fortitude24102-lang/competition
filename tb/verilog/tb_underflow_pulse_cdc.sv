`timescale 1ns/1ps
module tb_underflow_pulse_cdc;
    reg pixel_clk = 1'b0;
    reg gpu_clk = 1'b0;
    reg pixel_reset = 1'b1;
    reg gpu_reset = 1'b1;
    reg scale_underflow = 1'b0;
    wire underflow_pulse_gpu;
    integer pulse_count = 0;
    integer failures = 0;
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
    // A deliberately slower GPU clock makes a pair of valid source episodes
    // arrive before the destination can observe either transition.
    always #50 gpu_clk = ~gpu_clk;

    always @(posedge gpu_clk) begin
        if (gpu_reset || pixel_reset) begin
            if (underflow_pulse_gpu !== 1'b0) begin
                $display("FAIL underflow pulse was nonzero during reset");
                failures = failures + 1;
            end
        end else if (underflow_pulse_gpu) begin
            if (previous_pulse) begin
                $display("FAIL underflow pulse was wider than one GPU clock");
                failures = failures + 1;
            end
            pulse_count = pulse_count + 1;
        end
        previous_pulse = underflow_pulse_gpu;
    end

    always @(posedge underflow_pulse_gpu) begin
        if (gpu_reset || pixel_reset) begin
            $display("FAIL underflow pulse rose during reset");
            failures = failures + 1;
        end
    end

    task automatic wait_gpu(input integer cycles);
        repeat (cycles) @(posedge gpu_clk);
    endtask

    task automatic expect_no_new_pulses(input integer cycles, input [8*48-1:0] phase);
        integer pulse_count_before;
        begin
            pulse_count_before = pulse_count;
            wait_gpu(cycles);
            if (pulse_count != pulse_count_before) begin
                $display("FAIL %0s: reset recovery created a phantom pulse", phase);
                failures = failures + 1;
            end
        end
    endtask

    task automatic wait_pixel(input integer cycles);
        repeat (cycles) @(posedge pixel_clk);
    endtask

    task automatic expect_pulses(input integer expected, input [8*48-1:0] phase);
        begin
            wait_gpu(10);
            if (pulse_count != expected) begin
                $display("FAIL %0s: got %0d GPU pulses, expected %0d", phase, pulse_count, expected);
                failures = failures + 1;
            end
        end
    endtask

    task automatic begin_close_episodes;
        begin
            // The rising edges are 28 ns apart, inside one 100 ns GPU cycle.
            @(posedge gpu_clk);
            @(negedge pixel_clk);
            scale_underflow = 1'b1;
            wait_pixel(1);
            @(negedge pixel_clk);
            scale_underflow = 1'b0;
            wait_pixel(1);
            @(negedge pixel_clk);
            scale_underflow = 1'b1;
            wait_pixel(1);
            @(negedge pixel_clk);
            scale_underflow = 1'b0;
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

        // Two separate episodes before one GPU observation must both survive.
        begin_close_episodes();
        expect_pulses(4, "closely spaced separate source episodes");

        // Independent resets keep the output low and recover without a phantom.
        pixel_reset = 1'b1;
        wait_gpu(2);
        pixel_reset = 1'b0;
        expect_no_new_pulses(4, "pixel reset idle recovery");
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        wait_pixel(1);
        @(negedge pixel_clk);
        scale_underflow = 1'b0;
        expect_pulses(5, "episode after pixel reset recovery");

        // This real source edge occurs during pixel local-reset release.
        pixel_reset = 1'b1;
        wait_gpu(2);
        pixel_reset = 1'b0;
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        wait_pixel(1);
        @(negedge pixel_clk);
        scale_underflow = 1'b0;
        expect_pulses(6, "episode during pixel reset release");

        gpu_reset = 1'b1;
        wait_gpu(2);
        gpu_reset = 1'b0;
        expect_no_new_pulses(4, "GPU reset idle recovery");
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        wait_pixel(1);
        @(negedge pixel_clk);
        scale_underflow = 1'b0;
        expect_pulses(7, "episode after GPU reset recovery");

        // This real source edge occurs during GPU local-reset release.
        gpu_reset = 1'b1;
        wait_gpu(2);
        gpu_reset = 1'b0;
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        wait_pixel(1);
        @(negedge pixel_clk);
        scale_underflow = 1'b0;
        expect_pulses(8, "episode during GPU reset release");

        // Reset during an active episode suppresses a replay until the source goes low.
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        expect_pulses(9, "ninth source episode");
        pixel_reset = 1'b1;
        wait_gpu(2);
        pixel_reset = 1'b0;
        expect_pulses(9, "pixel reset while active");
        @(negedge pixel_clk);
        scale_underflow = 1'b0;
        wait_pixel(3);
        begin_episode(3);
        expect_pulses(10, "episode after pixel reset rearm");

        // A GPU reset during an active source level must baseline, not replay it.
        @(negedge pixel_clk);
        scale_underflow = 1'b1;
        expect_pulses(11, "eleventh source episode");
        gpu_reset = 1'b1;
        wait_gpu(2);
        gpu_reset = 1'b0;
        expect_pulses(11, "GPU reset while active");

        if (failures != 0)
            $fatal(1, "underflow CDC failures: %0d", failures);
        $display("PASS underflow CDC: burst episodes queue and resets preserve new events without replay");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "underflow CDC timeout");
    end
endmodule
