`timescale 1ns / 1ps  
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    ethernet_test 
//////////////////////////////////////////////////////////////////////////////////
module ethernet_test
(
 input          rst_n,
 input          clk_50m,   
 
 output [3:0]   led,
  
 output         e_mdc,
 inout          e_mdio,
 
 output [3:0]   rgmii_txd,
 output         rgmii_txctl,
 output         rgmii_txc,
 input  [3:0]   rgmii_rxd,
 input          rgmii_rxctl,
 input          rgmii_rxc
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




gmii_arbi arbi_inst
(
 .clk                (gmii_tx_clk      ),
 .rst_n              (rst_n            ),
 .speed              (speed            ),  
 .link               (link             ), 
 .pack_total_len     (pack_total_len   ), 
 .e_rst_n            (e_rst_n          ),
 .gmii_rx_dv         (gmii_rx_dv       ),
 .gmii_rxd           (gmii_rxd         ),
 .gmii_tx_en         (gmii_tx_en       ),
 .gmii_txd           (gmii_txd         ), 
 .e_rx_dv            (e_rx_dv          ),
 .e_rxd              (e_rxd            ),
 .e_tx_en            (e_tx_en          ),
 .e_txd              (e_txd            )

 
);



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
	
util_gmii_to_rgmii util_gmii_to_rgmii_m0
(
 .rst_n                  (rst_n           ),
 
 .rgmii_td               (rgmii_txd       ),
 .rgmii_tx_ctl           (rgmii_txctl     ),
 .rgmii_txc              (rgmii_txc       ),
 .rgmii_rd               (rgmii_rxd       ),
 .rgmii_rx_ctl           (rgmii_rxctl     ),
 .rgmii_rxc              (rgmii_rxc       ),
                                          
 .gmii_txd               (e_txd           ),
 .gmii_tx_en             (e_tx_en         ),
 .gmii_tx_er             (1'b0            ),
 .gmii_tx_clk            (gmii_tx_clk     ),
 .gmii_crs               (gmii_crs        ),
 .gmii_col               (gmii_col        ),
 .gmii_rxd               (gmii_rxd        ),
 .gmii_rx_dv             (gmii_rx_dv      ),
 .gmii_rx_er             (gmii_rx_er      ),
 .gmii_rx_clk            (gmii_rx_clk     ),
 .duplex_mode            (duplex_mode     )
);

	
mac_test mac_test0
(
 .gmii_tx_clk            (gmii_tx_clk     ),
 .gmii_rx_clk            (gmii_rx_clk     ),
 .rst_n                  (e_rst_n         ),

 .pack_total_len         (pack_total_len  ),
 .gmii_rx_dv             (e_rx_dv         ),
 .gmii_rxd               (e_rxd           ),
 .gmii_tx_en             (gmii_tx_en      ),
 .gmii_txd               (gmii_txd        )
 
); 

	 
    
endmodule
