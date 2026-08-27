`include "core_v2_defs.vh"

module execute_unit_v2(
    input      [31:0] pc,
    input      [3:0]  uop,
    input      [3:0]  alu_op,
    input      [2:0]  branch_cond,
    input      [31:0] operand1,
    input      [31:0] operand2,
    input      [31:0] immediate,
    input             src1_is_pc,
    input             src2_is_imm,
    input             target_is_rs1,
    input             link,
    output     [31:0] result,
    output            branch_taken,
    output     [31:0] branch_target
);
    wire [31:0] alu_operand1 = src1_is_pc ? pc : operand1;
    wire [31:0] alu_operand2 = src2_is_imm ? immediate : operand2;
    wire [31:0] alu_result;
    wire [31:0] unused_alu_bypass_result;
    wire [31:0] link_value;
    wire branch_is_valid = uop == `V2_UOP_BRANCH;
    wire branch_taken_raw;

    alu_v2 u_alu (
        .operand_a(alu_operand1),
        .operand_b(alu_operand2),
        .alu_op(alu_op),
        .result(alu_result),
        .bypass_result(unused_alu_bypass_result)
    );

    branch_unit_v2 u_branch (
        .condition(branch_cond),
        .operand1(operand1),
        .operand2(operand2),
        .pc(pc),
        .immediate(immediate),
        .target_is_rs1(target_is_rs1),
        .taken(branch_taken_raw),
        .target(branch_target),
        .link_value(link_value)
    );

    assign branch_taken = branch_is_valid && branch_taken_raw;
    assign result = link ? link_value : alu_result;
endmodule
