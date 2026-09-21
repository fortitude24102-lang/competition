`timescale 1ns/1ps
`include "asset_protocol.vh"
module asset_udp_rx(input wire clk,input wire reset,input wire [7:0] rx_byte,input wire rx_valid,output wire rx_ready,input wire rx_last,input wire [15:0] rx_length,input wire [31:0] current_session,output reg meta_valid,input wire meta_ready,output reg [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,output reg [15:0] meta_length,meta_flags,output reg [31:0] meta_crc32,output reg payload_valid,input wire payload_ready,output reg [7:0] payload_data,output reg payload_last,output reg [31:0] error_count);
reg [5:0] pos; reg [15:0] remain; reg bad; reg [31:0] h_magic,h_session,h_asset,h_offset,h_seq,h_crc; reg [15:0] h_ver,h_type,h_len,h_flags; reg in_packet;
assign rx_ready = !payload_valid || payload_ready;
always @(posedge clk or posedge reset) begin
 if(reset) begin pos<=0;remain<=0;bad<=0;in_packet<=0;meta_valid<=0;payload_valid<=0;payload_last<=0;error_count<=0; end else begin
  if(meta_valid&&meta_ready) meta_valid<=0;
  if(payload_valid&&payload_ready) begin payload_valid<=0; if(payload_last) begin payload_last<=0;in_packet<=0;end end
  if(rx_valid&&rx_ready) begin
   if(!in_packet) begin in_packet<=1;pos<=0;remain<=rx_length;bad<=0;end
   if(pos<32) begin case(pos) 0:h_magic[31:24]<=rx_byte;1:h_magic[23:16]<=rx_byte;2:h_magic[15:8]<=rx_byte;3:h_magic[7:0]<=rx_byte;4:h_ver[15:8]<=rx_byte;5:h_ver[7:0]<=rx_byte;6:h_type[15:8]<=rx_byte;7:h_type[7:0]<=rx_byte;8:h_session[31:24]<=rx_byte;9:h_session[23:16]<=rx_byte;10:h_session[15:8]<=rx_byte;11:h_session[7:0]<=rx_byte;12:h_asset[31:24]<=rx_byte;13:h_asset[23:16]<=rx_byte;14:h_asset[15:8]<=rx_byte;15:h_asset[7:0]<=rx_byte;16:h_offset[31:24]<=rx_byte;17:h_offset[23:16]<=rx_byte;18:h_offset[15:8]<=rx_byte;19:h_offset[7:0]<=rx_byte;20:h_len[15:8]<=rx_byte;21:h_len[7:0]<=rx_byte;22:h_flags[15:8]<=rx_byte;23:h_flags[7:0]<=rx_byte;24:h_seq[31:24]<=rx_byte;25:h_seq[23:16]<=rx_byte;26:h_seq[15:8]<=rx_byte;27:h_seq[7:0]<=rx_byte;28:h_crc[31:24]<=rx_byte;29:h_crc[23:16]<=rx_byte;30:h_crc[15:8]<=rx_byte;31:h_crc[7:0]<=rx_byte;endcase end else begin payload_data<=rx_byte;payload_valid<=!bad;payload_last<=((pos-32)==h_len-1);end
   pos<=pos+1; if(rx_last) begin if(rx_length<33||rx_length>1056||h_magic!=`ASST_MAGIC||h_ver!=`ASST_VERSION||h_type!=`ASST_DATA||h_len==0||h_len>1024||h_session!=current_session||h_offset[1:0]) begin bad<=1;error_count<=error_count+1;end else if(!meta_valid) begin meta_valid<=1;meta_session<=h_session;meta_asset_id<=h_asset;meta_offset<=h_offset;meta_length<=h_len;meta_flags<=h_flags;meta_sequence<=h_seq;meta_crc32<=h_crc;end end
  end
 end
end
endmodule
