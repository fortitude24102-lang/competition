`timescale 1ns/1ps
// One complete UDP application packet is buffered before any byte reaches DMA.
module asset_udp_rx #(
    parameter integer TIMEOUT_CYCLES = 125000
) (
    input wire clk, reset,
    input wire [7:0] rx_byte,
    input wire rx_valid,
    output wire rx_ready,
    input wire rx_last,
    input wire [15:0] rx_length,
    input wire [31:0] current_session,
    output wire meta_valid,
    input wire meta_ready,
    output reg [31:0] meta_session, meta_asset_id, meta_offset, meta_sequence,
    output reg [15:0] meta_length, meta_flags,
    output reg [31:0] meta_crc32,
    output wire payload_valid,
    input wire payload_ready,
    output wire [7:0] payload_data,
    output wire payload_last,
    output reg stream_error,
    output reg [31:0] error_count
);
    localparam [2:0] IDLE=0, RECEIVE=1, CHECK=2, META=3, PAYLOAD=4, DROP=5;
    reg [2:0] state;
    reg [7:0] packet [0:1055];
    reg [10:0] received, sent;
    reg [15:0] declared_length;
    reg length_changed;
    reg [31:0] idle_cycles;
    reg [31:0] payload_crc;
    function [31:0] crc_byte;
        input [31:0] crc;
        input [7:0] data;
        reg [31:0] value;
        integer bit_index;
        begin
            value=crc^{24'b0,data};
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                value=value[0] ? (value>>1)^32'hedb88320 : value>>1;
            crc_byte=value;
        end
    endfunction

    wire [31:0] magic = {packet[0],packet[1],packet[2],packet[3]};
    wire [15:0] version = {packet[4],packet[5]};
    wire [15:0] packet_type = {packet[6],packet[7]};
    wire [31:0] session = {packet[8],packet[9],packet[10],packet[11]};
    wire [15:0] data_length = {packet[20],packet[21]};
    wire [15:0] flags = {packet[22],packet[23]};
    wire [31:0] offset = {packet[16],packet[17],packet[18],packet[19]};
    wire valid_packet = !length_changed && {5'b0,received} == declared_length &&
        declared_length >= 33 && declared_length <= 1056 &&
        magic == 32'h41535354 && version == 16'd1 && packet_type == 16'd2 &&
        session == current_session && offset[1:0] == 2'b00 &&
        data_length != 0 && data_length <= 1024 &&
        declared_length == 32 + data_length && flags[15:2] == 0 &&
        flags[1]==0 && (flags[0] || data_length[1:0]==0) &&
        ~payload_crc == {packet[28],packet[29],packet[30],packet[31]};

    assign rx_ready = state == IDLE || state == RECEIVE || state == DROP;
    assign meta_valid = state == META;
    assign payload_valid = state == PAYLOAD;
    assign payload_data = packet[32 + sent];
    assign payload_last = {5'b0,sent} == meta_length - 1'b1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            received <= 0;
            sent <= 0;
            declared_length <= 0;
            length_changed <= 0;
            idle_cycles <= 0;
            payload_crc <= 32'hffffffff;
            stream_error <= 0;
            error_count <= 0;
            meta_session <= 0;
            meta_asset_id <= 0;
            meta_offset <= 0;
            meta_sequence <= 0;
            meta_length <= 0;
            meta_flags <= 0;
            meta_crc32 <= 0;
        end else begin
            stream_error <= 0;
            if (state == RECEIVE || state == DROP) begin
                if (rx_valid && rx_ready) idle_cycles <= 0;
                else if (idle_cycles < TIMEOUT_CYCLES) idle_cycles <= idle_cycles + 1'b1;
            end else idle_cycles <= 0;
            case (state)
                IDLE: if (rx_valid) begin
                    payload_crc <= 32'hffffffff;
                    packet[0] <= rx_byte;
                    received <= 1;
                    declared_length <= rx_length;
                    length_changed <= 0;
                    if (rx_last) begin
                        state <= IDLE;
                        stream_error <= 1;
                        error_count <= error_count + 1'b1;
                    end else if (rx_length < 33 || rx_length > 1056) begin
                        state <= DROP;
                        stream_error <= 1;
                        error_count <= error_count + 1'b1;
                    end else state <= RECEIVE;
                end
                RECEIVE: begin
                    if (idle_cycles == TIMEOUT_CYCLES) begin
                        state <= IDLE;
                        stream_error <= 1;
                        error_count <= error_count + 1'b1;
                    end else if (rx_valid) begin
                        if (rx_length != declared_length) length_changed <= 1;
                        if (received < 1056) packet[received] <= rx_byte;
                        if (received>=32 && received<1056) payload_crc<=crc_byte(payload_crc,rx_byte);
                        received <= received + 1'b1;
                        if (rx_last) state <= CHECK;
                        else if ({5'b0,received} + 16'd1 >= declared_length) begin
                            state <= DROP;
                            stream_error <= 1;
                            error_count <= error_count + 1'b1;
                        end
                    end
                end
                CHECK: if (valid_packet) begin
                    meta_session <= session;
                    meta_asset_id <= {packet[12],packet[13],packet[14],packet[15]};
                    meta_offset <= offset;
                    meta_length <= data_length;
                    meta_flags <= flags;
                    meta_sequence <= {packet[24],packet[25],packet[26],packet[27]};
                    meta_crc32 <= {packet[28],packet[29],packet[30],packet[31]};
                    sent <= 0;
                    state <= META;
                end else begin
                    state <= IDLE;
                    stream_error <= 1;
                    error_count <= error_count + 1'b1;
                end
                META: if (meta_ready) state <= PAYLOAD;
                PAYLOAD: if (payload_ready) begin
                    if (payload_last) state <= IDLE;
                    else sent <= sent + 1'b1;
                end
                DROP: begin
                    if (idle_cycles == TIMEOUT_CYCLES || (rx_valid && rx_last)) state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
