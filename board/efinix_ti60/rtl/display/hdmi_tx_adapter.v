`timescale 1ns/1ps
module hdmi_tx_adapter (
    input wire pixelclk, rst,
    input wire [7:0] red, green, blue,
    input wire hs, vs, de,
    output wire [9:0] tmds_data0_o, tmds_data1_o, tmds_data2_o, tmds_clk_o,
    output wire tmds_data0_TX_OE, tmds_data1_TX_OE, tmds_data2_TX_OE, tmds_clk_TX_OE,
    output wire tmds_data0_TX_RST, tmds_data1_TX_RST, tmds_data2_TX_RST, tmds_clk_TX_RST
);
    wire [9:0] data0, data1, data2, clock_word;
    dvi_encoder encoder (
        .pixelclk(pixelclk), .rstin(rst),
        .red_din(red), .green_din(green), .blue_din(blue),
        .hsync(hs), .vsync(vs), .de(de),
        .tmds_data0(data0), .tmds_data1(data1), .tmds_data2(data2),
        .tmds_clk(clock_word)
    );
    // Match vendor/hdmi_tx/rtl/top.v at the Efinity LVDS serializer boundary.
    assign tmds_data0_o = ~data0; // Blue, with HS/VS control tokens.
    assign tmds_data1_o = ~data1; // Green.
    assign tmds_data2_o = ~data2; // Red.
    assign tmds_clk_o = ~clock_word;
    assign {tmds_data0_TX_OE,tmds_data1_TX_OE,tmds_data2_TX_OE,tmds_clk_TX_OE} = 4'hf;
    assign {tmds_data0_TX_RST,tmds_data1_TX_RST,tmds_data2_TX_RST,tmds_clk_TX_RST} = 4'h0;
endmodule
