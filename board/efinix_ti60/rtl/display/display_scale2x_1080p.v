`timescale 1ns/1ps
module display_scale2x_1080p (
    input wire clk,
    input wire reset,
    input wire [15:0] line_pixel,
    input wire line_valid,
    output wire [9:0] line_read_index,
    output wire line_begin,
    output wire line_done,
    output wire [15:0] rgb565,
    output wire hs,
    output wire vs,
    output wire de,
    output wire vblank,
    output wire underflow
);
    reg [11:0] h_count;
    reg [10:0] v_count;
    wire h_active = h_count >= 12'd192 && h_count < 12'd2112;
    wire v_active = v_count >= 11'd41 && v_count < 11'd1121;
    wire [11:0] active_x = h_count - 12'd192;
    wire [10:0] active_y = v_count - 11'd41;
    wire scaled_active = h_active && v_active && active_x >= 12'd320 && active_x < 12'd1600 &&
        active_y >= 11'd60 && active_y < 11'd1020;
    wire [10:0] scaled_y = active_y - 11'd60;
    wire [11:0] next_h_count = h_count == 12'd2199 ? 12'd0 : h_count + 1'b1;
    wire [11:0] read_scaled_x = next_h_count - 12'd512;
    wire next_scaled_horizontal = next_h_count >= 12'd512 && next_h_count < 12'd1792;

    assign hs = h_count < 12'd44;
    assign vs = v_count < 11'd5;
    assign de = h_active && v_active;
    assign vblank = !v_active;
    assign line_read_index = next_scaled_horizontal ? read_scaled_x[10:1] : 10'd0;
    assign line_begin = h_count == 0 && v_active && active_y >= 11'd60 && active_y < 11'd1020 && !scaled_y[0];
    assign line_done = h_count == 12'd2199 && v_active && active_y >= 11'd60 && active_y < 11'd1020 && scaled_y[0];
    assign rgb565 = scaled_active && line_valid ? line_pixel : 16'h0000;
    // Underflow: the scaled region needs a source line but none is ready; the
    // same condition that forces rgb565 to the fixed black background.
    assign underflow = scaled_active && !line_valid;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            h_count <= 0;
            v_count <= 0;
        end else if (h_count == 12'd2199) begin
            h_count <= 0;
            if (v_count == 11'd1124)
                v_count <= 0;
            else
                v_count <= v_count + 1'b1;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end
endmodule
