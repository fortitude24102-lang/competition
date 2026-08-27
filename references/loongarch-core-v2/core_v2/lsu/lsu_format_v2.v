`include "core_v2_defs.vh"

module lsu_format_v2(
    input      [1:0]  address_low,
    input      [1:0]  width,
    input             load_signed,
    input      [31:0] store_data,
    input      [31:0] read_data,
    output reg        aligned,
    output reg [3:0]  write_strobe,
    output reg [31:0] write_data,
    output reg [31:0] load_data
);
    reg [7:0] selected_byte;
    reg [15:0] selected_half;

    always @(*) begin
        aligned = 1'b1;
        write_strobe = 4'b0000;
        write_data = 32'b0;
        load_data = 32'b0;
        selected_byte = 8'b0;
        selected_half = 16'b0;

        case (address_low)
            2'd0: selected_byte = read_data[7:0];
            2'd1: selected_byte = read_data[15:8];
            2'd2: selected_byte = read_data[23:16];
            default: selected_byte = read_data[31:24];
        endcase

        selected_half = address_low[1] ? read_data[31:16] : read_data[15:0];

        case (width)
            `V2_MEM_BYTE: begin
                write_strobe = 4'b0001 << address_low;
                write_data = {24'b0, store_data[7:0]} << {address_low, 3'b000};
                load_data = load_signed
                    ? {{24{selected_byte[7]}}, selected_byte}
                    : {24'b0, selected_byte};
            end
            `V2_MEM_HALF: begin
                if (address_low[0]) begin
                    aligned = 1'b0;
                end else begin
                    write_strobe = address_low[1] ? 4'b1100 : 4'b0011;
                    write_data = address_low[1]
                        ? {store_data[15:0], 16'b0}
                        : {16'b0, store_data[15:0]};
                    load_data = load_signed
                        ? {{16{selected_half[15]}}, selected_half}
                        : {16'b0, selected_half};
                end
            end
            `V2_MEM_WORD: begin
                if (address_low != 2'b00) begin
                    aligned = 1'b0;
                end else begin
                    write_strobe = 4'b1111;
                    write_data = store_data;
                    load_data = read_data;
                end
            end
            default: aligned = 1'b0;
        endcase

        if (!aligned) begin
            write_strobe = 4'b0000;
            write_data = 32'b0;
            load_data = 32'b0;
        end
    end
endmodule
