`include "core_v2_defs.vh"

module alu_v2(
    input      [31:0] operand_a,
    input      [31:0] operand_b,
    input      [3:0]  alu_op,
    output reg [31:0] result,
    output reg [31:0] bypass_result
);
    wire [31:0] add_result  = operand_a + operand_b;
    wire [31:0] sub_result  = operand_a - operand_b;
    wire [31:0] slt_result  = {31'b0, $signed(operand_a) < $signed(operand_b)};
    wire [31:0] sltu_result = {31'b0, operand_a < operand_b};

    always @(*) begin
        case (alu_op)
            `V2_ALU_ADD:  result = add_result;
            `V2_ALU_SUB:  result = sub_result;
            `V2_ALU_AND:  result = operand_a & operand_b;
            `V2_ALU_OR:   result = operand_a | operand_b;
            `V2_ALU_XOR:  result = operand_a ^ operand_b;
            `V2_ALU_NOR:  result = ~(operand_a | operand_b);
            `V2_ALU_SLT:  result = slt_result;
            `V2_ALU_SLTU: result = sltu_result;
            `V2_ALU_SLL:  result = operand_a << operand_b[4:0];
            `V2_ALU_SRA:  result = $signed(operand_a) >>> operand_b[4:0];
            `V2_ALU_SRL:  result = operand_a >> operand_b[4:0];
            default:      result = 32'b0;
        endcase
    end

    always @(*) begin
        case (alu_op)
            `V2_ALU_ADD:  bypass_result = add_result;
            `V2_ALU_SUB:  bypass_result = sub_result;
            `V2_ALU_AND:  bypass_result = operand_a & operand_b;
            `V2_ALU_OR:   bypass_result = operand_a | operand_b;
            `V2_ALU_XOR:  bypass_result = operand_a ^ operand_b;
            `V2_ALU_NOR:  bypass_result = ~(operand_a | operand_b);
            `V2_ALU_SLT:  bypass_result = slt_result;
            `V2_ALU_SLTU: bypass_result = sltu_result;
            default:      bypass_result = 32'b0;
        endcase
    end
endmodule
