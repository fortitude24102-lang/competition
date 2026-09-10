`timescale 1ns/1ps
module vblank_pulse_sync (
    input wire src_clk,
    input wire src_reset,
    input wire src_vblank,
    input wire dst_clk,
    input wire dst_reset,
    output wire dst_pulse
);
    reg src_level;
    (* async_reg = "true" *) reg dst_sync0, dst_sync1;
    (* async_reg = "true" *) reg [1:0] reset_pipe;
    reg dst_seen, armed;

    always @(posedge src_clk or posedge src_reset) begin
        if (src_reset)
            src_level <= 1;
        else
            src_level <= src_vblank;
    end

    always @(posedge dst_clk or posedge dst_reset or posedge src_reset) begin
        if (dst_reset || src_reset)
            reset_pipe <= 2'b11;
        else
            reset_pipe <= {reset_pipe[0],1'b0};
    end

    always @(posedge dst_clk) begin
        if (reset_pipe[1]) begin
            dst_sync0 <= 1;
            dst_sync1 <= 1;
            dst_seen <= 1;
            armed <= 0;
        end else begin
            dst_sync0 <= src_level;
            dst_sync1 <= dst_sync0;
            dst_seen <= dst_sync1;
            if (!armed && !dst_sync1)
                armed <= 1;
        end
    end

    assign dst_pulse = !reset_pipe[1] && armed && dst_sync1 && !dst_seen;
endmodule
