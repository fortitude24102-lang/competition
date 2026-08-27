`include "core_v2_defs.vh"

module csr_access_v2(
    input      [1:0]  csr_op,
    input      [31:0] csr_read_data,
    input      [31:0] data_operand,
    input      [31:0] mask_operand,
    output            gpr_write,
    output     [31:0] gpr_data,
    output            csr_write,
    output     [31:0] csr_write_data,
    output     [31:0] csr_write_mask
);
    assign gpr_write = csr_op != `V2_CSR_OP_NONE;
    assign gpr_data = csr_read_data;
    assign csr_write = csr_op == `V2_CSR_OP_WRITE ||
                       csr_op == `V2_CSR_OP_EXCHANGE;
    assign csr_write_data = csr_write ? data_operand : 32'b0;
    assign csr_write_mask = csr_op == `V2_CSR_OP_WRITE
        ? 32'hffffffff
        : csr_op == `V2_CSR_OP_EXCHANGE
            ? mask_operand
            : 32'b0;
endmodule
