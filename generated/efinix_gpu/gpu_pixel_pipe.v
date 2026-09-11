`timescale 1ns/1ps
`include "gpu_pixel_contract.vh"
module gpu_pixel_pipe(
  input clock, reset, in_valid,
  output in_ready,
  input [2:0] op,
  input [15:0] foreground, background, fill_color, color_key,
  input [7:0] alpha,
  output reg out_valid,
  input out_ready,
  output reg [15:0] result_pixel,
  output reg write_enable
);
  wire [15:0] copy_pixel, fill_pixel, color_key_pixel, alpha_pixel;
  wire color_key_write;
  gpu_pixel_copy copy_unit(.foreground(foreground), .result_pixel(copy_pixel));
  gpu_pixel_fill fill_unit(.fill_color(fill_color), .result_pixel(fill_pixel));
  gpu_pixel_color_key color_key_unit(.foreground(foreground), .color_key(color_key),
                                     .result_pixel(color_key_pixel), .write_enable(color_key_write));
  gpu_pixel_alpha_blend alpha_unit(.foreground(foreground), .background(background), .alpha(alpha),
                                   .result_pixel(alpha_pixel));
  // One elastic stage; synchronous active-high reset discards any pending beat.
  assign in_ready = !reset && (!out_valid || out_ready);
  always @(posedge clock) begin
    if (reset) begin
      out_valid <= 1'b0;
      result_pixel <= 16'b0;
      write_enable <= 1'b0;
    end else if (in_ready) begin
      out_valid <= in_valid;
      write_enable <= in_valid && ((op == `GPU_PIXEL_FILL) ||
                                   (op == `GPU_PIXEL_COPY) ||
                                   ((op == `GPU_PIXEL_COLOR_KEY) && color_key_write) ||
                                   (op == `GPU_PIXEL_ALPHA));
      case (op)
        `GPU_PIXEL_FILL: result_pixel <= fill_pixel;
        `GPU_PIXEL_COPY: result_pixel <= copy_pixel;
        `GPU_PIXEL_COLOR_KEY: result_pixel <= color_key_pixel;
        `GPU_PIXEL_ALPHA: result_pixel <= alpha_pixel;
        default: result_pixel <= 16'b0;
      endcase
    end
  end
endmodule	// src/main/scala/gpu/PixelPipeExt.scala:7:7