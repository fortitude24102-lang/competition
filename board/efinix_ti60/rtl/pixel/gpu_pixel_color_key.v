`timescale 1ns/1ps
module gpu_pixel_color_key(input [15:0] foreground, input [15:0] color_key, output [15:0] result_pixel, output write_enable);
  // Transparent-color hit (foreground == color_key) suppresses the write-back.
  assign result_pixel = foreground;
  assign write_enable = (foreground != color_key);
endmodule
