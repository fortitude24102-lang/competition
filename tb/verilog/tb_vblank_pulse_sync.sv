`timescale 1ns/1ps
module tb_vblank_pulse_sync;
    reg src_clk=0,dst_clk=0,src_reset=1,dst_reset=1,src_vblank=1;
    wire dst_pulse;
    integer pulse_count=0;
    reg previous_pulse=0;

    vblank_pulse_sync dut(.*);
    always #7 src_clk=~src_clk;
    always #5 dst_clk=~dst_clk;

    always @(posedge dst_clk) begin
        if(dst_pulse) pulse_count=pulse_count+1;
        if(dst_pulse && previous_pulse) $fatal(1,"vblank pulse wider than one destination cycle");
        previous_pulse=dst_pulse;
    end

    task wait_dst(input integer cycles);
        repeat(cycles) @(posedge dst_clk);
    endtask
    task complete_frame;
        begin
            src_vblank=0; wait_dst(6);
            src_vblank=1; wait_dst(6);
        end
    endtask

    initial begin
        wait_dst(3); src_reset=0;
        wait_dst(3); dst_reset=0;
        wait_dst(8);
        if(pulse_count!=0) $fatal(1,"startup high replayed as vblank");
        complete_frame();
        if(pulse_count!=1) $fatal(1,"first complete frame missing");

        src_vblank=0; wait_dst(5);
        src_reset=1; src_vblank=1; wait_dst(3); src_reset=0;
        wait_dst(8);
        if(pulse_count!=1) $fatal(1,"source reset created a false vblank");
        complete_frame();
        if(pulse_count!=2) $fatal(1,"source reset did not rearm");

        dst_reset=1; wait_dst(3); dst_reset=0;
        wait_dst(8);
        if(pulse_count!=2) $fatal(1,"destination reset replayed active vblank");
        complete_frame();
        if(pulse_count!=3) $fatal(1,"destination reset did not rearm");
        $display("PASS vblank CDC: independent resets suppress startup pulses and rearm on active video");
        $finish;
    end
    initial begin #5000; $fatal(1,"vblank CDC timeout"); end
endmodule
