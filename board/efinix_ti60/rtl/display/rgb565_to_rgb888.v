`timescale 1ns/1ps
module rgb565_to_rgb888 (
    input wire [15:0] rgb565,
    output wire [7:0] red, green, blue
);
    assign red = {rgb565[15:11], rgb565[15:13]};
    assign green = {rgb565[10:5], rgb565[10:9]};
    assign blue = {rgb565[4:0], rgb565[4:2]};
endmodule
