//=================================================================
//
//  Copyright (C) 2022 Persion All rights reserved.
//  文件名称：top.v
//  创 建 者：Ramsey Wang
//  创建日期：2022.04.01
//  描    述：led test
//
//=================================================================


module top
(

  (* syn_peri_port = 0 *) input ge_0_gclk_pll_LOCKED,
  (* syn_peri_port = 0 *) input FB,
  (* syn_peri_port = 0 *) input rxc,
  
  (* syn_peri_port = 0 *) input rx_dv_HI,
  (* syn_peri_port = 0 *) input rx_dv_LO,
  (* syn_peri_port = 0 *) input [3:0] rxd_hi_i,
  (* syn_peri_port = 0 *) input [3:0] rxd_lo_i,
  (* syn_peri_port = 0 *) output phy_rst_n,
  (* syn_peri_port = 0 *) output ge_rx_pll_RSTN,
  (* syn_peri_port = 0 *) output mdc_o,
  (* syn_peri_port = 0 *) input mdio_i,
  (* syn_peri_port = 0 *) output mdio_o,
  (* syn_peri_port = 0 *) output mdio_oe,
  (* syn_peri_port = 0 *) output tx_en_o_HI,
  (* syn_peri_port = 0 *) output tx_en_o_LO,
  (* syn_peri_port = 0 *) output txc_hi_o,
  (* syn_peri_port = 0 *) output txc_lo_o,
  (* syn_peri_port = 0 *) output [3:0] txd_hi_o,
  (* syn_peri_port = 0 *) output [3:0] txd_lo_o,
  (* syn_peri_port = 0 *) output osc_inst1_ENA,
  output led_d0
);

reg [25:0] cnt ;
localparam cnt_1s = 125000000-1;
reg  rxc_toggle = 'd0;
always @( posedge rxc)
begin
       if( cnt == cnt_1s ) begin 
              cnt <= 'd0;
              rxc_toggle <= ~rxc_toggle;
       end  else 
              cnt <= cnt + 1 ;
end 

assign led_d0 = rxc_toggle;
assign ge_rx_pll_RSTN = 1'b1;
assign osc_inst1_ENA = 1'b1;
udp_test_top  u0_udp_test_top (
       .rst_n(ge_0_gclk_pll_LOCKED),
       .rxc(rxc),
  /*I*/.source_mac_addr            (48'h00_0a_35_01_fe_c0)   ,       //source mac address
  /*I*/.TTL                        (8'h80),
  /*I*/.source_ip_addr             (32'hc0a80002),//192.168.0.2
  /*I*/.destination_ip_addr        (32'hc0a80003),//192.168.0.3
  /*I*/.udp_send_source_port       (16'h1f90),//8080
  /*I*/.udp_send_destination_port  (16'h1f90),//8080
       .rxd_hi_i(rxd_hi_i),
       .rxd_lo_i(rxd_lo_i),
       .rx_dv_HI(rx_dv_HI),
       .rx_dv_LO(rx_dv_LO),
       .tx_en_o_HI(tx_en_o_HI),
       .tx_en_o_LO(tx_en_o_LO),
       .txc_hi_o(txc_hi_o),
       .txc_lo_o(txc_lo_o),
       .txd_hi_o(txd_hi_o),
       .txd_lo_o(txd_lo_o),
       .mdc_o(mdc_o),
       .mdio_o(mdio_o),
       .mdio_oe(mdio_oe),
       .mdio_i(mdio_i),
       .phy_rst_n(phy_rst_n)
     );


    

endmodule
