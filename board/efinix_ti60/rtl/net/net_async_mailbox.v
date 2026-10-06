`timescale 1ns/1ps
// Single-outstanding stable-snapshot CDC, inspired by PULP's two-phase CDC.
// Both domains MUST share the combined asynchronous reset. This is not a FIFO
// and must not replace a receiver that promises multiple queued transactions.
module net_async_mailbox #(
    parameter integer DATA_WIDTH=32
) (
    input wire wr_clk,wr_reset,
    input wire [DATA_WIDTH-1:0] wr_data,
    input wire wr_valid,
    output wire wr_ready,
    input wire rd_clk,rd_reset,
    output wire [DATA_WIDTH-1:0] rd_data,
    output reg rd_valid,
    input wire rd_ready
);
    wire reset=wr_reset|rd_reset;
    reg [1:0] wr_release,rd_release;
    always @(posedge wr_clk or posedge reset)
        if(reset) wr_release<=2'b11;else wr_release<={wr_release[0],1'b0};
    always @(posedge rd_clk or posedge reset)
        if(reset) rd_release<=2'b11;else rd_release<={rd_release[0],1'b0};
    (* syn_keep="true" *) reg request,acknowledge;
    (* ASYNC_REG="TRUE" *) reg acknowledge_sync0,acknowledge_sync1;
    (* ASYNC_REG="TRUE" *) reg request_sync0,request_sync1;
    (* syn_keep="true" *) reg [DATA_WIDTH-1:0] wr_snapshot;
    reg [DATA_WIDTH-1:0] rd_snapshot;
    assign wr_ready=!reset && !wr_release[1] && request==acknowledge_sync1;
    assign rd_data=rd_snapshot;
    always @(posedge wr_clk or posedge reset) begin
        if(reset) begin
            request<=0;acknowledge_sync0<=0;acknowledge_sync1<=0;wr_snapshot<=0;
        end else if(wr_release[1]) begin
            request<=0;acknowledge_sync0<=0;acknowledge_sync1<=0;
        end else begin
            acknowledge_sync0<=acknowledge;acknowledge_sync1<=acknowledge_sync0;
            if(wr_valid && wr_ready) begin wr_snapshot<=wr_data;request<=~request;end
        end
    end
    always @(posedge rd_clk or posedge reset) begin
        if(reset) begin
            acknowledge<=0;request_sync0<=0;request_sync1<=0;rd_snapshot<=0;rd_valid<=0;
        end else if(rd_release[1]) begin
            acknowledge<=0;request_sync0<=0;request_sync1<=0;rd_valid<=0;
        end else begin
            request_sync0<=request;request_sync1<=request_sync0;
            if(!rd_valid && request_sync1!=acknowledge) begin
                rd_snapshot<=wr_snapshot;rd_valid<=1;
            end
            if(rd_valid && rd_ready) begin rd_valid<=0;acknowledge<=request_sync1;end
        end
    end
endmodule
