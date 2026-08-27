`include "core_v2_defs.vh"

module integer_pipeline_v2(
    input         clk,
    input         reset,
    input         input_valid,
    output        input_ready,
    input  [31:0] input_pc,
    input  [31:0] input_inst,
    input         input_error,
    input  [7:0]  hardware_interrupt,
    output        commit_valid,
    input         commit_ready,
    output [31:0] commit_pc,
    output [31:0] commit_inst,
    output        commit_we,
    output [4:0]  commit_rd,
    output [31:0] commit_data,
    output        commit_exception,
    output [5:0]  commit_ecode,
    output        commit_badv_valid,
    output [31:0] commit_badv,
    output        redirect_valid,
    output [31:0] redirect_target,
    output        data_request_valid,
    input         data_request_ready,
    output        data_request_write,
    output [31:0] data_request_address,
    output [3:0]  data_request_strobe,
    output [31:0] data_request_data,
    input         data_response_valid,
    output        data_response_ready,
    input  [31:0] data_response_data,
    input         data_response_error
);
    reg d0_valid_q;
    reg [31:0] d0_pc_q;
    reg [31:0] d0_inst_q;
    reg d0_error_q;
    reg d0_system_q;

    reg d1_valid_q;
    reg [31:0] d1_pc_q;
    reg [31:0] d1_inst_q;
    reg d1_exception_q;
    reg [5:0] d1_ecode_q;
    reg d1_badv_valid_q;
    reg [31:0] d1_badv_q;
    reg [3:0] d1_uop_q;
    reg [3:0] d1_alu_op_q;
    reg [2:0] d1_branch_cond_q;
    reg [4:0] d1_rd_q;
    reg d1_we_q;
    reg d1_link_q;
    reg d1_target_is_rs1_q;
    reg d1_src1_is_pc_q;
    reg d1_src2_is_imm_q;
    reg [2:0] d1_imm_type_q;
    reg [2:0] d1_forward_sel1_q;
    reg [2:0] d1_forward_sel2_q;
    reg [1:0] d1_mem_width_q;
    reg d1_mem_signed_q;
    reg [31:0] d1_operand1_q;
    reg [31:0] d1_operand2_q;

    reg e0_valid_q;
    reg [31:0] e0_pc_q;
    reg [31:0] e0_inst_q;
    reg e0_exception_q;
    reg [5:0] e0_ecode_q;
    reg e0_badv_valid_q;
    reg [31:0] e0_badv_q;
    reg [3:0] e0_uop_q;
    reg [3:0] e0_alu_op_q;
    reg [2:0] e0_branch_cond_q;
    reg [1:0] e0_mem_width_q;
    reg e0_mem_signed_q;
    reg [4:0] e0_rd_q;
    reg e0_we_q;
    reg e0_link_q;
    reg [31:0] e0_operand1_q;
    reg [31:0] e0_operand2_q;
    reg [31:0] e0_store_data_q;
    reg [31:0] e0_branch_target_q;
    reg [31:0] e0_link_value_q;

    reg m0_valid_q;
    reg [31:0] m0_pc_q;
    reg [31:0] m0_inst_q;
    reg m0_exception_q;
    reg [5:0] m0_ecode_q;
    reg m0_badv_valid_q;
    reg [31:0] m0_badv_q;
    reg [3:0] m0_uop_q;
    reg [1:0] m0_mem_width_q;
    reg m0_mem_signed_q;
    reg [4:0] m0_rd_q;
    reg m0_we_q;
    reg [31:0] m0_data_q;
    reg [31:0] m0_store_data_q;
    reg [31:0] m0_next_pc_q;
    reg m0_branch_redirect_q;
    reg [31:0] m0_branch_target_q;

    reg m1_valid_q;
    reg [31:0] m1_pc_q;
    reg [31:0] m1_inst_q;
    reg m1_exception_q;
    reg [5:0] m1_ecode_q;
    reg m1_badv_valid_q;
    reg [31:0] m1_badv_q;
    reg [4:0] m1_rd_q;
    reg m1_we_q;
    reg [31:0] m1_data_q;
    reg [31:0] m1_next_pc_q;

    reg c0_valid_q;
    reg [31:0] c0_pc_q;
    reg [31:0] c0_inst_q;
    reg c0_exception_q;
    reg [5:0] c0_ecode_q;
    reg c0_badv_valid_q;
    reg [31:0] c0_badv_q;
    reg [4:0] c0_rd_q;
    reg c0_we_q;
    reg [31:0] c0_data_q;
    reg [31:0] c0_next_pc_q;

    wire [3:0] d0_uop;
    wire [3:0] d0_alu_op;
    wire [2:0] d0_imm_type;
    wire [2:0] d0_branch_cond;
    wire [4:0] d0_rs1;
    wire [4:0] d0_rs2;
    wire [4:0] d0_rd;
    wire d0_use_rs1;
    wire d0_use_rs2;
    wire d0_src1_is_pc;
    wire d0_src2_is_imm;
    wire d0_reg_write;
    wire d0_link;
    wire d0_target_is_rs1;
    wire [1:0] d0_mem_width;
    wire d0_mem_signed;
    wire d0_illegal;
    wire [31:0] d1_immediate;
    wire [31:0] rf_data1;
    wire [31:0] rf_data2;
    wire [31:0] rf_rk_data;
    wire [31:0] rf_rd_data;
    wire [31:0] rf_system_data;
    wire [31:0] rf_system_mask;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] unused_rf_data;
    /* verilator lint_on UNUSEDSIGNAL */
    wire d0_rs2_is_rd;
    wire input_system_recognized;
    wire [1:0] unused_system_csr_op;
    wire unused_system_cpucfg;
    wire unused_system_ertn_decode;
    wire unused_system_exception;
    wire [5:0] unused_system_ecode;
    wire [13:0] unused_system_csr_addr;
    wire [13:0] system_csr_read_addr;
    wire [4:0] unused_system_rd;
    wire [4:0] unused_system_data_source;
    wire [4:0] unused_system_mask_source;
    wire [31:0] csr_read_data;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] unused_csr_read_data;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] d1_forwarded1;
    wire [31:0] d1_forwarded2;
    wire [4:0] d0_forward_match1;
    wire [4:0] d0_forward_match2;
    reg [2:0] d0_forward_sel1;
    reg [2:0] d0_forward_sel2;
    wire [31:0] d1_operand1;
    wire [31:0] d1_operand2;
    wire [31:0] d1_branch_base;
    wire [31:0] d1_branch_target;
    wire [31:0] d1_link_value;
    wire [31:0] e0_result;
    wire [31:0] e0_bypass_result;
    wire [31:0] e0_alu_result;
    wire [31:0] e0_alu_bypass_result;
    wire e0_branch_taken;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] unused_e0_branch_target;
    wire [31:0] unused_e0_link_value;
    /* verilator lint_on UNUSEDSIGNAL */
    wire c0_allowin;
    wire m1_allowin;
    wire m0_allowin;
    wire m0_ready_go;
    wire e0_allowin;
    wire d1_allowin;
    wire d0_allowin;
    wire d0_issue_stall;
    wire input_payload_ready;
    wire memory_barrier;
    wire exception_barrier;
    wire interrupt_barrier;
    wire d1_memory;
    wire e0_memory;
    wire m0_memory;
    /* verilator lint_off UNUSEDSIGNAL */
    wire lsu_request_ready;
    /* verilator lint_on UNUSEDSIGNAL */
    wire lsu_completion_valid;
    wire [31:0] lsu_completion_data;
    wire lsu_completion_misaligned;
    wire lsu_completion_bus_error;
    wire d0_system;
    wire older_pipeline_empty;
    wire system_dispatch;
    wire system_accept;
    wire system_input_ready;
    wire system_commit_valid;
    wire [31:0] system_commit_pc;
    wire [31:0] system_commit_inst;
    wire system_commit_recognized;
    wire system_commit_gpr_write;
    wire [4:0] system_commit_rd;
    wire [31:0] system_commit_data;
    wire system_commit_exception;
    wire [5:0] system_commit_ecode;
    wire system_csr_write_valid;
    wire [13:0] system_csr_write_addr;
    wire [31:0] system_csr_write_data;
    wire [31:0] system_csr_write_mask;
    wire system_ertn_valid;
    wire [31:0] exception_entry;
    wire [31:0] ertn_entry;
    wire interrupt_pending;
    wire commit_fire;
    wire branch_redirect_valid;
    wire control_redirect_valid;
    wire [31:0] control_redirect_target;
    wire csr_exception_valid;
    wire [5:0] csr_exception_ecode;
    wire [8:0] csr_exception_esubcode;
    wire [31:0] csr_exception_pc;
    wire csr_badv_valid;
    wire [31:0] csr_exception_badv;
    wire csr_ertn_valid;
    wire [2:0] unused_redirect_kind;
    wire [1:0] unused_current_plv;
    wire unused_interrupt_enable;
    wire unused_direct_address;
    wire unused_paging_enable;
    wire d1_shift_result;
    wire e0_shift_result;

    localparam [2:0] V2_FWD_RF = 3'd0;
    localparam [2:0] V2_FWD_E0 = 3'd1;
    localparam [2:0] V2_FWD_M0 = 3'd2;
    localparam [2:0] V2_FWD_M1 = 3'd3;
    localparam [2:0] V2_FWD_C0 = 3'd4;

    function [31:0] select_forward_data;
        input [2:0] select;
        input [31:0] register_data;
        input [31:0] e0_data;
        input [31:0] m0_data;
        input [31:0] m1_data;
        input [31:0] c0_data;
        begin
            case (select)
                V2_FWD_E0: select_forward_data = e0_data;
                V2_FWD_M0: select_forward_data = m0_data;
                V2_FWD_M1: select_forward_data = m1_data;
                V2_FWD_C0: select_forward_data = c0_data;
                default:   select_forward_data = register_data;
            endcase
        end
    endfunction

    function [31:0] select_late_forward_data;
        input [2:0] select;
        input [31:0] register_data;
        input [31:0] m0_data;
        input [31:0] m1_data;
        input [31:0] c0_data;
        begin
            case (select)
                V2_FWD_M0: select_late_forward_data = m0_data;
                V2_FWD_M1: select_late_forward_data = m1_data;
                V2_FWD_C0: select_late_forward_data = c0_data;
                default:   select_late_forward_data = register_data;
            endcase
        end
    endfunction

    assign c0_allowin = !c0_valid_q || commit_ready;
    assign m1_allowin = !m1_valid_q || c0_allowin;
    assign d1_memory = d1_valid_q && !d1_exception_q &&
                       (d1_uop_q == `V2_UOP_LOAD ||
                        d1_uop_q == `V2_UOP_STORE);
    assign e0_memory = e0_valid_q && !e0_exception_q &&
                       (e0_uop_q == `V2_UOP_LOAD ||
                        e0_uop_q == `V2_UOP_STORE);
    assign m0_memory = m0_valid_q && !m0_exception_q &&
                       (m0_uop_q == `V2_UOP_LOAD ||
                        m0_uop_q == `V2_UOP_STORE);
    assign memory_barrier = d1_memory || e0_memory || m0_memory;
    assign exception_barrier =
        (d0_valid_q && (d0_error_q || d0_illegal)) ||
        (d1_valid_q && d1_exception_q) ||
        (e0_valid_q && e0_exception_q) ||
        (m0_valid_q && m0_exception_q) ||
        (m1_valid_q && m1_exception_q) ||
        (c0_valid_q && c0_exception_q);
    assign interrupt_barrier = interrupt_pending &&
        (d0_valid_q || d1_valid_q || e0_valid_q || m0_valid_q ||
         m1_valid_q || c0_valid_q || system_commit_valid);
    assign m0_ready_go = !m0_memory || lsu_completion_valid;
    assign m0_allowin = !m0_valid_q || (m0_ready_go && m1_allowin);
    assign e0_allowin = !e0_valid_q || m0_allowin;
    assign d1_allowin = !d1_valid_q || e0_allowin;
    assign d0_system = d0_valid_q && !d0_error_q && d0_system_q;
    assign older_pipeline_empty = !d1_valid_q && !e0_valid_q &&
                                  !m0_valid_q && !m1_valid_q &&
                                  !c0_valid_q;
    assign system_dispatch = d0_system && older_pipeline_empty;
    assign system_accept = system_dispatch && system_input_ready;
    assign d0_allowin = !d0_valid_q || system_accept ||
                         (d1_allowin && !memory_barrier && !d0_system &&
                          !d0_issue_stall);
    assign input_payload_ready = d0_allowin && !d0_system &&
                          !system_commit_valid && !memory_barrier &&
                          !exception_barrier && !interrupt_barrier;
    assign input_ready = input_payload_ready && !redirect_valid;

    system_decoder_v2 u_system_decoder (
        .inst(input_inst), .recognized(input_system_recognized),
        .csr_op(unused_system_csr_op),
        .cpucfg(unused_system_cpucfg),
        .ertn(unused_system_ertn_decode),
        .exception(unused_system_exception),
        .exception_ecode(unused_system_ecode),
        .csr_addr(unused_system_csr_addr), .rd(unused_system_rd),
        .data_source(unused_system_data_source),
        .mask_source(unused_system_mask_source)
    );

    decoder_v2 u_decoder (
        .inst(d0_inst_q),
        .uop(d0_uop), .alu_op(d0_alu_op),
        .imm_type(d0_imm_type), .branch_cond(d0_branch_cond),
        .rs1(d0_rs1), .rs2(d0_rs2), .rd(d0_rd),
        .use_rs1(d0_use_rs1), .use_rs2(d0_use_rs2),
        .src1_is_pc(d0_src1_is_pc),
        .src2_is_imm(d0_src2_is_imm),
        .reg_write(d0_reg_write), .link(d0_link),
        .target_is_rs1(d0_target_is_rs1),
        .mem_width(d0_mem_width), .mem_signed(d0_mem_signed),
        .illegal(d0_illegal)
    );

    immediate_gen_v2 u_immediate (
        .inst(d1_inst_q[25:0]), .imm_type(d1_imm_type_q),
        .immediate(d1_immediate)
    );

    regfile_v2 #(
        .WRITE_THROUGH(1)
    ) u_regfile (
        .clk(clk),
        .raddr_0(d0_inst_q[9:5]),
        .raddr_1(d0_inst_q[14:10]),
        .raddr_2(d0_inst_q[4:0]),
        .raddr_3(5'b0),
        .rdata_0(rf_data1), .rdata_1(rf_rk_data),
        .rdata_2(rf_rd_data), .rdata_3(unused_rf_data),
        .we_0(commit_valid && commit_ready && commit_we &&
              !commit_exception),
        .waddr_0(commit_rd), .wdata_0(commit_data),
        .we_1(1'b0), .waddr_1(5'b0), .wdata_1(32'b0)
    );

    assign d0_rs2_is_rd = d0_uop == `V2_UOP_STORE ||
        (d0_uop == `V2_UOP_BRANCH && d0_use_rs2);
    assign rf_data2 = d0_rs2_is_rd ? rf_rd_data : rf_rk_data;
    assign rf_system_data = d0_inst_q[31:24] == 8'h04 &&
                            d0_inst_q[9:5] != 5'b0
        ? rf_rd_data : rf_data1;
    assign rf_system_mask = rf_data1;

    assign d0_forward_match1[4] = d0_use_rs1 && d0_rs1 != 5'b0 &&
        d1_valid_q && d1_we_q && !d1_exception_q && d1_rd_q == d0_rs1;
    assign d0_forward_match1[3] = d0_use_rs1 && d0_rs1 != 5'b0 &&
        e0_valid_q && e0_we_q && !e0_exception_q && e0_rd_q == d0_rs1;
    assign d0_forward_match1[2] = d0_use_rs1 && d0_rs1 != 5'b0 &&
        m0_valid_q && m0_we_q && !m0_exception_q && m0_rd_q == d0_rs1;
    assign d0_forward_match1[1] = d0_use_rs1 && d0_rs1 != 5'b0 &&
        m1_valid_q && m1_we_q && !m1_exception_q && m1_rd_q == d0_rs1;
    assign d0_forward_match1[0] = d0_use_rs1 && d0_rs1 != 5'b0 &&
        c0_valid_q && !c0_allowin && c0_we_q && !c0_exception_q &&
        c0_rd_q == d0_rs1;
    assign d0_forward_match2[4] = d0_use_rs2 && d0_rs2 != 5'b0 &&
        d1_valid_q && d1_we_q && !d1_exception_q && d1_rd_q == d0_rs2;
    assign d0_forward_match2[3] = d0_use_rs2 && d0_rs2 != 5'b0 &&
        e0_valid_q && e0_we_q && !e0_exception_q && e0_rd_q == d0_rs2;
    assign d0_forward_match2[2] = d0_use_rs2 && d0_rs2 != 5'b0 &&
        m0_valid_q && m0_we_q && !m0_exception_q && m0_rd_q == d0_rs2;
    assign d0_forward_match2[1] = d0_use_rs2 && d0_rs2 != 5'b0 &&
        m1_valid_q && m1_we_q && !m1_exception_q && m1_rd_q == d0_rs2;
    assign d0_forward_match2[0] = d0_use_rs2 && d0_rs2 != 5'b0 &&
        c0_valid_q && !c0_allowin && c0_we_q && !c0_exception_q &&
        c0_rd_q == d0_rs2;

    assign d1_shift_result = d1_valid_q && !d1_exception_q &&
        d1_uop_q == `V2_UOP_ALU &&
        (d1_alu_op_q == `V2_ALU_SLL ||
         d1_alu_op_q == `V2_ALU_SRA ||
         d1_alu_op_q == `V2_ALU_SRL);
    assign e0_shift_result = e0_valid_q && !e0_exception_q &&
        e0_uop_q == `V2_UOP_ALU &&
        (e0_alu_op_q == `V2_ALU_SLL ||
         e0_alu_op_q == `V2_ALU_SRA ||
         e0_alu_op_q == `V2_ALU_SRL);
    assign d0_issue_stall =
        (d0_target_is_rs1 &&
         (d0_forward_match1[4] ||
          (d0_forward_match1[3] && !e0_allowin))) ||
        (d1_shift_result &&
         (d0_forward_match1[4] || d0_forward_match2[4])) ||
        (e0_shift_result && !e0_allowin &&
         (d0_forward_match1[3] || d0_forward_match2[3]));

    always @(*) begin
        d0_forward_sel1 = V2_FWD_RF;
        if (d0_forward_match1[0])
            d0_forward_sel1 = V2_FWD_C0;
        if (d0_forward_match1[1])
            d0_forward_sel1 = m1_allowin ? V2_FWD_C0 : V2_FWD_M1;
        if (d0_forward_match1[2])
            d0_forward_sel1 = m0_allowin ? V2_FWD_M1 : V2_FWD_M0;
        if (d0_forward_match1[3])
            d0_forward_sel1 = e0_allowin ? V2_FWD_M0 : V2_FWD_E0;
        if (d0_forward_match1[4])
            d0_forward_sel1 = V2_FWD_E0;

        d0_forward_sel2 = V2_FWD_RF;
        if (d0_forward_match2[0])
            d0_forward_sel2 = V2_FWD_C0;
        if (d0_forward_match2[1])
            d0_forward_sel2 = m1_allowin ? V2_FWD_C0 : V2_FWD_M1;
        if (d0_forward_match2[2])
            d0_forward_sel2 = m0_allowin ? V2_FWD_M1 : V2_FWD_M0;
        if (d0_forward_match2[3])
            d0_forward_sel2 = e0_allowin ? V2_FWD_M0 : V2_FWD_E0;
        if (d0_forward_match2[4])
            d0_forward_sel2 = V2_FWD_E0;
    end

    assign d1_forwarded1 = select_forward_data(
        d1_forward_sel1_q, d1_operand1_q, e0_bypass_result,
        m0_data_q, m1_data_q, c0_data_q);
    assign d1_forwarded2 = select_forward_data(
        d1_forward_sel2_q, d1_operand2_q, e0_bypass_result,
        m0_data_q, m1_data_q, c0_data_q);

    assign d1_operand1 = d1_src1_is_pc_q
        ? d1_pc_q : d1_forwarded1;
    assign d1_operand2 = d1_src2_is_imm_q
        ? d1_immediate : d1_forwarded2;

    assign d1_branch_base = d1_target_is_rs1_q
        ? select_late_forward_data(
            d1_forward_sel1_q, d1_operand1_q,
            m0_data_q, m1_data_q, c0_data_q)
        : d1_pc_q;
    assign d1_branch_target = d1_branch_base + d1_immediate;
    assign d1_link_value = d1_pc_q + 32'd4;

    alu_v2 u_alu (
        .operand_a(e0_operand1_q), .operand_b(e0_operand2_q),
        .alu_op(e0_alu_op_q), .result(e0_alu_result),
        .bypass_result(e0_alu_bypass_result)
    );

    branch_unit_v2 u_branch (
        .condition(e0_branch_cond_q),
        .operand1(e0_operand1_q), .operand2(e0_operand2_q),
        .pc(32'b0), .immediate(32'b0),
        .target_is_rs1(1'b0),
        .taken(e0_branch_taken), .target(unused_e0_branch_target),
        .link_value(unused_e0_link_value)
    );

    lsu_request_v2 u_lsu (
        .clk(clk), .reset(reset),
        .request_valid(m0_memory),
        .request_ready(lsu_request_ready),
        .request_write(m0_uop_q == `V2_UOP_STORE),
        .request_address(m0_data_q),
        .request_width(m0_mem_width_q),
        .request_signed(m0_mem_signed_q),
        .request_write_data(m0_store_data_q),
        .bus_request_valid(data_request_valid),
        .bus_request_ready(data_request_ready),
        .bus_request_write(data_request_write),
        .bus_request_address(data_request_address),
        .bus_request_strobe(data_request_strobe),
        .bus_request_data(data_request_data),
        .bus_response_valid(data_response_valid),
        .bus_response_ready(data_response_ready),
        .bus_response_data(data_response_data),
        .bus_response_error(data_response_error),
        .completion_valid(lsu_completion_valid),
        .completion_ready(m0_memory && m1_allowin),
        .completion_data(lsu_completion_data),
        .completion_misaligned(lsu_completion_misaligned),
        .completion_bus_error(lsu_completion_bus_error)
    );

    system_pipeline_v2 u_system_pipeline (
        .clk(clk), .reset(reset),
        .input_valid(system_dispatch),
        .input_ready(system_input_ready),
        .input_pc(d0_pc_q), .input_inst(d0_inst_q),
        .input_data_operand(rf_system_data),
        .input_mask_operand(rf_system_mask),
        .csr_read_addr(system_csr_read_addr),
        .csr_read_data(csr_read_data),
        .commit_valid(system_commit_valid),
        .commit_ready(commit_ready),
        .commit_pc(system_commit_pc),
        .commit_inst(system_commit_inst),
        .commit_recognized(system_commit_recognized),
        .commit_gpr_write(system_commit_gpr_write),
        .commit_rd(system_commit_rd),
        .commit_gpr_data(system_commit_data),
        .commit_exception(system_commit_exception),
        .commit_ecode(system_commit_ecode),
        .csr_write_valid(system_csr_write_valid),
        .csr_write_addr(system_csr_write_addr),
        .csr_write_data(system_csr_write_data),
        .csr_write_mask(system_csr_write_mask),
        .ertn_valid(system_ertn_valid)
    );

    csr_file_v2 u_csr_file (
        .clk(clk), .reset(reset),
        .read_addr(system_csr_read_addr),
        .read_data(unused_csr_read_data),
        .read_data_registered(csr_read_data),
        .write_valid(system_csr_write_valid),
        .write_addr(system_csr_write_addr),
        .write_data(system_csr_write_data),
        .write_mask(system_csr_write_mask),
        .exception_valid(csr_exception_valid),
        .exception_ecode(csr_exception_ecode),
        .exception_esubcode(csr_exception_esubcode),
        .exception_pc(csr_exception_pc),
        .badv_valid(csr_badv_valid),
        .exception_badv(csr_exception_badv),
        .ertn_valid(csr_ertn_valid),
        .hardware_interrupt(hardware_interrupt), .timer_interrupt(1'b0),
        .ipi_interrupt(1'b0),
        .exception_entry(exception_entry),
        .ertn_entry(ertn_entry),
        .interrupt_pending(interrupt_pending),
        .current_plv(unused_current_plv),
        .interrupt_enable(unused_interrupt_enable),
        .direct_address(unused_direct_address),
        .paging_enable(unused_paging_enable)
    );

    assign commit_fire = commit_valid && commit_ready;

    exception_control_v2 u_exception_control (
        .boundary_valid(commit_fire), .boundary_pc(commit_pc),
        .boundary_next_pc(system_commit_valid
            ? system_commit_pc + 32'd4 : c0_next_pc_q),
        .instruction_exception(commit_exception),
        .instruction_ecode(commit_ecode),
        .instruction_esubcode(9'b0),
        .instruction_badv_valid(commit_badv_valid),
        .instruction_badv(commit_badv),
        .instruction_ertn(system_ertn_valid),
        .interrupt_pending(interrupt_pending),
        .exception_entry(exception_entry), .ertn_entry(ertn_entry),
        .csr_exception_valid(csr_exception_valid),
        .csr_exception_ecode(csr_exception_ecode),
        .csr_exception_esubcode(csr_exception_esubcode),
        .csr_exception_pc(csr_exception_pc),
        .csr_badv_valid(csr_badv_valid),
        .csr_exception_badv(csr_exception_badv),
        .csr_ertn_valid(csr_ertn_valid),
        .redirect_valid(control_redirect_valid),
        .redirect_kind(unused_redirect_kind),
        .redirect_target(control_redirect_target)
    );

    assign branch_redirect_valid = m0_valid_q && !m0_exception_q &&
        m0_branch_redirect_q && m1_allowin;
    assign e0_result = e0_link_q ? e0_link_value_q : e0_alu_result;
    assign e0_bypass_result = e0_link_q
        ? e0_link_value_q : e0_alu_bypass_result;
    assign redirect_valid = control_redirect_valid || branch_redirect_valid;
    assign redirect_target = control_redirect_valid
        ? control_redirect_target
        : branch_redirect_valid ? m0_branch_target_q : 32'b0;

    assign commit_valid = system_commit_valid || c0_valid_q;
    assign commit_pc = system_commit_valid
        ? system_commit_pc : c0_pc_q;
    assign commit_inst = system_commit_valid
        ? system_commit_inst : c0_inst_q;
    assign commit_we = system_commit_valid
        ? (system_commit_recognized && system_commit_gpr_write &&
           system_commit_rd != 5'b0 && !system_commit_exception)
        : (c0_we_q && !c0_exception_q);
    assign commit_rd = system_commit_valid
        ? system_commit_rd : c0_rd_q;
    assign commit_data = system_commit_valid
        ? system_commit_data : c0_data_q;
    assign commit_exception = system_commit_valid
        ? system_commit_exception : c0_exception_q;
    assign commit_ecode = commit_exception
        ? (system_commit_valid ? system_commit_ecode : c0_ecode_q)
        : 6'b0;
    assign commit_badv_valid = !system_commit_valid &&
                               c0_exception_q && c0_badv_valid_q;
    assign commit_badv = commit_badv_valid ? c0_badv_q : 32'b0;

    always @(posedge clk) begin
        if (reset) begin
            d0_valid_q <= 1'b0;
            d1_valid_q <= 1'b0;
            e0_valid_q <= 1'b0;
            m0_valid_q <= 1'b0;
            m1_valid_q <= 1'b0;
            c0_valid_q <= 1'b0;
        end else begin
            if (control_redirect_valid) begin
                d0_valid_q <= 1'b0;
                d1_valid_q <= 1'b0;
                e0_valid_q <= 1'b0;
                m0_valid_q <= 1'b0;
                m1_valid_q <= 1'b0;
                c0_valid_q <= 1'b0;
            end else if (redirect_valid)
                d0_valid_q <= 1'b0;
            else if (d0_allowin)
                d0_valid_q <= input_valid && input_ready;
            if (!control_redirect_valid && d1_allowin)
                d1_valid_q <= redirect_valid ? 1'b0
                              : (d0_valid_q && !memory_barrier &&
                                 !d0_system && !d0_issue_stall);
            if (!control_redirect_valid && e0_allowin)
                e0_valid_q <= redirect_valid ? 1'b0 : d1_valid_q;
            if (!control_redirect_valid && m0_allowin)
                m0_valid_q <= branch_redirect_valid ? 1'b0 : e0_valid_q;
            if (!control_redirect_valid && m1_allowin)
                m1_valid_q <= m0_valid_q && m0_ready_go;
            if (!control_redirect_valid && c0_allowin)
                c0_valid_q <= m1_valid_q;

            if (input_valid && input_payload_ready) begin
                d0_pc_q <= input_pc;
                d0_inst_q <= input_inst;
                d0_error_q <= input_error;
                d0_system_q <= input_system_recognized;
            end
            if (d1_allowin) begin
                d1_pc_q <= d0_pc_q;
                d1_inst_q <= d0_inst_q;
                d1_exception_q <= d0_error_q || d0_illegal ||
                                   (d0_uop != `V2_UOP_ALU &&
                                    d0_uop != `V2_UOP_BRANCH &&
                                    d0_uop != `V2_UOP_LOAD &&
                                    d0_uop != `V2_UOP_STORE);
                d1_ecode_q <= d0_error_q
                    ? `V2_ECODE_ADE : `V2_ECODE_INE;
                d1_badv_valid_q <= d0_error_q;
                d1_badv_q <= d0_pc_q;
                d1_uop_q <= d0_uop;
                d1_alu_op_q <= d0_alu_op;
                d1_branch_cond_q <= d0_branch_cond;
                d1_rd_q <= d0_rd;
                d1_we_q <= d0_reg_write;
                d1_link_q <= d0_link;
                d1_target_is_rs1_q <= d0_target_is_rs1;
                d1_src1_is_pc_q <= d0_src1_is_pc;
                d1_src2_is_imm_q <= d0_src2_is_imm;
                d1_imm_type_q <= d0_imm_type;
                d1_forward_sel1_q <= d0_forward_sel1;
                d1_forward_sel2_q <= d0_forward_sel2;
                d1_mem_width_q <= d0_mem_width;
                d1_mem_signed_q <= d0_mem_signed;
                d1_operand1_q <= rf_data1;
                d1_operand2_q <= rf_data2;
            end
            if (e0_allowin) begin
                e0_pc_q <= d1_pc_q;
                e0_inst_q <= d1_inst_q;
                e0_exception_q <= d1_exception_q;
                e0_ecode_q <= d1_ecode_q;
                e0_badv_valid_q <= d1_badv_valid_q;
                e0_badv_q <= d1_badv_q;
                e0_uop_q <= d1_uop_q;
                e0_alu_op_q <= d1_alu_op_q;
                e0_branch_cond_q <= d1_branch_cond_q;
                e0_mem_width_q <= d1_mem_width_q;
                e0_mem_signed_q <= d1_mem_signed_q;
                e0_rd_q <= d1_rd_q;
                e0_we_q <= d1_we_q;
                e0_link_q <= d1_link_q;
                e0_operand1_q <= d1_operand1;
                e0_operand2_q <= d1_operand2;
                e0_store_data_q <= d1_forwarded2;
                e0_branch_target_q <= d1_branch_target;
                e0_link_value_q <= d1_link_value;
            end
            if (m0_allowin) begin
                m0_pc_q <= e0_pc_q;
                m0_inst_q <= e0_inst_q;
                m0_exception_q <= e0_exception_q;
                m0_ecode_q <= e0_ecode_q;
                m0_badv_valid_q <= e0_badv_valid_q;
                m0_badv_q <= e0_badv_q;
                m0_uop_q <= e0_uop_q;
                m0_mem_width_q <= e0_mem_width_q;
                m0_mem_signed_q <= e0_mem_signed_q;
                m0_rd_q <= e0_rd_q;
                m0_we_q <= e0_we_q;
                m0_data_q <= e0_result;
                m0_store_data_q <= e0_store_data_q;
                m0_next_pc_q <= e0_link_value_q;
                m0_branch_redirect_q <=
                    e0_uop_q == `V2_UOP_BRANCH && e0_branch_taken;
                m0_branch_target_q <= e0_branch_target_q;
            end
            if (m1_allowin) begin
                m1_pc_q <= m0_pc_q;
                m1_inst_q <= m0_inst_q;
                m1_exception_q <= m0_exception_q ||
                                  (m0_memory &&
                                   (lsu_completion_misaligned ||
                                    lsu_completion_bus_error));
                m1_ecode_q <= m0_exception_q
                    ? m0_ecode_q
                    : lsu_completion_misaligned
                        ? `V2_ECODE_ALE
                        : lsu_completion_bus_error
                            ? `V2_ECODE_ADE : 6'b0;
                m1_badv_valid_q <= m0_exception_q
                    ? m0_badv_valid_q
                    : m0_memory &&
                      (lsu_completion_misaligned ||
                       lsu_completion_bus_error);
                m1_badv_q <= m0_exception_q ? m0_badv_q : m0_data_q;
                m1_rd_q <= m0_rd_q;
                m1_we_q <= m0_we_q;
                m1_data_q <= m0_memory &&
                             m0_uop_q == `V2_UOP_LOAD
                    ? lsu_completion_data : m0_data_q;
                m1_next_pc_q <= m0_branch_redirect_q
                    ? m0_branch_target_q : m0_next_pc_q;
            end
            if (c0_allowin) begin
                c0_pc_q <= m1_pc_q;
                c0_inst_q <= m1_inst_q;
                c0_exception_q <= m1_exception_q;
                c0_ecode_q <= m1_ecode_q;
                c0_badv_valid_q <= m1_badv_valid_q;
                c0_badv_q <= m1_badv_q;
                c0_rd_q <= m1_rd_q;
                c0_we_q <= m1_we_q;
                c0_data_q <= m1_data_q;
                c0_next_pc_q <= m1_next_pc_q;
            end
        end
    end
endmodule
