`timescale 1ns/1ps
`include "asset_protocol.vh"
module asset_udp_rx(input wire clk,input wire reset,input wire [7:0] rx_byte,input wire rx_valid,output wire rx_ready,input wire rx_last,input wire [15:0] rx_length,input wire [31:0] current_session,output reg meta_valid,input wire meta_ready,output reg [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,output reg [15:0] meta_length,meta_flags,output reg [31:0] meta_crc32,output reg payload_valid,input wire payload_ready,output reg [7:0] payload_data,output reg payload_last,output reg [31:0] error_count);
localparam IDLE=0,RECV=1,WAIT_META=2,SEND=3; reg [2:0] state; reg [10:0] count,send_index; reg [15:0] packet_length; reg [7:0] mem[0:1055]; reg [31:0] hm,hs,ha,ho,hq,hc; reg [15:0] hv,ht,hl,hf;
assign rx_ready=(state==IDLE||state==RECV);
wire header_ok=(packet_length>=33&&packet_length<=1056&&hm==`ASST_MAGIC&&hv==`ASST_VERSION&&ht==`ASST_DATA&&hl!=0&&hl<=1024&&hs==current_session&&(ho[1:0]==0)&&hf[15:2]==0);
always @(posedge clk or posedge reset) begin
 if(reset) begin state<=IDLE;count<=0;send_index<=0;meta_valid<=0;payload_valid<=0;payload_last<=0;error_count<=0; end else begin
  if(meta_valid&&meta_ready) meta_valid<=0;
  if(payload_valid&&payload_ready) begin payload_valid<=0; if(payload_last) begin payload_last<=0;state<=IDLE;end end
  case(state)
   IDLE: if(rx_valid) begin state<=RECV;count<=1;packet_length<=rx_length;mem[0]<=rx_byte;end
   RECV: if(rx_valid) begin if(count<1056) mem[count]<=rx_byte; count<=count+1; case(count) 1:hm[23:16]<=rx_byte;2:hm[15:8]<=rx_byte;3:hm[7:0]<=rx_byte;4:hv[15:8]<=rx_byte;5:hv[7:0]<=rx_byte;6:ht[15:8]<=rx_byte;7:ht[7:0]<=rx_byte;8:hs[31:24]<=rx_byte;9:hs[23:16]<=rx_byte;10:hs[15:8]<=rx_byte;11:hs[7:0]<=rx_byte;12:ha[31:24]<=rx_byte;13:ha[23:16]<=rx_byte;14:ha[15:8]<=rx_byte;15:ha[7:0]<=rx_byte;16:ho[31:24]<=rx_byte;17:ho[23:16]<=rx_byte;18:ho[15:8]<=rx_byte;19:ho[7:0]<=rx_byte;20:hl[15:8]<=rx_byte;21:hl[7:0]<=rx_byte;22:hf[15:8]<=rx_byte;23:hf[7:0]<=rx_byte;24:hq[31:24]<=rx_byte;25:hq[23:16]<=rx_byte;26:hq[15:8]<=rx_byte;27:hq[7:0]<=rx_byte;28:hc[31:24]<=rx_byte;29:hc[23:16]<=rx_byte;30:hc[15:8]<=rx_byte;31:hc[7:0]<=rx_byte;endcase if(rx_last) begin
      hm[31:24]<=mem[0];
       if(header_ok) begin meta_session<=hs;meta_asset_id<=ha;meta_offset<=ho;meta_length<=hl;meta_flags<=hf;meta_sequence<=hq;meta_crc32<=hc;meta_valid<=1;send_index<=0;state<=WAIT_META;end else begin error_count<=error_count+1;state<=IDLE;end end end
   WAIT_META: if(meta_valid&&meta_ready) state<=SEND;
   SEND: if(!payload_valid||payload_ready) begin payload_data<=mem[32+send_index];payload_valid<=1;payload_last<=send_index==hl-1; if(send_index<hl-1) send_index<=send_index+1;end
  endcase
 end
end
endmodule

