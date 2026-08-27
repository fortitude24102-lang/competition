module axi_ar_buffer_v2(
    input             clk,
    input             reset,
    input             input_valid,
    output            input_ready,
    input      [31:0] input_address,
    input             input_owner,
    output            output_valid,
    input             output_ready,
    output     [31:0] output_address,
    output            output_owner
);
    reg [31:0] front_address_q;
    reg        front_owner_q;
    reg        front_valid_q;
    reg [31:0] back_address_q;
    reg        back_owner_q;
    reg        back_valid_q;

    wire push;
    wire pop;

    assign output_valid = front_valid_q;
    assign output_address = front_valid_q ? front_address_q : 32'b0;
    assign output_owner = front_valid_q ? front_owner_q : 1'b0;
    assign input_ready = !back_valid_q || pop;
    assign push = input_valid && input_ready;
    assign pop = output_valid && output_ready;

    always @(posedge clk) begin
        if (reset) begin
            front_valid_q <= 1'b0;
            back_valid_q <= 1'b0;
        end else begin
            case ({push, pop})
                2'b10: begin
                    if (!front_valid_q) begin
                        front_address_q <= input_address;
                        front_owner_q <= input_owner;
                        front_valid_q <= 1'b1;
                    end else begin
                        back_address_q <= input_address;
                        back_owner_q <= input_owner;
                        back_valid_q <= 1'b1;
                    end
                end
                2'b01: begin
                    if (back_valid_q) begin
                        front_address_q <= back_address_q;
                        front_owner_q <= back_owner_q;
                        back_valid_q <= 1'b0;
                    end else begin
                        front_valid_q <= 1'b0;
                    end
                end
                2'b11: begin
                    if (back_valid_q) begin
                        front_address_q <= back_address_q;
                        front_owner_q <= back_owner_q;
                        back_address_q <= input_address;
                        back_owner_q <= input_owner;
                    end else begin
                        front_address_q <= input_address;
                        front_owner_q <= input_owner;
                    end
                end
                default: begin
                    front_valid_q <= front_valid_q;
                    back_valid_q <= back_valid_q;
                end
            endcase
        end
    end
endmodule
