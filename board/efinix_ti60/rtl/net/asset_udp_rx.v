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
    // Only the 32-byte header needs parallel field reads. Synchronous payload
    // reads avoid an 8K-bit register array and a 1024:1 combinational mux.
    reg [7:0] header [0:31];
    (* syn_ramstyle="block_ram" *) reg [7:0] payload_ram [0:1023];
    reg [7:0] payload_q;
    reg [10:0] received, sent;
    wire [9:0] payload_wr_address = received - 11'd32;
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

    wire [31:0] magic = {header[0],header[1],header[2],header[3]};
    wire [15:0] version = {header[4],header[5]};
    wire [15:0] packet_type = {header[6],header[7]};
    wire [31:0] session = {header[8],header[9],header[10],header[11]};
    wire [15:0] data_length = {header[20],header[21]};
    wire [15:0] flags = {header[22],header[23]};
    wire [31:0] offset = {header[16],header[17],header[18],header[19]};
    wire valid_packet = !length_changed && {5'b0,received} == declared_length &&
        declared_length >= 33 && declared_length <= 1056 &&
        magic == 32'h41535354 && version == 16'd1 && packet_type == 16'd2 &&
        session == current_session && offset[1:0] == 2'b00 &&
        data_length != 0 && data_length <= 1024 &&
        declared_length == 32 + data_length && flags[15:2] == 0 &&
        flags[1]==0 && (flags[0] || data_length[1:0]==0) &&
        ~payload_crc == {header[28],header[29],header[30],header[31]};

    assign rx_ready = state == IDLE || state == RECEIVE || state == DROP;
    assign meta_valid = state == META;
    assign payload_valid = state == PAYLOAD;
    assign payload_data = payload_q;
    assign payload_last = {5'b0,sent} == meta_length - 1'b1;
    wire payload_read = (state==META && meta_ready) ||
                        (state==PAYLOAD && payload_ready && !payload_last);
    wire [9:0] payload_rd_address = state==META ? 10'd0 : sent[9:0]+10'd1;

    // No RAM reset: validity is owned by state and a complete verified packet.
    // Metadata acceptance prefetches byte zero. Each consumed byte prefetches
    // its successor, so data remains stable under stalls and has no bubbles.
    always @(posedge clk) begin
        if(!reset) begin
            if(state==RECEIVE && rx_valid && received>=32 && received<1056)
                payload_ram[payload_wr_address] <= rx_byte;
            // One syntactic read port is essential to Efinity RAM inference.
            if(payload_read)
                payload_q <= payload_ram[payload_rd_address];
        end
    end

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
                    header[0] <= rx_byte;
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
                        if (received < 32) header[received[4:0]] <= rx_byte;
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
                    meta_asset_id <= {header[12],header[13],header[14],header[15]};
                    meta_offset <= offset;
                    meta_length <= data_length;
                    meta_flags <= flags;
                    meta_sequence <= {header[24],header[25],header[26],header[27]};
                    meta_crc32 <= {header[28],header[29],header[30],header[31]};
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
