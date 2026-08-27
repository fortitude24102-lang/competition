`include "core_v2_defs.vh"

module system_decoder_v2(
    input      [31:0] inst,
    output reg        recognized,
    output reg [1:0]  csr_op,
    output reg        cpucfg,
    output reg        ertn,
    output reg        exception,
    output reg [5:0]  exception_ecode,
    output reg [13:0] csr_addr,
    output reg [4:0]  rd,
    output reg [4:0]  data_source,
    output reg [4:0]  mask_source
);
    wire [4:0] inst_rd = inst[4:0];
    wire [4:0] inst_rj = inst[9:5];

    always @(*) begin
        recognized = 1'b0;
        csr_op = `V2_CSR_OP_NONE;
        cpucfg = 1'b0;
        ertn = 1'b0;
        exception = 1'b0;
        exception_ecode = 6'b0;
        csr_addr = 14'b0;
        rd = 5'b0;
        data_source = 5'b0;
        mask_source = 5'b0;

        if (inst[31:24] == 8'h04) begin
            recognized = 1'b1;
            csr_addr = inst[23:10];
            rd = inst_rd;
            if (inst_rj == 5'd0) begin
                csr_op = `V2_CSR_OP_READ;
            end else if (inst_rj == 5'd1) begin
                csr_op = `V2_CSR_OP_WRITE;
                data_source = inst_rd;
            end else begin
                csr_op = `V2_CSR_OP_EXCHANGE;
                data_source = inst_rd;
                mask_source = inst_rj;
            end
        end else if (inst[31:10] == 22'h00001b) begin
            recognized = 1'b1;
            cpucfg = 1'b1;
            rd = inst_rd;
            data_source = inst_rj;
        end else if (inst[31:15] == 17'b00000000001010110) begin
            recognized = 1'b1;
            exception = 1'b1;
            exception_ecode = `V2_ECODE_SYS;
        end else if (inst[31:15] == 17'b00000000001010100) begin
            recognized = 1'b1;
            exception = 1'b1;
            exception_ecode = `V2_ECODE_BRK;
        end else if (inst == 32'h06483800) begin
            recognized = 1'b1;
            ertn = 1'b1;
        end
    end
endmodule
