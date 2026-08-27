`include "core_v2_defs.vh"

module branch_unit_v2(
    input      [2:0]  condition,
    input      [31:0] operand1,
    input      [31:0] operand2,
    input      [31:0] pc,
    input      [31:0] immediate,
    input             target_is_rs1,
    output reg        taken,
    output     [31:0] target,
    output     [31:0] link_value
);
    wire [31:0] pc_target = pc + immediate;
    wire [31:0] register_target = operand1 + immediate;

    assign target = target_is_rs1 ? register_target : pc_target;
    assign link_value = pc + 32'd4;

    always @(*) begin
        case (condition)
            `V2_BR_EQ:     taken = operand1 == operand2;
            `V2_BR_NE:     taken = operand1 != operand2;
            `V2_BR_LT:     taken = $signed(operand1) < $signed(operand2);
            `V2_BR_GE:     taken = $signed(operand1) >= $signed(operand2);
            `V2_BR_LTU:    taken = operand1 < operand2;
            `V2_BR_GEU:    taken = operand1 >= operand2;
            `V2_BR_ALWAYS: taken = 1'b1;
            default:       taken = 1'b0;
        endcase
    end
endmodule
