`include "core_v2_defs.vh"

module immediate_gen_v2(
    input      [25:0] inst,
    input      [2:0]  imm_type,
    output reg [31:0] immediate
);
    always @(*) begin
        case (imm_type)
            `V2_IMM_SI12:
                immediate = {{20{inst[21]}}, inst[21:10]};
            `V2_IMM_UI12:
                immediate = {20'b0, inst[21:10]};
            `V2_IMM_UI5:
                immediate = {27'b0, inst[14:10]};
            `V2_IMM_SI20:
                immediate = {inst[24:5], 12'b0};
            `V2_IMM_OFFS16:
                immediate = {{14{inst[25]}}, inst[25:10], 2'b0};
            `V2_IMM_OFFS26:
                immediate = {{4{inst[9]}}, inst[9:0], inst[25:10], 2'b0};
            default:
                immediate = 32'b0;
        endcase
    end
endmodule
