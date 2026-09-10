`timescale 1ns/1ps
module display_line_buffer (
    input wire clk,
    input wire reset,
    input wire [17:0] input_data,
    input wire input_valid,
    output wire input_ready,
    input wire line_begin,
    input wire line_done,
    input wire [9:0] read_index,
    output wire [15:0] read_pixel,
    output reg line_valid,
    output reg protocol_error
);
    (* syn_ramstyle = "block_ram" *) reg [15:0] line0 [0:639];
    (* syn_ramstyle = "block_ram" *) reg [15:0] line1 [0:639];
    reg [15:0] line0_read, line1_read;
    reg [9:0] write_index;
    reg write_bank, read_bank, active_bank;
    reg [1:0] bank_ready;
    wire write_fire = input_valid && input_ready;
    wire write_last = write_index == 10'd639;

    assign input_ready = !bank_ready[write_bank];
    assign read_pixel = active_bank ? line1_read : line0_read;

    always @(posedge clk) begin
        line0_read <= line0[read_index];
        line1_read <= line1[read_index];
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_index <= 0;
            write_bank <= 0;
            read_bank <= 0;
            active_bank <= 0;
            bank_ready <= 0;
            line_valid <= 0;
            protocol_error <= 0;
        end else begin
            if (line_begin) begin
                active_bank <= read_bank;
                line_valid <= bank_ready[read_bank];
            end
            if (line_done) begin
                if (line_valid)
                    bank_ready[active_bank] <= 0;
                read_bank <= ~read_bank;
                line_valid <= 0;
            end
            if (write_fire) begin
                if (write_bank)
                    line1[write_index] <= input_data[17:2];
                else
                    line0[write_index] <= input_data[17:2];
                if (input_data[1] != write_last || (input_data[0] && !input_data[1]))
                    protocol_error <= 1;
                if (write_last) begin
                    bank_ready[write_bank] <= 1;
                    if (active_bank == write_bank && !line_valid)
                        line_valid <= 1;
                    write_bank <= ~write_bank;
                    write_index <= 0;
                end else begin
                    write_index <= write_index + 1'b1;
                end
            end
        end
    end
endmodule
