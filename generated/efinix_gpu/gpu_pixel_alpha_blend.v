`timescale 1ns/1ps
module gpu_pixel_alpha_blend(input [15:0] foreground, input [15:0] background, input [7:0] alpha, output [15:0] result_pixel);
  // Global Alpha in native RGB565 5/6/5 channels using the frozen formula
  //   out = (fg*alpha + bg*(255-alpha) + 127) / 255
  // The divide by 255 is realized exactly as (x + (x>>8) + 1) >> 8, valid for x < 65280.
  wire [7:0] inv_alpha = 8'd255 - alpha;
  wire [12:0] r_fg  = foreground[15:11] * alpha;        // 5b * 8b -> 13b
  wire [12:0] r_bg  = background[15:11] * inv_alpha;
  wire [13:0] r_sum = r_fg + r_bg + 14'd127;
  wire [13:0] g_fg  = foreground[10:5] * alpha;         // 6b * 8b -> 14b
  wire [13:0] g_bg  = background[10:5] * inv_alpha;
  wire [14:0] g_sum = g_fg + g_bg + 15'd127;
  wire [12:0] b_fg  = foreground[4:0] * alpha;
  wire [12:0] b_bg  = background[4:0] * inv_alpha;
  wire [13:0] b_sum = b_fg + b_bg + 14'd127;
  wire [13:0] r_rounded = r_sum + (r_sum >> 8) + 14'd1;
  wire [14:0] g_rounded = g_sum + (g_sum >> 8) + 15'd1;
  wire [13:0] b_rounded = b_sum + (b_sum >> 8) + 14'd1;
  wire [4:0] r_out = r_rounded[12:8];
  wire [5:0] g_out = g_rounded[13:8];
  wire [4:0] b_out = b_rounded[12:8];
  assign result_pixel = {r_out, g_out, b_out};
endmodule	// src/main/scala/gpu/PixelPipeExt.scala:7:7