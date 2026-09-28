`timescale 1ns/1ps
module gpu_pixel_fill(input [15:0] fill_color, output [15:0] result_pixel);
  assign result_pixel = fill_color;
endmodule	// src/main/scala/gpu/PixelPipeExt.scala:7:7