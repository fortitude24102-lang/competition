`timescale 1ns/1ps
module net_control_bridge #(
    parameter integer GPU_CYCLES_PER_MS=100000
) (
    input wire gpu_clk,gpu_reset,ge_clk,ge_reset,
    input wire [15:0] paddr,input wire psel,penable,pwrite,input wire [31:0] pwdata,
    output reg [31:0] prdata,output wire pready,output reg pslverror,
    input wire [255:0] rx_packet,input wire rx_packet_valid,output wire rx_packet_ready,
    input wire [31:0] rx_arrival_ms,rx_drop_count,output wire [31:0] ge_time_ms,
    output wire [1023:0] tx_packet,output wire tx_packet_valid,input wire tx_packet_ready,
    output wire [15:0] tx_length,input wire tx_done,tx_error,
    input wire [31:0] configured_local_ip,configured_peer_ip,
    output wire [31:0] tx_local_ip,tx_peer_ip
);
    wire reset=gpu_reset|ge_reset;
    reg [1:0] gpu_pipe,ge_pipe;
    always @(posedge gpu_clk or posedge reset) if(reset) gpu_pipe<=3;else gpu_pipe<={gpu_pipe[0],1'b0};
    always @(posedge ge_clk or posedge reset) if(reset) ge_pipe<=3;else ge_pipe<={ge_pipe[0],1'b0};
    wire gpu_rst=gpu_pipe[1],ge_rst=ge_pipe[1];
    reg [31:0] tick_divider,time_ms;
    (* syn_keep="true" *) reg [31:0] time_gray;
    (* ASYNC_REG="TRUE" *) reg [31:0] time_sync1,time_sync2,drop_sync1,drop_sync2;
    (* syn_keep="true" *) reg [31:0] drop_gray;
    function [31:0] gray_binary;
        input [31:0] gray;integer b;
        begin gray_binary[31]=gray[31];for(b=30;b>=0;b=b-1) gray_binary[b]=gray_binary[b+1]^gray[b];end
    endfunction
    assign ge_time_ms=gray_binary(time_sync2);
    wire [31:0] next_ms=time_ms+1'b1;
    always @(posedge gpu_clk or posedge gpu_rst) begin
        if(gpu_rst) begin tick_divider<=0;time_ms<=0;time_gray<=0;drop_sync1<=0;drop_sync2<=0;end
        else begin
            if(tick_divider==GPU_CYCLES_PER_MS-1) begin tick_divider<=0;time_ms<=next_ms;time_gray<=next_ms^(next_ms>>1);end
            else tick_divider<=tick_divider+1'b1;
            drop_sync1<=drop_gray;drop_sync2<=drop_sync1;
        end
    end
    always @(posedge ge_clk or posedge ge_rst) begin
        if(ge_rst) begin time_sync1<=0;time_sync2<=0;drop_gray<=0;end
        else begin time_sync1<=time_gray;time_sync2<=time_sync1;drop_gray<=rx_drop_count^(rx_drop_count>>1);end
    end
    wire [287:0] rx_head;wire rx_head_valid;wire rx_release;
    pixel_async_fifo #(.DATA_WIDTH(288),.DEPTH(4),.ADDRESS_WIDTH(2)) u_rx(
        .wr_clk(ge_clk),.wr_reset(reset),.wr_data({rx_arrival_ms,rx_packet}),.wr_valid(rx_packet_valid),.wr_ready(rx_packet_ready),
        .rd_clk(gpu_clk),.rd_reset(reset),.rd_data(rx_head),.rd_valid(rx_head_valid),.rd_ready(rx_release));
    reg [255:0] snapshot;reg [31:0] snapshot_age;reg snapshot_valid;
    reg [1023:0] tx_shadow;reg [31:0] written;reg [15:0] length_shadow;
    reg busy,error;reg [31:0] done_count;
    wire tx_fifo_ready,response_valid,response_error;
    wire [1103:0] tx_descriptor;
    wire access=psel&&penable;
    wire rx_word=paddr>=16'h0320 && paddr<=16'h033c;
    wire tx_word=paddr>=16'h0340 && paddr<=16'h03bc;
    wire all_written=length_shadow==128 ? &written : &written[7:0];
    wire commit=access && pwrite && paddr==16'h0318 && !pslverror;
    assign rx_release=access && pwrite && paddr==16'h030c && !pslverror;
    assign pready=1'b1;
    always @* begin
        prdata=0;pslverror=0;
        case(paddr)
            16'h0300: prdata=32'h4d475431;
            16'h0304: prdata={28'b0,error,(!busy && tx_fifo_ready),snapshot_valid,rx_head_valid};
            16'h0308,16'h030c,16'h0318: prdata=0;
            16'h0310: begin prdata=snapshot_age;if(!snapshot_valid) pslverror=1;end
            16'h0314: prdata=gray_binary(drop_sync2);
            16'h031c: prdata=done_count;
            16'h03c0: prdata={16'b0,length_shadow};
            default: begin
                if(rx_word) begin prdata=snapshot[paddr[4:2]*32+:32];if(!snapshot_valid) pslverror=1;end
                else if(tx_word) prdata=tx_shadow[((paddr-16'h0340)>>2)*32+:32];
                else pslverror=1;
            end
        endcase
        if(paddr[1:0]!=0) pslverror=1;
        if(pwrite) begin
            case(paddr)
                16'h0308: if(pwdata!=1 || !rx_head_valid || snapshot_valid) pslverror=1;
                16'h030c: if(pwdata!=1 || !snapshot_valid) pslverror=1;
                16'h0318: if(pwdata!=1 || busy || !tx_fifo_ready || !all_written) pslverror=1;
                16'h03c0: if(busy || (pwdata!=32 && pwdata!=128)) pslverror=1;
                default: if(!tx_word || busy) pslverror=1;
            endcase
        end
        if(!access) pslverror=0;
    end
    always @(posedge gpu_clk or posedge gpu_rst) begin
        if(gpu_rst) begin snapshot<=0;snapshot_age<=0;snapshot_valid<=0;tx_shadow<=0;written<=0;length_shadow<=32;busy<=0;error<=0;done_count<=0;end
        else begin
            if(response_valid) begin busy<=0;done_count<=done_count+1'b1;if(response_error) error<=1;end
            if(access && pwrite) begin
                if(paddr==16'h0318 && pslverror) error<=1;
                if(!pslverror) begin
                    case(paddr)
                        16'h0308: begin snapshot<=rx_head[255:0];snapshot_age<=time_ms-rx_head[287:256];snapshot_valid<=1;end
                        16'h030c: snapshot_valid<=0;
                        16'h0318: begin busy<=1;error<=0;written<=0;end
                        16'h03c0: length_shadow<=pwdata[15:0];
                        default: if(tx_word) begin tx_shadow[((paddr-16'h0340)>>2)*32+:32]<=pwdata;written[(paddr-16'h0340)>>2]<=1;end
                    endcase
                end
            end
        end
    end
    // IP configuration is GPU-domain data: snapshot with the packet, never
    // sample a live multibit APB register across the GE clock boundary.
    // busy forbids another commit until TX completion, so four BRAM-backed
    // slots add no concurrency. Retain an atomic snapshot in one CDC mailbox.
    net_async_mailbox #(.DATA_WIDTH(1104)) u_tx(
        .wr_clk(gpu_clk),.wr_reset(reset),.wr_data({configured_peer_ip,configured_local_ip,length_shadow,tx_shadow}),.wr_valid(commit),.wr_ready(tx_fifo_ready),
        .rd_clk(ge_clk),.rd_reset(reset),.rd_data(tx_descriptor),.rd_valid(tx_packet_valid),.rd_ready(tx_packet_ready));
    assign tx_packet=tx_descriptor[1023:0];assign tx_length=tx_descriptor[1039:1024];
    assign tx_local_ip=tx_descriptor[1071:1040];assign tx_peer_ip=tx_descriptor[1103:1072];
    pixel_async_fifo #(.DATA_WIDTH(1),.DEPTH(4),.ADDRESS_WIDTH(2)) u_done(
        .wr_clk(ge_clk),.wr_reset(reset),.wr_data(tx_error),.wr_valid(tx_done),.wr_ready(),
        .rd_clk(gpu_clk),.rd_reset(reset),.rd_data(response_error),.rd_valid(response_valid),.rd_ready(1'b1));
endmodule
