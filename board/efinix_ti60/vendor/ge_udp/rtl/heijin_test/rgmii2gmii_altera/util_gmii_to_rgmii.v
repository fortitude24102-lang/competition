`timescale 1 ns/1 ns
module util_gmii_to_rgmii 
(
  input                      rst_n,             //!复位信号                
  input                      rgmii_rxc,         //!RGMI RX CLK

  input  [ 3:0]              rgmii_rx_hi      ,//!RGMII RXD HIGH
  input  [ 3:0]              rgmii_rx_lo      ,//!RGMII RXD LOW
  input                      rgmii_rx_dv      ,//!RGMII RX DV
  input                      rgmii_rx_er      ,//!RGMII RX ERROR

  output reg                 rgmii_tx_ctrl_hi ,//!RGMII TX HIGH
  output reg                 rgmii_tx_ctrl_lo ,//!RGMII TX LOW
  output reg   [ 3:0]        rgmii_txd_lo     ,//!RGMII TXD LOW
  output reg   [ 3:0]        rgmii_txd_hi     ,//!RGMII TXD HIGH
                        
  input        [ 7:0]        gmii_txd         ,//!
  input                      gmii_tx_en       ,//!
  input                      gmii_tx_er       ,//!
  output                     gmii_tx_clk      ,//!
  output reg                 gmii_crs         ,//!
  output reg                 gmii_col         ,//!
  output reg [ 7:0]          gmii_rxd         ,//!
  output reg                 gmii_rx_dv       ,//!
  output reg                 gmii_rx_er       ,//!
  output                     gmii_rx_clk      ,//!
  input                      duplex_mode       //!
  );
    


                        
reg   [ 7:0]            gmii_txd_r        ;
reg                     gmii_tx_en_r      ;
reg                     gmii_tx_er_r      ;


assign gmii_rx_clk = rgmii_rxc;   
assign gmii_tx_clk  = gmii_rx_clk;
 
always @(posedge gmii_rx_clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
      gmii_rxd   <= 8'd0 ;
      gmii_rx_dv <= 1'b0 ;
      gmii_rx_er <= 1'b0 ;
    end else begin
      gmii_rxd   <= {rgmii_rx_hi,rgmii_rx_lo};//gmii_rxd_s;
      gmii_rx_dv <= rgmii_rx_dv;
      gmii_rx_er <= rgmii_rx_dv ^ rgmii_rx_er;
    end
end

always @(posedge gmii_tx_clk or negedge rst_n) 
begin
  if (rst_n == 1'b0) begin
    gmii_txd_r   <= 8'd0;
    gmii_tx_en_r <= 1'b0;
    gmii_tx_er_r <= 1'b0;
  end else begin
    gmii_txd_r   <= gmii_txd;
    gmii_tx_en_r <= gmii_tx_en;
    gmii_tx_er_r <= gmii_tx_er;
  end
end
always @(posedge gmii_tx_clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
      rgmii_tx_ctrl_lo   <= 1'b0 ;
      rgmii_tx_ctrl_hi  <= 1'b0 ;
      rgmii_txd_lo       <= 4'd0 ;
      rgmii_txd_hi      <= 4'd0 ;   
      gmii_col           <= 1'b0 ;
      gmii_crs           <= 1'b0 ;
    end else begin
      rgmii_tx_ctrl_lo   <= gmii_tx_en_r ^ gmii_tx_er_r;       //TX_ER
      rgmii_tx_ctrl_hi   <= gmii_tx_en_r ;                     //TX_EN
      rgmii_txd_lo       <= gmii_txd_r[7:4] ;                  
      rgmii_txd_hi      <= gmii_txd_r[3:0] ;
      gmii_col           <= duplex_mode ? 1'b0 : (gmii_tx_en_r| gmii_tx_er_r) & ( gmii_rx_dv | gmii_rx_er) ;
      gmii_crs           <= duplex_mode ? 1'b0 : (gmii_tx_en_r| gmii_tx_er_r | gmii_rx_dv | gmii_rx_er);
    end
end



endmodule
