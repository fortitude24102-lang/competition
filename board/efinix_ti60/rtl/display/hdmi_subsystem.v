`timescale 1ns/1ps
module hdmi_subsystem (
    input wire gpu_clk,
    input wire gpu_reset,
    input wire pixel_clk,
    input wire pixel_reset,
    input wire [15:0] gpu_pixel,
    input wire gpu_valid,
    input wire gpu_line_last,
    input wire gpu_frame_last,
    output wire gpu_ready,
    output wire [11:0] fifo_level,
    output wire vblank_gpu,
    output wire vblank,
    output wire fifo_full,
    output wire fifo_empty,
    output wire protocol_error,
    output wire [15:0] video_rgb565,
    output wire video_hs,
    output wire video_vs,
    output wire video_de,
    output wire [9:0] tmds_data0_o,
    output wire [9:0] tmds_data1_o,
    output wire [9:0] tmds_data2_o,
    output wire [9:0] tmds_clk_o,
    output wire tmds_data0_TX_OE,
    output wire tmds_data1_TX_OE,
    output wire tmds_data2_TX_OE,
    output wire tmds_clk_TX_OE,
    output wire tmds_data0_TX_RST,
    output wire tmds_data1_TX_RST,
    output wire tmds_data2_TX_RST,
    output wire tmds_clk_TX_RST
);
    wire [17:0] fifo_read_data;
    wire fifo_read_valid, fifo_read_ready;
    wire [11:0] fifo_read_level;
    wire [9:0] line_read_index;
    wire [15:0] line_pixel;
    wire line_begin, line_done, line_valid;
    wire [7:0] red, green, blue;

    pixel_async_fifo u_fifo (
        .wr_clk(gpu_clk), .wr_reset(gpu_reset),
        .wr_data({gpu_pixel, gpu_line_last, gpu_frame_last}),
        .wr_valid(gpu_valid), .wr_ready(gpu_ready), .wr_level(fifo_level),
        .rd_clk(pixel_clk), .rd_reset(pixel_reset), .rd_data(fifo_read_data),
        .rd_valid(fifo_read_valid), .rd_ready(fifo_read_ready), .rd_level(fifo_read_level),
        .full(fifo_full), .empty(fifo_empty)
    );

    display_line_buffer u_line_buffer (
        .clk(pixel_clk), .reset(pixel_reset), .input_data(fifo_read_data),
        .input_valid(fifo_read_valid), .input_ready(fifo_read_ready),
        .line_begin(line_begin), .line_done(line_done), .read_index(line_read_index),
        .read_pixel(line_pixel), .line_valid(line_valid), .protocol_error(protocol_error)
    );

    display_scale2x_1080p u_scale (
        .clk(pixel_clk), .reset(pixel_reset), .line_pixel(line_pixel), .line_valid(line_valid),
        .line_read_index(line_read_index), .line_begin(line_begin), .line_done(line_done),
        .rgb565(video_rgb565), .hs(video_hs), .vs(video_vs), .de(video_de), .vblank(vblank)
    );

    vblank_pulse_sync u_vblank_sync (
        .src_clk(pixel_clk), .src_reset(pixel_reset), .src_vblank(vblank),
        .dst_clk(gpu_clk), .dst_reset(gpu_reset), .dst_pulse(vblank_gpu)
    );

    rgb565_to_rgb888 u_rgb (
        .rgb565(video_rgb565), .red(red), .green(green), .blue(blue)
    );

    hdmi_tx_adapter u_hdmi (
        .pixelclk(pixel_clk), .rst(pixel_reset), .red(red), .green(green), .blue(blue),
        .hs(video_hs), .vs(video_vs), .de(video_de),
        .tmds_data0_o(tmds_data0_o), .tmds_data1_o(tmds_data1_o),
        .tmds_data2_o(tmds_data2_o), .tmds_clk_o(tmds_clk_o),
        .tmds_data0_TX_OE(tmds_data0_TX_OE), .tmds_data1_TX_OE(tmds_data1_TX_OE),
        .tmds_data2_TX_OE(tmds_data2_TX_OE), .tmds_clk_TX_OE(tmds_clk_TX_OE),
        .tmds_data0_TX_RST(tmds_data0_TX_RST), .tmds_data1_TX_RST(tmds_data1_TX_RST),
        .tmds_data2_TX_RST(tmds_data2_TX_RST), .tmds_clk_TX_RST(tmds_clk_TX_RST)
    );
endmodule
