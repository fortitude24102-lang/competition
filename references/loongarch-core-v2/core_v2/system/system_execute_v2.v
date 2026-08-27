module system_execute_v2(
    input      [31:0] inst,
    input      [31:0] data_operand,
    input      [31:0] mask_operand,
    input      [31:0] csr_read_data,
    output            recognized,
    output     [4:0]  data_source,
    output     [4:0]  mask_source,
    output     [4:0]  rd,
    output            gpr_write,
    output     [31:0] gpr_data,
    output            csr_write,
    output     [13:0] csr_addr,
    output     [31:0] csr_write_data,
    output     [31:0] csr_write_mask,
    output            exception,
    output     [5:0]  exception_ecode,
    output            ertn
);
    wire [1:0] csr_op;
    wire cpucfg;
    wire [31:0] cpucfg_value;
    wire csr_gpr_write;
    wire [31:0] csr_gpr_data;
    wire csr_write_internal;

    system_decoder_v2 u_decoder (
        .inst(inst), .recognized(recognized), .csr_op(csr_op),
        .cpucfg(cpucfg), .ertn(ertn), .exception(exception),
        .exception_ecode(exception_ecode), .csr_addr(csr_addr),
        .rd(rd), .data_source(data_source), .mask_source(mask_source)
    );

    cpucfg_table_v2 u_cpucfg (
        .index(data_operand),
        .value(cpucfg_value)
    );

    csr_access_v2 u_csr_access (
        .csr_op(csr_op), .csr_read_data(csr_read_data),
        .data_operand(data_operand), .mask_operand(mask_operand),
        .gpr_write(csr_gpr_write), .gpr_data(csr_gpr_data),
        .csr_write(csr_write_internal),
        .csr_write_data(csr_write_data),
        .csr_write_mask(csr_write_mask)
    );

    assign gpr_write = cpucfg || csr_gpr_write;
    assign gpr_data = cpucfg ? cpucfg_value : csr_gpr_data;
    assign csr_write = csr_write_internal;
endmodule
