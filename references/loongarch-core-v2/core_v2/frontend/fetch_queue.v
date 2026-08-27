module fetch_queue(
    input             clk,
    input             reset,
    input             flush,
    input      [1:0]  push_count,
    input      [99:0] push_entry_0,
    input      [99:0] push_entry_1,
    output            push_ready_1,
    output            push_ready_2,
    input      [1:0]  pop_count,
    output            output_valid_0,
    output            output_valid_1,
    output     [99:0] output_entry_0,
    output     [99:0] output_entry_1,
    output     [3:0]  entry_count
);
    reg [99:0] entries [0:7];
    reg [2:0]  read_ptr_q;
    reg [2:0]  write_ptr_q;
    reg [3:0]  count_q;

    assign push_ready_1 = count_q <= 4'd7;
    assign push_ready_2 = count_q <= 4'd6;
    assign output_valid_0 = count_q != 4'd0;
    assign output_valid_1 = count_q >= 4'd2;
    assign output_entry_0 = entries[read_ptr_q];
    assign output_entry_1 = entries[read_ptr_q + 3'd1];
    assign entry_count = count_q;

    always @(posedge clk) begin
        if (reset || flush) begin
            read_ptr_q  <= 3'd0;
            write_ptr_q <= 3'd0;
            count_q     <= 4'd0;
        end else begin
            if (push_count != 2'd0)
                entries[write_ptr_q] <= push_entry_0;
            if (push_count == 2'd2)
                entries[write_ptr_q + 3'd1] <= push_entry_1;
            write_ptr_q <= write_ptr_q + push_count;
            read_ptr_q  <= read_ptr_q + pop_count;
            count_q     <= count_q + {2'b0, push_count} - {2'b0, pop_count};
        end
    end
endmodule
