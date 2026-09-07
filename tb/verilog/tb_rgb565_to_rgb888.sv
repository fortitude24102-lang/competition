`timescale 1ns/1ps
module tb_rgb565_to_rgb888;
    reg [15:0] rgb565;
    wire [7:0] red, green, blue;
    integer i, r, g, b;
    rgb565_to_rgb888 dut (.rgb565(rgb565), .red(red), .green(green), .blue(blue));
    task automatic check(input [15:0] pixel, input [23:0] expected);
        rgb565 = pixel;
        #1;
        if ({red,green,blue} !== expected)
            $fatal(1, "RGB565 %h: got %h expected %h", pixel, {red,green,blue}, expected);
    endtask
    initial begin
        // Catch channel swaps, truncation, and zero-fill instead of bit replication.
        check(16'hf800, 24'hff0000);
        check(16'h07e0, 24'h00ff00);
        check(16'h001f, 24'h0000ff);
        check(16'hffff, 24'hffffff);
        check(16'h0000, 24'h000000);
        for (i=0; i<65536; i=i+1) begin
            r = i / 2048;
            g = (i / 32) % 64;
            b = i % 32;
            // Arithmetic oracle, independent of the DUT's bit concatenations.
            check(16'(i), 24'((r*8+r/4)*65536+(g*4+g/16)*256+b*8+b/4));
        end
        $display("PASS RGB565: primary colors, white, black, all 65536 values");
        $finish;
    end
endmodule
