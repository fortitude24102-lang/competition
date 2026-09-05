`timescale 1 ps / 1ps
module dvi_encoder
(
	input           pixelclk,       // system clock
	input           rstin,          // reset
	input[7:0]      blue_din,       // Blue data in
	input[7:0]      green_din,      // Green data in
	input[7:0]      red_din,        // Red data in
	input           hsync,          // hsync data
	input           vsync,          // vsync data
	input           de,             // data enable

    output          [9:0]tmds_data0,
    output          [9:0]tmds_data1,
    output          [9:0]tmds_data2,
    output          [9:0]tmds_clk
);

wire    [9:0]   red ;
wire    [9:0]   green ;
wire    [9:0]   blue ;

encode encb (
	.clkin      (pixelclk),
	.rstin      (rstin),
	.din        (blue_din),
	.c0         (hsync),
	.c1         (vsync),
	.de         (de),
	.dout       (blue)) ;

encode encr (
	.clkin      (pixelclk),
	.rstin      (rstin),
	.din        (green_din),
	.c0         (1'b0),
	.c1         (1'b0),
	.de         (de),
	.dout       (green)) ;

encode encg (
	.clkin      (pixelclk),
	.rstin      (rstin),
	.din        (red_din),
	.c0         (1'b0),
	.c1         (1'b0),
	.de         (de),
	.dout       (red)) ;


assign tmds_data0 = blue;
assign tmds_data1 = green;
assign tmds_data2 = red;
assign tmds_clk   = 10'b1111100000;

endmodule
