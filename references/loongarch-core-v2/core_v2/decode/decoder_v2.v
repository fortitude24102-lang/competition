`include "core_v2_defs.vh"

module decoder_v2(
    input      [31:0] inst,
    output reg [3:0]  uop,
    output reg [3:0]  alu_op,
    output reg [2:0]  imm_type,
    output reg [2:0]  branch_cond,
    output reg [4:0]  rs1,
    output reg [4:0]  rs2,
    output reg [4:0]  rd,
    output reg        use_rs1,
    output reg        use_rs2,
    output reg        src1_is_pc,
    output reg        src2_is_imm,
    output reg        reg_write,
    output reg        link,
    output reg        target_is_rs1,
    output reg [1:0]  mem_width,
    output reg        mem_signed,
    output reg        illegal
);
    wire [5:0]  opcode_6  = inst[31:26];
    wire [9:0]  opcode_10 = inst[31:22];
    wire [16:0] opcode_17 = inst[31:15];
    wire [4:0]  inst_rd   = inst[4:0];
    wire [4:0]  inst_rj   = inst[9:5];
    wire [4:0]  inst_rk   = inst[14:10];

    always @(*) begin
        uop = `V2_UOP_NONE;
        alu_op = `V2_ALU_ADD;
        imm_type = `V2_IMM_NONE;
        branch_cond = `V2_BR_NONE;
        rs1 = inst_rj;
        rs2 = inst_rk;
        rd = inst_rd;
        use_rs1 = 1'b0;
        use_rs2 = 1'b0;
        src1_is_pc = 1'b0;
        src2_is_imm = 1'b0;
        reg_write = 1'b0;
        link = 1'b0;
        target_is_rs1 = 1'b0;
        mem_width = `V2_MEM_WORD;
        mem_signed = 1'b1;
        illegal = 1'b0;

        case (opcode_17)
            17'b00000000000100000: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_ADD;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000100010: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SUB;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000100100: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SLT;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000100101: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SLTU; use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000101000: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_NOR;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000101001: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_AND;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000101010: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_OR;   use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000101011: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_XOR;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000101110: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SLL;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000101111: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SRL;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000110000: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SRA;  use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000000111000: begin uop = `V2_UOP_MUL; use_rs1 = 1'b1; use_rs2 = 1'b1; reg_write = 1'b1; end
            17'b00000000010000001: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SLL;  imm_type = `V2_IMM_UI5; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
            17'b00000000010001001: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SRL;  imm_type = `V2_IMM_UI5; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
            17'b00000000010010001: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SRA;  imm_type = `V2_IMM_UI5; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
            default: begin
                case (opcode_10)
                    10'b0000001010: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_ADD;  imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
                    10'b0000001000: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SLT;  imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
                    10'b0000001001: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_SLTU; imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
                    10'b0000001101: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_AND;  imm_type = `V2_IMM_UI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
                    10'b0000001110: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_OR;   imm_type = `V2_IMM_UI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
                    10'b0000001111: begin uop = `V2_UOP_ALU; alu_op = `V2_ALU_XOR;  imm_type = `V2_IMM_UI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; end
                    10'b0010100000: begin uop = `V2_UOP_LOAD; imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; mem_width = `V2_MEM_BYTE; mem_signed = 1'b1; end
                    10'b0010100001: begin uop = `V2_UOP_LOAD; imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; mem_width = `V2_MEM_HALF; mem_signed = 1'b1; end
                    10'b0010100010: begin uop = `V2_UOP_LOAD; imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; mem_width = `V2_MEM_WORD; mem_signed = 1'b1; end
                    10'b0010101000: begin uop = `V2_UOP_LOAD; imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; mem_width = `V2_MEM_BYTE; mem_signed = 1'b0; end
                    10'b0010101001: begin uop = `V2_UOP_LOAD; imm_type = `V2_IMM_SI12; use_rs1 = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1; mem_width = `V2_MEM_HALF; mem_signed = 1'b0; end
                    10'b0010100100: begin uop = `V2_UOP_STORE; imm_type = `V2_IMM_SI12; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; src2_is_imm = 1'b1; mem_width = `V2_MEM_BYTE; end
                    10'b0010100101: begin uop = `V2_UOP_STORE; imm_type = `V2_IMM_SI12; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; src2_is_imm = 1'b1; mem_width = `V2_MEM_HALF; end
                    10'b0010100110: begin uop = `V2_UOP_STORE; imm_type = `V2_IMM_SI12; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; src2_is_imm = 1'b1; mem_width = `V2_MEM_WORD; end
                    default: begin
                        case (opcode_6)
                            6'b010110: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_EQ;  imm_type = `V2_IMM_OFFS16; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; end
                            6'b010111: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_NE;  imm_type = `V2_IMM_OFFS16; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; end
                            6'b011000: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_LT;  imm_type = `V2_IMM_OFFS16; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; end
                            6'b011001: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_GE;  imm_type = `V2_IMM_OFFS16; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; end
                            6'b011010: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_LTU; imm_type = `V2_IMM_OFFS16; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; end
                            6'b011011: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_GEU; imm_type = `V2_IMM_OFFS16; rs2 = inst_rd; use_rs1 = 1'b1; use_rs2 = 1'b1; end
                            6'b010100: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_ALWAYS; imm_type = `V2_IMM_OFFS26; end
                            6'b010101: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_ALWAYS; imm_type = `V2_IMM_OFFS26; rd = 5'd1; reg_write = 1'b1; link = 1'b1; end
                            6'b010011: begin uop = `V2_UOP_BRANCH; branch_cond = `V2_BR_ALWAYS; imm_type = `V2_IMM_OFFS16; use_rs1 = 1'b1; reg_write = 1'b1; link = 1'b1; target_is_rs1 = 1'b1; end
                            default: begin
                                if (inst[31:25] == 7'b0001010) begin
                                    uop = `V2_UOP_ALU; imm_type = `V2_IMM_SI20; src2_is_imm = 1'b1; reg_write = 1'b1;
                                end else if (inst[31:25] == 7'b0001110) begin
                                    uop = `V2_UOP_ALU; imm_type = `V2_IMM_SI20; src1_is_pc = 1'b1; src2_is_imm = 1'b1; reg_write = 1'b1;
                                end else begin
                                    illegal = 1'b1;
                                end
                            end
                        endcase
                    end
                endcase
            end
        endcase
    end
endmodule
