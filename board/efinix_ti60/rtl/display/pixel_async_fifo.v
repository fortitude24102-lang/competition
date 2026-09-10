`timescale 1ns/1ps
module pixel_async_fifo #(
    parameter DATA_WIDTH = 18,
    parameter DEPTH = 2048,
    parameter ADDRESS_WIDTH = 11
) (
    input wire wr_clk,
    input wire wr_reset,
    input wire [DATA_WIDTH-1:0] wr_data,
    input wire wr_valid,
    output wire wr_ready,
    output wire [11:0] wr_level,
    input wire rd_clk,
    input wire rd_reset,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire rd_valid,
    input wire rd_ready,
    output wire [11:0] rd_level,
    output wire full,
    output wire empty
);
    wire [ADDRESS_WIDTH:0] vendor_wr_level;
    wire [ADDRESS_WIDTH:0] vendor_rd_level;
    wire vendor_rd_valid, reset_busy;
    wire unused_almost_full, unused_prog_full, unused_overflow, unused_wr_ack;
    wire unused_almost_empty, unused_prog_empty, unused_underflow;

    assign wr_ready = !full && !reset_busy;
    assign rd_valid = vendor_rd_valid && !reset_busy;
    assign wr_level = vendor_wr_level;
    assign rd_level = vendor_rd_level;

    efx_fifo_wrapper #(
        .FAMILY("TITANIUM"), .SYNC_CLK(0), .MODE("FWFT"),
        .DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .OUTPUT_REG(0),
        .OPTIONAL_FLAGS(1), .HANDSHAKE_FLAG(1), .PIPELINE_REG(1),
        .WADDR_WIDTH(ADDRESS_WIDTH), .RADDR_WIDTH(ADDRESS_WIDTH)
    ) u_vendor_fifo (
        .a_rst_i(wr_reset | rd_reset), .a_wr_rst_i(wr_reset), .a_rd_rst_i(rd_reset),
        .clk_i(wr_clk), .wr_clk_i(wr_clk), .rd_clk_i(rd_clk),
        .wr_en_i(wr_valid && wr_ready), .rd_en_i(rd_valid && rd_ready), .wdata(wr_data),
        .almost_full_o(unused_almost_full), .prog_full_o(unused_prog_full), .full_o(full),
        .overflow_o(unused_overflow), .wr_ack_o(unused_wr_ack), .datacount_o(),
        .wr_datacount_o(vendor_wr_level), .empty_o(empty),
        .almost_empty_o(unused_almost_empty), .prog_empty_o(unused_prog_empty),
        .underflow_o(unused_underflow), .rd_valid_o(vendor_rd_valid), .rdata(rd_data),
        .rd_datacount_o(vendor_rd_level), .rst_busy(reset_busy)
    );
endmodule
