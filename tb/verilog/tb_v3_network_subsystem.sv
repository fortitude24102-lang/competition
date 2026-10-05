`timescale 1ns/1ps
// Exercises the actual owner glue: an orphan bridge/0300 decode fails ID;
// wrong RX/reset/TX/session wiring loses a real MAC packet or its byte order.
module tb_v3_network_subsystem;
 reg gpu_clk=0,ge_clk=0,gpu_reset=1,ge_reset=1;
 always #5 gpu_clk=~gpu_clk;always #4 ge_clk=~ge_clk;
 reg [15:0] paddr=0;reg psel=0,penable=0,pwrite=0;reg [31:0] pwdata=0;
 wire [31:0] prdata;wire pready,pslverror;
 wire gmii_rx_valid,gmii_tx_valid;wire [7:0] gmii_rx_data,gmii_tx_data;
 reg [31:0] asset_session=32'h12345678;reg asset_active=0,asset_abort=0,asset_drop=0;
 wire meta_valid,payload_valid,payload_last,stream_error;reg meta_ready=1,payload_ready=1;
 wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,meta_crc32;
 wire [15:0] meta_length,meta_flags;wire [7:0] payload_data;
`ifdef V3_LEGACY_CONTROL
 efinix_asset_network #(.TX_TIMEOUT_CYCLES(20000)) dut(.*);
`else
 efinix_network_subsystem #(.TX_TIMEOUT_CYCLES(20000)) dut(.*);
`endif
 reg peer_req=0,peer_wr=0,peer_arp_req=0;reg [7:0] peer_data=0;reg [15:0] peer_length=32;
 reg [31:0] peer_ip=32'hc0a80003,board_ip=32'hc0a80002;
 wire peer_ram_req,peer_end,peer_rx_valid;wire [15:0] peer_rx_length;
 wire [7:0] peer_rx_byte;reg [10:0] peer_rx_address=0;
 mac_top peer(.gmii_tx_clk(ge_clk),.gmii_rx_clk(ge_clk),.rst_n(!ge_reset),
 .source_mac_addr(48'h020000000003),.TTL(8'd64),.source_ip_addr(peer_ip),.destination_ip_addr(board_ip),
 .udp_send_source_port(16'd8090),.udp_send_destination_port(16'd8090),
 .ram_wr_data(peer_data),.ram_wr_en(peer_wr),.udp_ram_data_req(peer_ram_req),.udp_send_data_length(peer_length),
 .udp_tx_req(peer_req),.arp_request_req(peer_arp_req),.mac_data_valid(gmii_rx_valid),.mac_send_end(peer_end),.mac_tx_data(gmii_rx_data),
 .rx_dv(gmii_tx_valid),.mac_rx_datain(gmii_tx_data),.udp_rec_ram_rdata(peer_rx_byte),.udp_rec_ram_read_addr(peer_rx_address),
 .udp_rec_data_length(peer_rx_length),.udp_rec_data_valid(peer_rx_valid),.arp_found(),.mac_not_exist());
 // Literal PC golden vector, byte zero in the low byte.
 reg [255:0] hello=256'h631a0b3e00000000000000000000000004030201785634122000010131434741;
 integer i,received_packets=0;reg [31:0] result;
 always @(posedge peer_rx_valid) received_packets=received_packets+1;
 task automatic apb(input bit write,input [15:0] addr,input [31:0] value);
 begin
  @(negedge gpu_clk);paddr=addr;pwdata=value;pwrite=write;psel=1;penable=0;
  @(negedge gpu_clk);penable=1;#1;
  if(!pready || pslverror) $fatal(1,"owner APB %h unavailable",addr);
  result=prdata;
  @(negedge gpu_clk);psel=0;penable=0;pwrite=0;
 end endtask
 task automatic send_tx(input integer length);
 integer previous_packets;
 begin
  previous_packets=received_packets;
  apb(1,16'h03c0,32'(length));
  for(i=0;i<length/4;i++) apb(1,16'(16'h0340+4*i),32'h03020100+32'h04040404*32'(i));
  apb(1,16'h0318,1);
  wait(received_packets>previous_packets);repeat(4) @(negedge ge_clk);
  if(peer_rx_length!=length+8) $fatal(1,"owner TX UDP length got %d expected %d",peer_rx_length,length+8);
  for(i=0;i<length;i++) begin peer_rx_address=11'(i);repeat(2) @(negedge ge_clk);if(peer_rx_byte!==8'(i)) $fatal(1,"owner TX byte %d",i);end
  repeat(40) @(negedge gpu_clk);
 end endtask
 initial begin
  #100;gpu_reset=0;ge_reset=0;repeat(30) @(negedge gpu_clk);
  apb(0,16'h0200,0);if(result!=32'h4e455431) $fatal(1,"resource ABI lost");
  apb(0,16'h0300,0);if(result!=32'h4d475431) $fatal(1,"management ID lost");
  // Management works without Asset DMA. Its descriptor also teaches ARP.
  send_tx(128);send_tx(32);
  // Separate deployment configuration, not unsupported vendor ARP hot-swap.
  gpu_reset=1;ge_reset=1;repeat(10) @(negedge gpu_clk);
  board_ip=32'h0a010203;peer_ip=32'h0a010204;
  gpu_reset=0;ge_reset=0;repeat(30) @(negedge gpu_clk);
  apb(1,16'h020c,board_ip);apb(1,16'h0210,peer_ip);
  send_tx(32);
  @(negedge ge_clk);peer_arp_req=1;@(negedge ge_clk);peer_arp_req=0;
  wait(!peer.mac_not_exist);repeat(300) @(negedge ge_clk);
  @(negedge ge_clk);peer_req=1;wait(peer_ram_req);@(negedge ge_clk);peer_req=0;repeat(2) @(negedge ge_clk);
  for(i=0;i<32;i++) begin peer_wr=1;peer_data=hello[i*8+:8];@(negedge ge_clk);end
  peer_wr=0;wait(peer_end);repeat(400) @(negedge gpu_clk);
  apb(0,16'h0304,0);if(!(result&1)) $fatal(1,"HELLO not routed into actual bridge");
  apb(1,16'h0308,1);apb(0,16'h0320,0);if(result!=32'h31434741) $fatal(1,"owner RX endian");
  apb(0,16'h0328,0);if(result!=32'h78563412) $fatal(1,"owner session");
  apb(1,16'h030c,1);if(meta_valid || payload_valid) $fatal(1,"management leaked into Asset DMA");
  ge_reset=1;repeat(10) @(negedge gpu_clk);ge_reset=0;repeat(40) @(negedge gpu_clk);
  apb(0,16'h0304,0);if(result&3) $fatal(1,"GE reset did not clear management snapshot");
  $display("PASS owner subsystem actual APB/resource IDs, default/configured IP MAC128/32, HELLO CDC/session, GE reset");$finish;
 end
 initial begin #600000;$fatal(1,"owner subsystem timeout, received=%0d configured=%h/%h",received_packets,board_ip,peer_ip);end
endmodule
