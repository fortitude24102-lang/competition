`timescale 1ns/1ps
module underflow_pulse_cdc #(
    // 65,535 pending episodes fit before wrap. This is far beyond the
    // display's possible in-flight underflow episodes between reset periods.
    parameter EVENT_COUNTER_WIDTH = 16
) (
    input wire pixel_clk,
    input wire pixel_reset,
    input wire scale_underflow,
    input wire gpu_clk,
    input wire gpu_reset,
    output wire underflow_pulse_gpu
);
    reg scale_underflow_prev;
    reg [EVENT_COUNTER_WIDTH-1:0] pixel_event_count;
    wire [EVENT_COUNTER_WIDTH-1:0] pixel_event_gray;
    (* async_reg = "true" *) reg [EVENT_COUNTER_WIDTH-1:0] gpu_gray_sync0;
    (* async_reg = "true" *) reg [EVENT_COUNTER_WIDTH-1:0] gpu_gray_sync1;
    wire [EVENT_COUNTER_WIDTH-1:0] gpu_event_count;
    reg [EVENT_COUNTER_WIDTH-1:0] gpu_consumed_count;
    reg gpu_gap;
    reg underflow_pulse_gpu_reg;

    function [EVENT_COUNTER_WIDTH-1:0] gray_to_binary;
        input [EVENT_COUNTER_WIDTH-1:0] gray;
        integer bit_index;
        begin
            gray_to_binary[EVENT_COUNTER_WIDTH-1] = gray[EVENT_COUNTER_WIDTH-1];
            for (bit_index = EVENT_COUNTER_WIDTH - 2; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_binary[bit_index] = gray_to_binary[bit_index + 1] ^ gray[bit_index];
        end
    endfunction

    assign pixel_event_gray = pixel_event_count ^ (pixel_event_count >> 1);
    assign gpu_event_count = gray_to_binary(gpu_gray_sync1);

    // Keep the level history live through either reset. A high level that
    // spans reset cannot replay, while a low-to-high transition immediately
    // after reset deassertion is still a valid new episode.
    always @(posedge pixel_clk) begin
        scale_underflow_prev <= scale_underflow;
    end

    // Either local-domain reset starts a fresh counter epoch for both sides of
    // this CDC channel. Therefore the destination never needs to baseline
    // away post-reset events: zero is its known initial consumed count.
    always @(posedge pixel_clk or posedge pixel_reset or posedge gpu_reset) begin
        if (pixel_reset || gpu_reset)
            pixel_event_count <= {EVENT_COUNTER_WIDTH{1'b0}};
        else if (scale_underflow && !scale_underflow_prev)
            pixel_event_count <= pixel_event_count + 1'b1;
    end

    always @(posedge gpu_clk or posedge gpu_reset or posedge pixel_reset) begin
        if (gpu_reset || pixel_reset) begin
            gpu_gray_sync0 <= {EVENT_COUNTER_WIDTH{1'b0}};
            gpu_gray_sync1 <= {EVENT_COUNTER_WIDTH{1'b0}};
            gpu_consumed_count <= {EVENT_COUNTER_WIDTH{1'b0}};
            gpu_gap <= 1'b0;
            underflow_pulse_gpu_reg <= 1'b0;
        end else begin
            gpu_gray_sync0 <= pixel_event_gray;
            gpu_gray_sync1 <= gpu_gray_sync0;
            underflow_pulse_gpu_reg <= 1'b0;
            if (gpu_gap) begin
                gpu_gap <= 1'b0;
            end else if (gpu_event_count != gpu_consumed_count) begin
                gpu_consumed_count <= gpu_consumed_count + 1'b1;
                gpu_gap <= 1'b1;
                underflow_pulse_gpu_reg <= 1'b1;
            end
        end
    end

    assign underflow_pulse_gpu = underflow_pulse_gpu_reg;
endmodule
