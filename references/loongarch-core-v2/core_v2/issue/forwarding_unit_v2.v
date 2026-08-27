module forwarding_unit_v2(
    input  [4:0]  rs1,
    input  [4:0]  rs2,
    input         use_rs1,
    input         use_rs2,
    input  [31:0] rf_data1,
    input  [31:0] rf_data2,
    input         e0_valid,
    input         e0_we,
    input  [4:0]  e0_rd,
    input  [31:0] e0_data,
    input         m0_valid,
    input         m0_we,
    input  [4:0]  m0_rd,
    input  [31:0] m0_data,
    input         m1_valid,
    input         m1_we,
    input  [4:0]  m1_rd,
    input  [31:0] m1_data,
    input         c0_valid,
    input         c0_we,
    input  [4:0]  c0_rd,
    input  [31:0] c0_data,
    output reg [31:0] operand1,
    output reg [31:0] operand2
);
    always @(*) begin
        operand1 = rf_data1;
        if (use_rs1 && rs1 != 5'd0) begin
            if (e0_valid && e0_we && e0_rd == rs1)
                operand1 = e0_data;
            else if (m0_valid && m0_we && m0_rd == rs1)
                operand1 = m0_data;
            else if (m1_valid && m1_we && m1_rd == rs1)
                operand1 = m1_data;
            else if (c0_valid && c0_we && c0_rd == rs1)
                operand1 = c0_data;
        end

        operand2 = rf_data2;
        if (use_rs2 && rs2 != 5'd0) begin
            if (e0_valid && e0_we && e0_rd == rs2)
                operand2 = e0_data;
            else if (m0_valid && m0_we && m0_rd == rs2)
                operand2 = m0_data;
            else if (m1_valid && m1_we && m1_rd == rs2)
                operand2 = m1_data;
            else if (c0_valid && c0_we && c0_rd == rs2)
                operand2 = c0_data;
        end
    end
endmodule
