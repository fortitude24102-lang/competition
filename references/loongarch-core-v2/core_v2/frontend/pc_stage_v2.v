module pc_stage_v2 #(
    parameter [31:0] RESET_PC = 32'h1c000000
)(
    input         clk,
    input         reset,
    input         fetch_ready,
    input         redirect_valid,
    input  [31:0] redirect_target,
    output        fetch_valid,
    output [31:0] fetch_pc
);
    reg [31:0] pc_q;
    reg        valid_q;

    assign fetch_valid = valid_q;
    assign fetch_pc = pc_q;

    always @(posedge clk) begin
        if (reset) begin
            pc_q <= RESET_PC;
            valid_q <= 1'b0;
        end else begin
            valid_q <= 1'b1;
            if (redirect_valid)
                pc_q <= redirect_target;
            else if (fetch_ready)
                pc_q <= pc_q + 32'd4;
        end
    end
endmodule
