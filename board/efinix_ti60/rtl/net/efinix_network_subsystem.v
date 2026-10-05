`timescale 1ns/1ps
// Owner-only glue: existing resource ABI + opt-in management APB window.
module efinix_network_subsystem #(
 parameter integer TX_TIMEOUT_CYCLES=2500000
) (
 input wire gpu_clk,gpu_reset,ge_clk,ge_reset,
 input wire [15:0] paddr,input wire psel,penable,pwrite,input wire [31:0] pwdata,
 output wire [31:0] prdata,output wire pready,pslverror,
 input wire gmii_rx_valid,input wire [7:0] gmii_rx_data,
 output wire gmii_tx_valid,output wire [7:0] gmii_tx_data,
 input wire [31:0] asset_session,input wire asset_active,asset_abort,asset_drop,
 output wire meta_valid,input wire meta_ready,
 output wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,meta_crc32,
 output wire [15:0] meta_length,meta_flags,
 output wire payload_valid,input wire payload_ready,
 output wire [7:0] payload_data,output wire payload_last,stream_error
);
 wire control_select=paddr[15:8]==8'h03;
 wire [31:0] asset_prdata,control_prdata;
 wire asset_pready,asset_pslverror,control_pready,control_pslverror;
 assign prdata=control_select?control_prdata:asset_prdata;
 assign pready=control_select?control_pready:asset_pready;
 assign pslverror=control_select?control_pslverror:asset_pslverror;
 wire [7:0] control_rx_byte;wire control_rx_valid,control_rx_ready,control_rx_last;
 wire [15:0] control_rx_length,tx_length;
 wire [1023:0] tx_packet;wire tx_valid,tx_ready,tx_done,tx_error;
 wire [255:0] packet;wire packet_valid,packet_ready;
 wire [31:0] arrival_ms,drop_count,ge_time_ms;
 wire [31:0] configured_local_ip,configured_peer_ip,tx_local_ip,tx_peer_ip;
 wire reset=gpu_reset|ge_reset;
 reg [1:0] ge_reset_pipe;
 always @(posedge ge_clk or posedge reset)
  if(reset) ge_reset_pipe<=2'b11;else ge_reset_pipe<={ge_reset_pipe[0],1'b0};
 efinix_asset_network_shared #(.TX_TIMEOUT_CYCLES(TX_TIMEOUT_CYCLES),.ENABLE_CONTROL(1)) u_shared(
 .gpu_clk(gpu_clk),.gpu_reset(gpu_reset),.ge_clk(ge_clk),.ge_reset(ge_reset),
 .paddr(paddr),.psel(psel&&!control_select),.penable(penable),.pwrite(pwrite),.pwdata(pwdata),
 .prdata(asset_prdata),.pready(asset_pready),.pslverror(asset_pslverror),
 .gmii_rx_valid(gmii_rx_valid),.gmii_rx_data(gmii_rx_data),.gmii_tx_valid(gmii_tx_valid),.gmii_tx_data(gmii_tx_data),
 .asset_session(asset_session),.asset_active(asset_active),.asset_abort(asset_abort),.asset_drop(asset_drop),
 .meta_valid(meta_valid),.meta_ready(meta_ready),.meta_session(meta_session),.meta_asset_id(meta_asset_id),
 .meta_offset(meta_offset),.meta_sequence(meta_sequence),.meta_crc32(meta_crc32),.meta_length(meta_length),.meta_flags(meta_flags),
 .payload_valid(payload_valid),.payload_ready(payload_ready),.payload_data(payload_data),.payload_last(payload_last),.stream_error(stream_error),
 .control_rx_byte(control_rx_byte),.control_rx_valid(control_rx_valid),.control_rx_ready(control_rx_ready),
 .control_rx_last(control_rx_last),.control_rx_length(control_rx_length),
 .control_tx_valid(tx_valid),.control_tx_ready(tx_ready),.control_tx_packet(tx_packet),.control_tx_length(tx_length),
 .control_tx_session({tx_packet[71:64],tx_packet[79:72],tx_packet[87:80],tx_packet[95:88]}),
 .control_tx_ports(32'h1f9a1f9a),.control_tx_peer_ip(tx_peer_ip),.control_tx_local_ip(tx_local_ip),
 .control_tx_done(tx_done),.control_tx_error(tx_error),
 .configured_local_ip(configured_local_ip),.configured_peer_ip(configured_peer_ip));
 control_udp_rx u_control_rx(.clk(ge_clk),.reset(ge_reset_pipe[1]),
 .rx_byte(control_rx_byte),.rx_valid(control_rx_valid),.rx_ready(control_rx_ready),
 .rx_last(control_rx_last),.rx_length(control_rx_length),.current_ms(ge_time_ms),
 .packet(packet),.packet_valid(packet_valid),.packet_ready(packet_ready),.arrival_ms(arrival_ms),.drop_count(drop_count));
 net_control_bridge u_control_bridge(.gpu_clk(gpu_clk),.gpu_reset(gpu_reset),.ge_clk(ge_clk),.ge_reset(ge_reset),
 .paddr(paddr),.psel(psel&&control_select),.penable(penable),.pwrite(pwrite),.pwdata(pwdata),
 .prdata(control_prdata),.pready(control_pready),.pslverror(control_pslverror),
 .rx_packet(packet),.rx_packet_valid(packet_valid),.rx_packet_ready(packet_ready),.rx_arrival_ms(arrival_ms),
 .rx_drop_count(drop_count),.ge_time_ms(ge_time_ms),.tx_packet(tx_packet),.tx_packet_valid(tx_valid),
 .tx_packet_ready(tx_ready),.tx_length(tx_length),.tx_done(tx_done),.tx_error(tx_error),
 .configured_local_ip(configured_local_ip),.configured_peer_ip(configured_peer_ip),
 .tx_local_ip(tx_local_ip),.tx_peer_ip(tx_peer_ip));
endmodule
