module system_pipeline_v2(
    input             clk,
    input             reset,
    input             input_valid,
    output            input_ready,
    input      [31:0] input_pc,
    input      [31:0] input_inst,
    input      [31:0] input_data_operand,
    input      [31:0] input_mask_operand,
    output     [13:0] csr_read_addr,
    input      [31:0] csr_read_data,
    output            commit_valid,
    input             commit_ready,
    output     [31:0] commit_pc,
    output     [31:0] commit_inst,
    output            commit_recognized,
    output            commit_gpr_write,
    output     [4:0]  commit_rd,
    output     [31:0] commit_gpr_data,
    output            commit_exception,
    output     [5:0]  commit_ecode,
    output            csr_write_valid,
    output     [13:0] csr_write_addr,
    output     [31:0] csr_write_data,
    output     [31:0] csr_write_mask,
    output            ertn_valid
);
    reg decode_valid_q;
    reg [31:0] decode_pc_q;
    reg [31:0] decode_inst_q;
    reg decode_recognized_q;
    reg [1:0] decode_csr_op_q;
    reg decode_cpucfg_q;
    reg decode_ertn_q;
    reg decode_exception_q;
    reg [5:0] decode_ecode_q;
    reg [13:0] decode_csr_addr_q;
    reg [4:0] decode_rd_q;
    reg [31:0] decode_data_operand_q;
    reg [31:0] decode_mask_operand_q;
    reg read_valid_q;

    reg valid_q;
    reg [31:0] pc_q;
    reg [31:0] inst_q;
    reg recognized_q;
    reg gpr_write_q;
    reg [4:0] rd_q;
    reg [31:0] gpr_data_q;
    reg exception_q;
    reg [5:0] ecode_q;
    reg csr_write_q;
    reg [13:0] csr_addr_q;
    reg [31:0] csr_data_q;
    reg [31:0] csr_mask_q;
    reg ertn_q;

    wire decode_recognized;
    wire [1:0] decode_csr_op;
    wire decode_cpucfg;
    wire decode_ertn;
    wire decode_exception;
    wire [5:0] decode_ecode;
    wire [13:0] decode_csr_addr;
    wire [4:0] decode_rd;
    wire [4:0] unused_decode_data_source;
    wire [4:0] unused_decode_mask_source;
    wire [31:0] cpucfg_value;
    wire csr_gpr_write;
    wire [31:0] csr_gpr_data;
    wire csr_write_internal;
    wire [31:0] csr_write_data_internal;
    wire [31:0] csr_write_mask_internal;

    system_decoder_v2 u_decoder (
        .inst(input_inst),
        .recognized(decode_recognized),
        .csr_op(decode_csr_op),
        .cpucfg(decode_cpucfg),
        .ertn(decode_ertn),
        .exception(decode_exception),
        .exception_ecode(decode_ecode),
        .csr_addr(decode_csr_addr),
        .rd(decode_rd),
        .data_source(unused_decode_data_source),
        .mask_source(unused_decode_mask_source)
    );

    cpucfg_table_v2 u_cpucfg (
        .index(decode_data_operand_q),
        .value(cpucfg_value)
    );

    csr_access_v2 u_csr_access (
        .csr_op(decode_csr_op_q),
        .csr_read_data(csr_read_data),
        .data_operand(decode_data_operand_q),
        .mask_operand(decode_mask_operand_q),
        .gpr_write(csr_gpr_write),
        .gpr_data(csr_gpr_data),
        .csr_write(csr_write_internal),
        .csr_write_data(csr_write_data_internal),
        .csr_write_mask(csr_write_mask_internal)
    );

    assign input_ready = !decode_valid_q && !read_valid_q && !valid_q;
    assign csr_read_addr = decode_csr_addr_q;
    assign commit_valid = valid_q;
    assign commit_pc = pc_q;
    assign commit_inst = inst_q;
    assign commit_recognized = recognized_q;
    assign commit_gpr_write = gpr_write_q && !exception_q;
    assign commit_rd = rd_q;
    assign commit_gpr_data = gpr_data_q;
    assign commit_exception = exception_q;
    assign commit_ecode = exception_q ? ecode_q : 6'b0;
    assign csr_write_valid = valid_q && commit_ready && csr_write_q &&
                             !exception_q;
    assign csr_write_addr = csr_addr_q;
    assign csr_write_data = csr_data_q;
    assign csr_write_mask = csr_mask_q;
    assign ertn_valid = valid_q && commit_ready && ertn_q && !exception_q;

    always @(posedge clk) begin
        if (reset) begin
            decode_valid_q <= 1'b0;
            read_valid_q <= 1'b0;
            valid_q <= 1'b0;
        end else begin
            if (valid_q && commit_ready)
                valid_q <= 1'b0;

            if (read_valid_q && !valid_q) begin
                read_valid_q <= 1'b0;
                valid_q <= 1'b1;
                pc_q <= decode_pc_q;
                inst_q <= decode_inst_q;
                recognized_q <= decode_recognized_q;
                gpr_write_q <= decode_cpucfg_q || csr_gpr_write;
                rd_q <= decode_rd_q;
                gpr_data_q <= decode_cpucfg_q
                    ? cpucfg_value : csr_gpr_data;
                exception_q <= decode_exception_q;
                ecode_q <= decode_ecode_q;
                csr_write_q <= csr_write_internal;
                csr_addr_q <= decode_csr_addr_q;
                csr_data_q <= csr_write_data_internal;
                csr_mask_q <= csr_write_mask_internal;
                ertn_q <= decode_ertn_q;
            end

            if (decode_valid_q && !read_valid_q && !valid_q) begin
                decode_valid_q <= 1'b0;
                read_valid_q <= 1'b1;
            end

            if (input_valid && input_ready) begin
                decode_valid_q <= 1'b1;
                decode_pc_q <= input_pc;
                decode_inst_q <= input_inst;
                decode_recognized_q <= decode_recognized;
                decode_csr_op_q <= decode_csr_op;
                decode_cpucfg_q <= decode_cpucfg;
                decode_ertn_q <= decode_ertn;
                decode_exception_q <= decode_exception;
                decode_ecode_q <= decode_ecode;
                decode_csr_addr_q <= decode_csr_addr;
                decode_rd_q <= decode_rd;
                decode_data_operand_q <= input_data_operand;
                decode_mask_operand_q <= input_mask_operand;
            end
        end
    end
endmodule
