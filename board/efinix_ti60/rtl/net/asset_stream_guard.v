`timescale 1ns/1ps
// GPU-domain packet ordering and abort containment after the RX async FIFOs.
module asset_stream_guard #(
    parameter integer TIMEOUT_CYCLES = 100000
) (
    input wire clk, reset,
    input wire in_meta_valid,
    output wire in_meta_ready,
    input wire [31:0] in_meta_session,in_meta_asset_id,in_meta_offset,in_meta_sequence,
    input wire [15:0] in_meta_length,in_meta_flags,
    input wire [31:0] in_meta_crc32,
    input wire in_payload_valid,
    output wire in_payload_ready,
    input wire [7:0] in_payload_data,
    input wire in_payload_last,
    input wire source_error,
    input wire dma_abort,
    output wire meta_valid,
    input wire meta_ready,
    output wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,
    output wire [15:0] meta_length,meta_flags,
    output wire [31:0] meta_crc32,
    output wire payload_valid,
    input wire payload_ready,
    output wire [7:0] payload_data,
    output wire payload_last,
    output reg stream_error,
    output reg [31:0] error_count
);
    localparam [1:0] META=0, FORWARD=1, DRAIN=2;
    reg [1:0] state;
    reg [15:0] remaining;
    reg [31:0] idle_cycles;
    wire consume_meta = in_meta_valid && in_meta_ready;
    wire consume_payload = in_payload_valid && in_payload_ready;
    wire invalid_length = in_meta_length==0 || in_meta_length>1024;

    assign meta_valid = state==META && in_meta_valid && !dma_abort && !invalid_length;
    assign in_meta_ready = state==META && (dma_abort || invalid_length || meta_ready);
    assign meta_session=in_meta_session;
    assign meta_asset_id=in_meta_asset_id;
    assign meta_offset=in_meta_offset;
    assign meta_sequence=in_meta_sequence;
    assign meta_length=in_meta_length;
    assign meta_flags=in_meta_flags;
    assign meta_crc32=in_meta_crc32;

    assign payload_valid=state==FORWARD && in_payload_valid && !dma_abort;
    assign in_payload_ready=state==DRAIN || (state==FORWARD &&
        (dma_abort || payload_ready));
    assign payload_data=in_payload_data;
    assign payload_last=in_payload_last;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=META;
            remaining<=0;
            idle_cycles<=0;
            stream_error<=0;
            error_count<=0;
        end else begin
            stream_error<=0;
            if (source_error) begin
                stream_error<=1;
                error_count<=error_count+1'b1;
            end
            if (state==META) begin
                idle_cycles<=0;
                if (consume_meta) begin
                    remaining<=in_meta_length;
                    if (dma_abort || invalid_length) begin
                        state<=DRAIN;
                        if (invalid_length && !source_error) begin
                            stream_error<=1;
                            error_count<=error_count+1'b1;
                        end
                    end else state<=FORWARD;
                end
            end else begin
                if (consume_payload) idle_cycles<=0;
                else if (!in_payload_valid && idle_cycles<TIMEOUT_CYCLES) idle_cycles<=idle_cycles+1'b1;
                if (idle_cycles==TIMEOUT_CYCLES && state==FORWARD) begin
                    state<=DRAIN;
                    stream_error<=1;
                    error_count<=error_count+1'b1;
                end else if (state==FORWARD) begin
                    if (dma_abort) state<=DRAIN;
                    if (consume_payload) begin
                        if (remaining!=0) remaining<=remaining-1'b1;
                        if (dma_abort) state<=in_payload_last ? META : DRAIN;
                        else if (in_payload_last && remaining==1) state<=META;
                        else if (!dma_abort && (in_payload_last || remaining==1)) begin
                            state<=in_payload_last ? META : DRAIN;
                            stream_error<=1;
                            error_count<=error_count+1'b1;
                        end
                    end
                end else if (consume_payload && in_payload_last) state<=META;
            end
        end
    end
endmodule
