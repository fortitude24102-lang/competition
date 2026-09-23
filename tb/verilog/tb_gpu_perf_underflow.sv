`timescale 1ns/1ps

module tb_gpu_perf_underflow;
    reg clock = 1'b0;
    reg reset = 1'b1;
    reg io_clear = 1'b0;
    reg io_active = 1'b0;
    reg io_pixelDone = 1'b0;
    reg io_readBeat = 1'b0;
    reg [3:0] io_writeStrobe = 4'b0000;
    reg io_stalled = 1'b0;
    reg io_underflow = 1'b0;
    reg [1:0] io_renderGrant = 2'b00;
    reg [1:0] io_scanoutGrant = 2'b00;
    wire [63:0] io_cycles;
    wire [63:0] io_pixels;
    wire [63:0] io_readBytes;
    wire [63:0] io_writeBytes;
    wire [63:0] io_stalls;
    wire [63:0] io_underflows;
    wire [63:0] io_renderGrants;
    wire [63:0] io_scanoutGrants;

    GpuPerfCounters dut (
        .clock(clock),
        .reset(reset),
        .io_clear(io_clear),
        .io_active(io_active),
        .io_pixelDone(io_pixelDone),
        .io_readBeat(io_readBeat),
        .io_writeStrobe(io_writeStrobe),
        .io_stalled(io_stalled),
        .io_underflow(io_underflow),
        .io_renderGrant(io_renderGrant),
        .io_scanoutGrant(io_scanoutGrant),
        .io_cycles(io_cycles),
        .io_pixels(io_pixels),
        .io_readBytes(io_readBytes),
        .io_writeBytes(io_writeBytes),
        .io_stalls(io_stalls),
        .io_underflows(io_underflows),
        .io_renderGrants(io_renderGrants),
        .io_scanoutGrants(io_scanoutGrants)
    );

    always #5 clock = ~clock;

    task automatic tick;
        begin
            @(posedge clock);
            #1;
        end
    endtask

    task automatic pulse_underflow;
        begin
            io_underflow = 1'b1;
            tick();
            io_underflow = 1'b0;
            tick();
        end
    endtask

    initial begin
        $dumpfile("tb/verilog/gpu_perf_underflow.vcd");
        $dumpvars(0, tb_gpu_perf_underflow);

        if ($bits(io_underflows) != 64)
            $fatal(1, "underflow counter output is not 64 bits");

        tick();
        tick();
        reset = 1'b0;
        tick();
        if (io_underflows !== 64'd0)
            $fatal(1, "underflow counter did not reset: %h", io_underflows);

        pulse_underflow();
        pulse_underflow();
        pulse_underflow();
        if (io_underflows !== 64'd3)
            $fatal(1, "expected three exact underflow increments, got %0d", io_underflows);
        if (io_cycles !== 64'd0 || io_pixels !== 64'd0 || io_readBytes !== 64'd0 ||
            io_writeBytes !== 64'd0 || io_stalls !== 64'd0 ||
            io_renderGrants !== 64'd0 || io_scanoutGrants !== 64'd0)
            $fatal(1, "underflow pulses changed an unrelated performance counter");

        io_underflow = 1'b1;
        io_clear = 1'b1;
        tick();
        io_underflow = 1'b0;
        io_clear = 1'b0;
        if (io_underflows !== 64'd0)
            $fatal(1, "clear did not take priority over an underflow pulse");

        pulse_underflow();
        if (io_underflows !== 64'd1)
            $fatal(1, "counter did not resume after clear: %0d", io_underflows);

        $display("PASS GPU performance underflow counter: 64-bit exact increment and clear priority");
        $finish;
    end
endmodule
