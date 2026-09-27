`timescale 1ns/1ps
module efinix_asset_network #(
    parameter integer TX_TIMEOUT_CYCLES=2500000
) (
    input wire gpu_clk,gpu_reset,ge_clk,ge_reset,
    input wire [15:0] paddr,input wire psel,penable,pwrite,input wire [31:0] pwdata,
    output reg [31:0] prdata,output wire pready,output reg pslverror,
    input wire gmii_rx_valid,input wire [7:0] gmii_rx_data,
    output wire gmii_tx_valid,output wire [7:0] gmii_tx_data,
    input wire [31:0] asset_session,input wire asset_active,asset_abort,asset_drop,
    output wire meta_valid,input wire meta_ready,
    output wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,meta_crc32,
    output wire [15:0] meta_length,meta_flags,
    output wire payload_valid,input wire payload_ready,
    output wire [7:0] payload_data,output wire payload_last,stream_error
);
    wire reset=gpu_reset|ge_reset;
    reg [1:0] gpu_reset_pipe,ge_reset_pipe;
    always @(posedge gpu_clk or posedge reset)
        if(reset) gpu_reset_pipe<=2'b11; else gpu_reset_pipe<={gpu_reset_pipe[0],1'b0};
    always @(posedge ge_clk or posedge reset)
        if(reset) ge_reset_pipe<=2'b11; else ge_reset_pipe<={ge_reset_pipe[0],1'b0};
    wire gpu_rst=gpu_reset_pipe[1],ge_rst=ge_reset_pipe[1];
    // DMA rejection is combinational from this cycle's metadata handshake.
    // Delay it until the following payload cycle to avoid a valid/drop loop.
    reg asset_drop_pending;
    always @(posedge gpu_clk or posedge gpu_rst)
        if(gpu_rst) asset_drop_pending<=0; else asset_drop_pending<=asset_drop;
    reg [31:0] local_ip,peer_ip,ports,tx_count;
    reg [255:0] header;
    reg busy,done,error;
    wire descriptor_ready,descriptor_valid,descriptor_take;
    wire [383:0] descriptor;
    wire response_valid,response_error;
    wire access=psel&&penable;
    wire header_address=paddr>=16'h0220 && paddr<=16'h023c;
    wire send=access && pwrite && paddr==16'h0208 && pwdata==1 && !pslverror;
    assign pready=1;
    always @* begin
        prdata=0;pslverror=0;
        case(paddr)
            16'h0200: prdata=32'h4e455431;
            16'h0204: prdata={28'b0,descriptor_ready,error,done,busy};
            16'h0208: prdata=0;
            16'h020c: prdata=local_ip;
            16'h0210: prdata=peer_ip;
            16'h0214: prdata=ports;
            16'h0218: prdata=0; // reserved: do not sample a multibit GE counter
            16'h021c: prdata=tx_count;
            default: if(header_address) prdata=header[paddr[4:2]*32+:32]; else pslverror=1;
        endcase
        if(paddr[1:0]!=0) pslverror=1;
        if(pwrite) begin
            if(paddr==16'h0208) begin
                if(pwdata!=1 || busy || !asset_active || !descriptor_ready) pslverror=1;
            end else if(paddr==16'h020c || paddr==16'h0210 || paddr==16'h0214 || header_address) begin
                if(busy) pslverror=1;
            end else pslverror=1;
        end
        if(!access) pslverror=0;
    end
    always @(posedge gpu_clk or posedge gpu_rst) begin
        if(gpu_rst) begin local_ip<=32'hc0a80002;peer_ip<=32'hc0a80003;ports<=32'h1f901f90;header<=0;busy<=0;done<=0;error<=0;tx_count<=0;end
        else begin
            if(response_valid) begin busy<=0;done<=1;error<=response_error;if(!response_error) tx_count<=tx_count+1'b1;end
            if(send) begin busy<=1;done<=0;error<=0;end
            if(access && pwrite && !pslverror) case(paddr)
                16'h020c: local_ip<=pwdata;
                16'h0210: peer_ip<=pwdata;
                16'h0214: ports<=pwdata;
                default: if(header_address) header[paddr[4:2]*32+:32]<=pwdata;
            endcase
        end
    end
    pixel_async_fifo #(.DATA_WIDTH(384),.DEPTH(4),.ADDRESS_WIDTH(2)) u_request(
        .wr_clk(gpu_clk),.wr_reset(reset),.wr_data({asset_session,ports,peer_ip,local_ip,header}),.wr_valid(send),.wr_ready(descriptor_ready),
        .rd_clk(ge_clk),.rd_reset(reset),.rd_data(descriptor),.rd_valid(descriptor_valid),.rd_ready(descriptor_take));
    reg [383:0] active_descriptor;
    reg pending;
    wire mac_ready,mac_done,mac_error;
    assign descriptor_take=!pending && mac_ready;
    always @(posedge ge_clk or posedge ge_rst) begin
        if(ge_rst) begin active_descriptor<={32'b0,32'h1f901f90,32'hc0a80003,32'hc0a80002,256'b0};pending<=0;end
        else begin
            if(descriptor_valid && descriptor_take) begin active_descriptor<=descriptor;pending<=1;end
            else if(pending && mac_ready) pending<=0;
        end
    end
    pixel_async_fifo #(.DATA_WIDTH(1),.DEPTH(4),.ADDRESS_WIDTH(2)) u_response(
        .wr_clk(ge_clk),.wr_reset(reset),.wr_data(mac_error),.wr_valid(mac_done),.wr_ready(),
        .rd_clk(gpu_clk),.rd_reset(reset),.rd_data(response_error),.rd_valid(response_valid),.rd_ready(1'b1));
    wire [7:0] rx_byte;
    wire rx_valid,rx_ready,rx_last;
    wire [15:0] rx_length;
    efinix_ge_mac_wrapper #(.TX_TIMEOUT_CYCLES(TX_TIMEOUT_CYCLES)) u_ge(
        .clk(ge_clk),.reset(ge_rst),.gmii_rx_valid(gmii_rx_valid),.gmii_rx_data(gmii_rx_data),
        .gmii_tx_valid(gmii_tx_valid),.gmii_tx_data(gmii_tx_data),
        .tx_valid(pending),.tx_ready(mac_ready),.tx_header(active_descriptor[255:0]),
        .local_ip(active_descriptor[287:256]),.peer_ip(active_descriptor[319:288]),.ports(active_descriptor[351:320]),
        .tx_done(mac_done),.tx_error(mac_error),.rx_byte(rx_byte),.rx_valid(rx_valid),.rx_ready(rx_ready),.rx_last(rx_last),.rx_length(rx_length));
    wire [191:0] m_in,m_out;
    wire m_valid,m_ready,m_out_valid,m_out_ready;
    wire [8:0] p_in,p_out;
    wire p_valid,p_ready,p_out_valid,p_out_ready;
    asset_udp_rx u_parser(
        .clk(ge_clk),.reset(ge_rst),.rx_byte(rx_byte),.rx_valid(rx_valid),.rx_ready(rx_ready),.rx_last(rx_last),.rx_length(rx_length),
        .current_session(active_descriptor[383:352]),
        .meta_valid(m_valid),.meta_ready(m_ready),.meta_session(m_in[191:160]),.meta_asset_id(m_in[159:128]),.meta_offset(m_in[127:96]),
        .meta_length(m_in[95:80]),.meta_flags(m_in[79:64]),.meta_sequence(m_in[63:32]),.meta_crc32(m_in[31:0]),
        .payload_valid(p_valid),.payload_ready(p_ready),.payload_data(p_in[7:0]),.payload_last(p_in[8]),.stream_error(),.error_count());
    pixel_async_fifo #(.DATA_WIDTH(192),.DEPTH(4),.ADDRESS_WIDTH(2)) u_metadata(
        .wr_clk(ge_clk),.wr_reset(reset),.wr_data(m_in),.wr_valid(m_valid),.wr_ready(m_ready),
        .rd_clk(gpu_clk),.rd_reset(reset),.rd_data(m_out),.rd_valid(m_out_valid),.rd_ready(m_out_ready));
    pixel_async_fifo #(.DATA_WIDTH(9),.DEPTH(2048),.ADDRESS_WIDTH(11)) u_payload(
        .wr_clk(ge_clk),.wr_reset(reset),.wr_data(p_in),.wr_valid(p_valid),.wr_ready(p_ready),
        .rd_clk(gpu_clk),.rd_reset(reset),.rd_data(p_out),.rd_valid(p_out_valid),.rd_ready(p_out_ready));
    asset_stream_guard u_guard(
        .clk(gpu_clk),.reset(gpu_rst),.in_meta_valid(m_out_valid),.in_meta_ready(m_out_ready),
        .in_meta_session(m_out[191:160]),.in_meta_asset_id(m_out[159:128]),.in_meta_offset(m_out[127:96]),
        .in_meta_length(m_out[95:80]),.in_meta_flags(m_out[79:64]),.in_meta_sequence(m_out[63:32]),.in_meta_crc32(m_out[31:0]),
        .in_payload_valid(p_out_valid),.in_payload_ready(p_out_ready),.in_payload_data(p_out[7:0]),.in_payload_last(p_out[8]),
        .source_error(1'b0),.dma_abort(asset_abort|asset_drop_pending|!asset_active),
        .meta_valid(meta_valid),.meta_ready(meta_ready),.meta_session(meta_session),.meta_asset_id(meta_asset_id),.meta_offset(meta_offset),
        .meta_length(meta_length),.meta_flags(meta_flags),.meta_sequence(meta_sequence),.meta_crc32(meta_crc32),
        .payload_valid(payload_valid),.payload_ready(payload_ready),.payload_data(payload_data),.payload_last(payload_last),.stream_error(stream_error),.error_count());
endmodule
