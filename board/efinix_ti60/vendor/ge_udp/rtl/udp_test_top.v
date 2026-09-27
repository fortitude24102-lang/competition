//=================================================================
//
//  Copyright (C) 2022 Persion All rights reserved.
//  文件名称：top.v
//  创 建 者：Ramsey Wang
//  创建日期：2022.04.01
//  描    述：led test
//
//=================================================================


module udp_test_top
(

    ////////////////////////    CLOCK & PLL     ////////////////////////
       input                rst_n,
       input  [47:0]        source_mac_addr ,       //source mac address
       input  [7:0]         TTL,
       input  [31:0]        source_ip_addr,
       input  [31:0]        destination_ip_addr,
       input  [15:0]        udp_send_source_port,
       input  [15:0]        udp_send_destination_port,
  //ETH
   input			rxc,   
   input  [3:0]             rxd_hi_i    ,
   input  [3:0]             rxd_lo_i    ,
   input 			rx_dv_HI    ,
   input 			rx_dv_LO    ,
   output 			tx_en_o_HI  ,
   output 		       tx_en_o_LO  ,
   output                   txc_hi_o,
   output                   txc_lo_o,
   output 	  [3:0]       txd_hi_o,
   output 	  [3:0]       txd_lo_o,

  output 			  mdc_o,
   output                     mdio_o,
   output                     mdio_oe,     
   input                      mdio_i,     
   output 			  phy_rst_n
);

  

wire   [ 7:0]   gmii_txd     ;
wire            gmii_tx_en   ;
wire            gmii_tx_er   ;
wire            gmii_tx_clk  ;
wire            gmii_crs     ;
wire            gmii_col     ;
wire   [ 7:0]   gmii_rxd     ;
wire            gmii_rx_dv   ;
wire            gmii_rx_er   ;
wire            gmii_rx_clk  ;

wire  [31:0]    pack_total_len ;
wire            duplex_mode;     // 1 full, 0 half

assign duplex_mode = 1'b1;

wire [1:0]      speed      ;
wire            link       ;
wire            e_rx_dv    ;
wire [7:0]      e_rxd      ;
wire            e_tx_en    ;
wire [7:0]      e_txd      ;
wire            e_rst_n    ;



assign phy_rst_n = 1'b1;
assign txc_hi_o = 1'b1;
assign txc_lo_o = 1'b0;



/*
smi_config  smi_config_inst
       (
        .clk         (clk_50m  ),
        .rst_n       (rst_n    ),		 
        .mdc         (e_mdc    ),
        .mdio        (e_mdio   ),
        .speed       (speed    ),
        .link        (link     ),
        .led         (led      )	
       );
*/


	
mac_test mac_test0
(
/*I*/.source_mac_addr             (source_mac_addr          ),//(48'h00_0a_35_01_fe_c0)   ,       //source mac address
/*I*/.TTL                         (TTL                      ),//(8'h80),
/*I*/.source_ip_addr              (source_ip_addr           ),//(32'hc0a80002),//192.168.0.2
/*I*/.destination_ip_addr         (destination_ip_addr      ),//(32'hc0a80003),//192.168.0.3
/*I*/.udp_send_source_port        (udp_send_source_port     ),//(16'h1f90),//8080
/*I*/.udp_send_destination_port   (udp_send_destination_port),//(16'h1f90),//8080
 /*I*/.gmii_tx_clk        (gmii_tx_clk     ),
 /*I*/.gmii_rx_clk        (gmii_rx_clk     ),
 /*I*/.rst_n              (e_rst_n         ),
 /*I*/.pack_total_len     (pack_total_len  ),
 /*I*/.gmii_rx_dv         (e_rx_dv         ),
 /*I*/.gmii_rxd           (e_rxd           ),
 /*O*/.gmii_tx_en         (gmii_tx_en      ),
 /*O*/.gmii_txd           (gmii_txd        )
 
); 

gmii_arbi arbi_inst
(
 /*I*/.clk                (gmii_tx_clk      ),
 /*I*/.rst_n              (rst_n            ),
 /*I*/.speed              (2'b10),//(speed            ),  
 /*I*/.link               (1'b1),//(link             ), 
 /*O*/.pack_total_len     (pack_total_len   ), 
 /*O*/.e_rst_n            (e_rst_n          ),

 /*I*/.gmii_rx_dv         (gmii_rx_dv       ),
 /*I*/.gmii_rxd           (gmii_rxd         ),

 /*I*/.gmii_tx_en         (gmii_tx_en       ),
 /*I*/.gmii_txd           (gmii_txd         ), 

 /*O*/.e_rx_dv            (e_rx_dv          ),
 /*O*/.e_rxd              (e_rxd            ),
 /*O*/.e_tx_en            (e_tx_en          ),
 /*O*/.e_txd              (e_txd            )
);

reg [3:0] align_rxd_hi;
wire [3:0] align_rxd_lo;
reg       align_rx_dv_hi;
wire      align_rx_dv_lo;
always @(posedge rxc)begin
       
       
       align_rxd_hi     <= rxd_hi_i;
       align_rx_dv_hi <= rx_dv_HI;
end
assign align_rxd_lo = rxd_lo_i;
assign align_rx_dv_lo = rx_dv_LO;
util_gmii_to_rgmii util_gmii_to_rgmii_m0
(
 /*I*/.rst_n                  (rst_n           ),     
 //interface RXD
 /*i*/.rgmii_rxc              (rxc         ),
 /*i*/.rgmii_rx_hi            (align_rxd_lo),//(rxd_hi_i        ),
 /*i*/.rgmii_rx_lo            (align_rxd_hi),//(rxd_lo_i        ),
 /*i*/.rgmii_rx_dv            (align_rx_dv_lo),//(rx_dv_HI        ),
 /*i*/.rgmii_rx_er            (align_rx_dv_hi),//(rx_dv_LO        ),
 
 //interface TXD
 /*o*/.rgmii_tx_ctrl_hi       (  tx_en_o_HI    ),
 /*o*/.rgmii_tx_ctrl_lo       (  tx_en_o_LO    ),
 /*o*/.rgmii_txd_lo           (  txd_lo_o      ),
 /*o*/.rgmii_txd_hi           (  txd_hi_o      ),

 //tx
 /*I*/.gmii_txd               (e_txd           ),
 /*I*/.gmii_tx_en             (e_tx_en         ),
 /*I*/.gmii_tx_er             (1'b0            ),
 /*o*/.gmii_tx_clk            (gmii_tx_clk     ),
//rx
 /*o*/.gmii_crs               (gmii_crs        ),
 /*o*/.gmii_col               (gmii_col        ),
 /*o*/.gmii_rxd               (gmii_rxd        ),
 /*o*/.gmii_rx_dv             (gmii_rx_dv      ),
 /*o*/.gmii_rx_er             (gmii_rx_er      ),
 /*o*/.gmii_rx_clk            (gmii_rx_clk     ),
 .duplex_mode                 (duplex_mode     )
);



//==================================================================== 
//
//====================================================================


 
endmodule
