module integer_issue_v2(
    input      [31:0] pc,
    input      [31:0] inst,
    input      [31:0] rf_data1,
    input      [31:0] rf_data2,
    input             e0_valid,
    input             e0_we,
    input             e0_result_ready,
    input      [4:0]  e0_rd,
    input      [31:0] e0_data,
    input             m0_valid,
    input             m0_we,
    input             m0_result_ready,
    input      [4:0]  m0_rd,
    input      [31:0] m0_data,
    input             m1_valid,
    input             m1_we,
    input             m1_result_ready,
    input      [4:0]  m1_rd,
    input      [31:0] m1_data,
    input             c0_valid,
    input             c0_we,
    input      [4:0]  c0_rd,
    input      [31:0] c0_data,
    output     [4:0]  rs1,
    output     [4:0]  rs2,
    output     [4:0]  rd,
    output            use_rs1,
    output            use_rs2,
    output            reg_write,
    output     [3:0]  uop,
    output     [1:0]  mem_width,
    output            mem_signed,
    output            illegal,
    output            stall,
    output     [31:0] result,
    output     [31:0] store_data,
    output            branch_taken,
    output     [31:0] branch_target
);
    wire [3:0] alu_op;
    wire [2:0] imm_type;
    wire [2:0] branch_cond;
    wire src1_is_pc;
    wire src2_is_imm;
    wire link;
    wire target_is_rs1;
    wire [31:0] immediate;
    wire [31:0] operand1;
    wire [31:0] operand2;

    decoder_v2 u_decoder (
        .inst(inst),
        .uop(uop), .alu_op(alu_op), .imm_type(imm_type),
        .branch_cond(branch_cond),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .use_rs1(use_rs1), .use_rs2(use_rs2),
        .src1_is_pc(src1_is_pc), .src2_is_imm(src2_is_imm),
        .reg_write(reg_write), .link(link),
        .target_is_rs1(target_is_rs1),
        .mem_width(mem_width), .mem_signed(mem_signed),
        .illegal(illegal)
    );

    immediate_gen_v2 u_immediate (
        .inst(inst[25:0]),
        .imm_type(imm_type),
        .immediate(immediate)
    );

    forwarding_unit_v2 u_forwarding (
        .rs1(rs1), .rs2(rs2),
        .use_rs1(use_rs1), .use_rs2(use_rs2),
        .rf_data1(rf_data1), .rf_data2(rf_data2),
        .e0_valid(e0_valid && e0_result_ready),
        .e0_we(e0_we), .e0_rd(e0_rd), .e0_data(e0_data),
        .m0_valid(m0_valid && m0_result_ready),
        .m0_we(m0_we), .m0_rd(m0_rd), .m0_data(m0_data),
        .m1_valid(m1_valid && m1_result_ready),
        .m1_we(m1_we), .m1_rd(m1_rd), .m1_data(m1_data),
        .c0_valid(c0_valid), .c0_we(c0_we),
        .c0_rd(c0_rd), .c0_data(c0_data),
        .operand1(operand1), .operand2(operand2)
    );

    hazard_unit_v2 u_hazard (
        .rs1(rs1), .rs2(rs2),
        .use_rs1(use_rs1), .use_rs2(use_rs2),
        .e0_valid(e0_valid), .e0_we(e0_we),
        .e0_ready(e0_result_ready), .e0_rd(e0_rd),
        .m0_valid(m0_valid), .m0_we(m0_we),
        .m0_ready(m0_result_ready), .m0_rd(m0_rd),
        .m1_valid(m1_valid), .m1_we(m1_we),
        .m1_ready(m1_result_ready), .m1_rd(m1_rd),
        .stall(stall)
    );

    execute_unit_v2 u_execute (
        .pc(pc), .uop(uop), .alu_op(alu_op),
        .branch_cond(branch_cond),
        .operand1(operand1), .operand2(operand2),
        .immediate(immediate),
        .src1_is_pc(src1_is_pc), .src2_is_imm(src2_is_imm),
        .target_is_rs1(target_is_rs1), .link(link),
        .result(result), .branch_taken(branch_taken),
        .branch_target(branch_target)
    );

    assign store_data = operand2;
endmodule
