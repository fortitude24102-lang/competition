module multiplier_v2(
    input             clk,
    input             reset,
    input             request_valid,
    output            request_ready,
    input      [31:0] operand1,
    input      [31:0] operand2,
    output            response_valid,
    input             response_ready,
    output     [31:0] response_data
);
    reg valid_0_q;
    reg valid_1_q;
    reg valid_2_q;
    reg [31:0] product_0_q;
    reg [31:0] product_1_q;
    reg [31:0] product_2_q;
    wire ready_2;
    wire ready_1;
    wire ready_0;

    assign ready_2 = !valid_2_q || response_ready;
    assign ready_1 = !valid_1_q || ready_2;
    assign ready_0 = !valid_0_q || ready_1;
    assign request_ready = ready_0;
    assign response_valid = valid_2_q;
    assign response_data = product_2_q;

    always @(posedge clk) begin
        if (reset) begin
            valid_0_q <= 1'b0;
            valid_1_q <= 1'b0;
            valid_2_q <= 1'b0;
        end else begin
            if (ready_2) begin
                valid_2_q <= valid_1_q;
                if (valid_1_q)
                    product_2_q <= product_1_q;
            end
            if (ready_1) begin
                valid_1_q <= valid_0_q;
                if (valid_0_q)
                    product_1_q <= product_0_q;
            end
            if (ready_0) begin
                valid_0_q <= request_valid;
                if (request_valid)
                    product_0_q <= operand1 * operand2;
            end
        end
    end
endmodule
