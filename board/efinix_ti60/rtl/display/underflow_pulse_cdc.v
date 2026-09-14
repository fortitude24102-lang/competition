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
    wire combined_reset = pixel_reset | gpu_reset;
    (* async_reg = "true" *) reg [1:0] pixel_reset_release;
    (* async_reg = "true" *) reg [1:0] gpu_reset_release;
    wire pixel_reset_local = pixel_reset_release[1];
    wire gpu_reset_local = gpu_reset_release[1];
    reg scale_underflow_prev;
    reg pixel_release_pending;
    reg [EVENT_COUNTER_WIDTH-1:0] pixel_event_count;
    // This register, rather than a combinational binary-to-Gray XOR network,
    // is the only source-domain signal that crosses to the GPU domain.
    (* keep = "true" *) reg [EVENT_COUNTER_WIDTH-1:0] pixel_event_gray;
    wire [EVENT_COUNTER_WIDTH-1:0] pixel_event_count_next;
    wire [EVENT_COUNTER_WIDTH-1:0] pixel_event_gray_next;
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

    assign pixel_event_count_next = pixel_event_count + 1'b1;
    assign pixel_event_gray_next = pixel_event_count_next ^ (pixel_event_count_next >> 1);
    assign gpu_event_count = gray_to_binary(gpu_gray_sync1);

    // The combined external reset asserts both local reset requests at once.
    // Each request only deasserts after two local clock edges, so pixel_reset
    // never asynchronously releases GPU logic and gpu_reset never
    // asynchronously releases pixel logic.
    always @(posedge pixel_clk or posedge combined_reset) begin
        if (combined_reset)
            pixel_reset_release <= 2'b11;
        else
            pixel_reset_release <= {pixel_reset_release[0], 1'b0};
    end

    always @(posedge gpu_clk or posedge combined_reset) begin
        if (combined_reset)
            gpu_reset_release <= 2'b11;
        else
            gpu_reset_release <= {gpu_reset_release[0], 1'b0};
    end

    // Keep history live through reset. A high level spanning reset cannot
    // replay, while a rising edge during local-reset release is recorded in
    // pixel_release_pending and committed once the counter is released.
    always @(posedge pixel_clk) begin
        scale_underflow_prev <= scale_underflow;
    end

    // pixel_event_gray is registered atomically with its next binary value.
    // The Gray bus changes only one bit per episode. CDC timing must constrain
    // this bus from the pixel register to gpu_gray_sync0 to less than one pixel
    // period, preventing bits from different count increments from arriving
    // together at the first GPU synchronizer stage.
    always @(posedge pixel_clk or posedge pixel_reset_local) begin
        if (pixel_reset_local) begin
            pixel_event_count <= {EVENT_COUNTER_WIDTH{1'b0}};
            pixel_event_gray <= {EVENT_COUNTER_WIDTH{1'b0}};
        end else if (pixel_release_pending || (scale_underflow && !scale_underflow_prev)) begin
            pixel_event_count <= pixel_event_count_next;
            pixel_event_gray <= pixel_event_gray_next;
        end
    end

    // This synchronous release capture preserves a real line-scale episode
    // that begins after external reset release but before pixel_reset_local
    // drops. The two-pixel-clock release window can contain at most one such
    // episode because scale_underflow is driven by a missing display line.
    // Reset is expected to remain asserted for at least one pixel edge.
    always @(posedge pixel_clk) begin
        if (combined_reset)
            pixel_release_pending <= 1'b0;
        else if (pixel_reset_local) begin
            if (scale_underflow && !scale_underflow_prev)
                pixel_release_pending <= 1'b1;
        end else begin
            pixel_release_pending <= 1'b0;
        end
    end

    always @(posedge gpu_clk or posedge gpu_reset_local) begin
        if (gpu_reset_local) begin
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

    // Make the contract explicit at the module boundary: no pulse may be
    // visible while either external reset is asserted.
    assign underflow_pulse_gpu = combined_reset ? 1'b0 : underflow_pulse_gpu_reg;
endmodule
