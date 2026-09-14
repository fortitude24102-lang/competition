`timescale 1ns/1ps
module underflow_pulse_cdc (
    input wire pixel_clk,
    input wire pixel_reset,
    input wire scale_underflow,
    input wire gpu_clk,
    input wire gpu_reset,
    output wire underflow_pulse_gpu
);
    reg pixel_underflow_prev;
    reg pixel_armed;
    reg pixel_event_toggle;
    (* async_reg = "true" *) reg gpu_sync0, gpu_sync1;
    reg gpu_toggle_seen;
    reg gpu_armed;
    reg [1:0] gpu_warmup;
    (* async_reg = "true" *) reg [1:0] reset_pipe;

    // Count only low-to-high episode boundaries after reset has observed idle.
    // This prevents a level that spans a pixel reset from being replayed.
    always @(posedge pixel_clk or posedge pixel_reset) begin
        if (pixel_reset) begin
            pixel_underflow_prev <= 1'b0;
            pixel_armed <= 1'b0;
            pixel_event_toggle <= 1'b0;
        end else begin
            pixel_underflow_prev <= scale_underflow;
            if (!pixel_armed) begin
                if (!scale_underflow)
                    pixel_armed <= 1'b1;
            end else if (scale_underflow && !pixel_underflow_prev) begin
                pixel_event_toggle <= ~pixel_event_toggle;
            end
        end
    end

    // Either reset flushes the destination synchronizer before it can emit a
    // pulse.  The source reset is intentionally included to suppress a toggle
    // reset transition from becoming a GPU-domain event.
    always @(posedge gpu_clk or posedge gpu_reset or posedge pixel_reset) begin
        if (gpu_reset || pixel_reset)
            reset_pipe <= 2'b11;
        else
            reset_pipe <= {reset_pipe[0], 1'b0};
    end

    always @(posedge gpu_clk) begin
        if (reset_pipe[1]) begin
            gpu_sync0 <= 1'b0;
            gpu_sync1 <= 1'b0;
            gpu_toggle_seen <= 1'b0;
            gpu_armed <= 1'b0;
            gpu_warmup <= 2'd0;
        end else begin
            gpu_sync0 <= pixel_event_toggle;
            gpu_sync1 <= gpu_sync0;
            if (!gpu_armed) begin
                gpu_toggle_seen <= gpu_sync1;
                if (gpu_warmup == 2'd3)
                    gpu_armed <= 1'b1;
                else
                    gpu_warmup <= gpu_warmup + 1'b1;
            end else begin
                gpu_toggle_seen <= gpu_sync1;
            end
        end
    end

    assign underflow_pulse_gpu = !reset_pipe[1] && gpu_armed &&
        (gpu_sync1 ^ gpu_toggle_seen);
endmodule
