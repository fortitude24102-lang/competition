`timescale 1ns/1ps
module gpu_pixel_copy(input [15:0] foreground, output [15:0] result_pixel);
  assign result_pixel = foreground;
endmodule	// src/main/scala/gpu/PixelPipeExt.scala:7:7