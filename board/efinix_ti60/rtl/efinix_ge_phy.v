// Preserve the official GE demo's DDIO resync half-cycle alignment.
module efinix_ge_phy (
    input rxc, input reset_async,
    input [3:0] rxd_hi_i, rxd_lo_i,
    input rx_dv_HI, rx_dv_LO,
    output tx_en_o_HI, tx_en_o_LO, txc_hi_o, txc_lo_o,
    output [3:0] txd_hi_o, txd_lo_o,
    output ge_reset, output gmii_rx_valid, output [7:0] gmii_rx_data,
    input gmii_tx_valid, input [7:0] gmii_tx_data
);
    (* async_reg = "true" *) reg [2:0] reset_sync = 3'b111;
    always @(posedge rxc or posedge reset_async)
        if (reset_async) reset_sync <= 3'b111;
        else reset_sync <= {reset_sync[1:0], 1'b0};
    assign ge_reset = reset_sync[2];
    reg [3:0] align_rxd_hi;
    reg align_rx_dv_hi;
    always @(posedge rxc or posedge ge_reset)
        if (ge_reset) begin align_rxd_hi <= 0; align_rx_dv_hi <= 0; end
        else begin align_rxd_hi <= rxd_hi_i; align_rx_dv_hi <= rx_dv_HI; end
    wire rx_valid, rx_error;
    assign gmii_rx_valid = rx_valid && !rx_error;
    assign txc_hi_o = 1'b1;
    assign txc_lo_o = 1'b0;
    util_gmii_to_rgmii u_rgmii (
        .rst_n(!ge_reset), .rgmii_rxc(rxc),
        .rgmii_rx_hi(rxd_lo_i), .rgmii_rx_lo(align_rxd_hi),
        .rgmii_rx_dv(rx_dv_LO), .rgmii_rx_er(align_rx_dv_hi),
        .rgmii_tx_ctrl_hi(tx_en_o_HI), .rgmii_tx_ctrl_lo(tx_en_o_LO),
        .rgmii_txd_lo(txd_lo_o), .rgmii_txd_hi(txd_hi_o),
        .gmii_txd(gmii_tx_data), .gmii_tx_en(gmii_tx_valid), .gmii_tx_er(1'b0),
        .gmii_tx_clk(), .gmii_crs(), .gmii_col(), .gmii_rxd(gmii_rx_data),
        .gmii_rx_dv(rx_valid), .gmii_rx_er(rx_error), .gmii_rx_clk(), .duplex_mode(1'b1)
    );
endmodule
