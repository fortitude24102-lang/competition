`include "core_v2_defs.vh"

module core_v2_single_issue(
    input             clk,
    input             reset,
    input      [7:0]  hardware_interrupt,
    output            instruction_request_valid,
    input             instruction_request_ready,
    output     [31:0] instruction_request_address,
    input             instruction_response_valid,
    output            instruction_response_ready,
    input      [31:0] instruction_response_data,
    input             instruction_response_error,
    output            data_request_valid,
    input             data_request_ready,
    output            data_request_write,
    output     [31:0] data_request_address,
    output     [3:0]  data_request_strobe,
    output     [31:0] data_request_data,
    input             data_response_valid,
    output            data_response_ready,
    input      [31:0] data_response_data,
    input             data_response_error,
    output            commit_valid,
    output     [31:0] commit_pc,
    output     [31:0] commit_inst,
    output            commit_we,
    output     [4:0]  commit_rd,
    output     [31:0] commit_data,
    output            commit_exception,
    output     [5:0]  commit_ecode
);
    localparam STATE_ACCEPT = 2'd0;
    localparam STATE_EXECUTE = 2'd1;
    localparam STATE_MEMORY = 2'd2;
    localparam STATE_COMMIT = 2'd3;

    reg [1:0] state_q;
    reg [31:0] instruction_pc_q;
    reg [31:0] instruction_q;
    reg instruction_error_q;
    reg [31:0] commit_pc_q;
    reg [31:0] commit_next_pc_q;
    reg [31:0] commit_inst_q;
    reg commit_we_q;
    reg [4:0] commit_rd_q;
    reg [31:0] commit_data_q;
    reg commit_exception_q;
    reg [5:0] commit_ecode_q;
    reg commit_badv_valid_q;
    reg [31:0] commit_badv_q;
    reg commit_csr_write_q;
    reg [13:0] commit_csr_addr_q;
    reg [31:0] commit_csr_write_data_q;
    reg [31:0] commit_csr_write_mask_q;
    reg commit_ertn_q;

    wire frontend_valid;
    wire frontend_ready;
    wire [31:0] frontend_pc;
    wire [31:0] frontend_instruction;
    wire frontend_error;
    wire redirect_valid;
    wire [31:0] redirect_target;
    wire [31:0] rf_data1;
    wire [31:0] rf_data2;
    wire [31:0] unused_rf_data2;
    wire [31:0] unused_rf_data3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] issue_rd;
    wire use_rs1;
    wire use_rs2;
    wire issue_reg_write;
    wire [3:0] issue_uop;
    wire [1:0] issue_mem_width;
    wire issue_mem_signed;
    wire issue_illegal;
    wire issue_stall;
    wire [31:0] issue_result;
    wire [31:0] issue_store_data;
    wire branch_taken;
    wire [31:0] branch_target;
    wire lsu_request_ready;
    wire lsu_completion_valid;
    wire [31:0] lsu_completion_data;
    wire lsu_completion_misaligned;
    wire lsu_completion_bus_error;
    wire memory_operation;
    wire regfile_write;
    wire system_recognized;
    wire [4:0] system_data_source;
    wire [4:0] system_mask_source;
    wire [4:0] system_rd;
    wire system_gpr_write;
    wire [31:0] system_gpr_data;
    wire system_csr_write;
    wire [13:0] system_csr_addr;
    wire [31:0] system_csr_write_data;
    wire [31:0] system_csr_write_mask;
    wire system_exception;
    wire [5:0] system_exception_ecode;
    wire system_ertn;
    wire [31:0] csr_read_data;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] unused_csr_read_data_registered;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] exception_entry;
    wire [31:0] ertn_entry;
    wire interrupt_pending;
    wire unused_current_plv_bit0;
    wire unused_current_plv_bit1;
    wire unused_interrupt_enable;
    wire unused_direct_address;
    wire unused_paging_enable;
    wire csr_exception_valid;
    wire [5:0] csr_exception_ecode;
    wire [8:0] csr_exception_esubcode;
    wire [31:0] csr_exception_pc;
    wire csr_badv_valid;
    wire [31:0] csr_exception_badv;
    wire csr_ertn_valid;
    wire exception_redirect_valid;
    wire [2:0] unused_redirect_kind;
    wire [31:0] exception_redirect_target;
    wire architectural_illegal;
    wire multiplier_request_ready;
    wire multiplier_response_valid;
    wire [31:0] multiplier_response_data;

    frontend_single_v2 u_frontend (
        .clk(clk), .reset(reset),
        .redirect_valid(redirect_valid),
        .redirect_target(redirect_target),
        .output_valid(frontend_valid), .output_ready(frontend_ready),
        .output_pc(frontend_pc),
        .output_instruction(frontend_instruction),
        .output_error(frontend_error),
        .instruction_request_valid(instruction_request_valid),
        .instruction_request_ready(instruction_request_ready),
        .instruction_request_address(instruction_request_address),
        .instruction_response_valid(instruction_response_valid),
        .instruction_response_ready(instruction_response_ready),
        .instruction_response_data(instruction_response_data),
        .instruction_response_error(instruction_response_error)
    );

    regfile_v2 u_regfile (
        .clk(clk),
        .raddr_0(system_recognized ? system_data_source
                                   : (use_rs1 ? rs1 : 5'b0)),
        .raddr_1(system_recognized ? system_mask_source
                                   : (use_rs2 ? rs2 : 5'b0)),
        .raddr_2(5'b0), .raddr_3(5'b0),
        .rdata_0(rf_data1), .rdata_1(rf_data2),
        .rdata_2(unused_rf_data2), .rdata_3(unused_rf_data3),
        .we_0(regfile_write), .waddr_0(commit_rd_q),
        .wdata_0(commit_data_q),
        .we_1(1'b0), .waddr_1(5'b0), .wdata_1(32'b0)
    );

    integer_issue_v2 u_issue (
        .pc(instruction_pc_q), .inst(instruction_q),
        .rf_data1(rf_data1), .rf_data2(rf_data2),
        .e0_valid(1'b0), .e0_we(1'b0), .e0_result_ready(1'b0),
        .e0_rd(5'b0), .e0_data(32'b0),
        .m0_valid(1'b0), .m0_we(1'b0), .m0_result_ready(1'b0),
        .m0_rd(5'b0), .m0_data(32'b0),
        .m1_valid(1'b0), .m1_we(1'b0), .m1_result_ready(1'b0),
        .m1_rd(5'b0), .m1_data(32'b0),
        .c0_valid(commit_valid), .c0_we(commit_we),
        .c0_rd(commit_rd), .c0_data(commit_data),
        .rs1(rs1), .rs2(rs2), .rd(issue_rd),
        .use_rs1(use_rs1), .use_rs2(use_rs2),
        .reg_write(issue_reg_write), .uop(issue_uop),
        .mem_width(issue_mem_width), .mem_signed(issue_mem_signed),
        .illegal(issue_illegal), .stall(issue_stall),
        .result(issue_result), .store_data(issue_store_data),
        .branch_taken(branch_taken), .branch_target(branch_target)
    );

    system_execute_v2 u_system_execute (
        .inst(instruction_q),
        .data_operand(rf_data1), .mask_operand(rf_data2),
        .csr_read_data(csr_read_data),
        .recognized(system_recognized),
        .data_source(system_data_source),
        .mask_source(system_mask_source), .rd(system_rd),
        .gpr_write(system_gpr_write), .gpr_data(system_gpr_data),
        .csr_write(system_csr_write), .csr_addr(system_csr_addr),
        .csr_write_data(system_csr_write_data),
        .csr_write_mask(system_csr_write_mask),
        .exception(system_exception),
        .exception_ecode(system_exception_ecode), .ertn(system_ertn)
    );

    csr_file_v2 u_csr_file (
        .clk(clk), .reset(reset),
        .read_addr(system_csr_addr), .read_data(csr_read_data),
        .read_data_registered(unused_csr_read_data_registered),
        .write_valid(commit_valid && commit_csr_write_q &&
                     !commit_exception_q),
        .write_addr(commit_csr_addr_q),
        .write_data(commit_csr_write_data_q),
        .write_mask(commit_csr_write_mask_q),
        .exception_valid(csr_exception_valid),
        .exception_ecode(csr_exception_ecode),
        .exception_esubcode(csr_exception_esubcode),
        .exception_pc(csr_exception_pc),
        .badv_valid(csr_badv_valid),
        .exception_badv(csr_exception_badv),
        .ertn_valid(csr_ertn_valid),
        .hardware_interrupt(hardware_interrupt), .timer_interrupt(1'b0),
        .ipi_interrupt(1'b0),
        .exception_entry(exception_entry), .ertn_entry(ertn_entry),
        .interrupt_pending(interrupt_pending),
        .current_plv({unused_current_plv_bit1, unused_current_plv_bit0}),
        .interrupt_enable(unused_interrupt_enable),
        .direct_address(unused_direct_address),
        .paging_enable(unused_paging_enable)
    );

    exception_control_v2 u_exception_control (
        .boundary_valid(commit_valid), .boundary_pc(commit_pc_q),
        .boundary_next_pc(commit_next_pc_q),
        .instruction_exception(commit_exception_q),
        .instruction_ecode(commit_ecode_q),
        .instruction_esubcode(9'b0),
        .instruction_badv_valid(commit_badv_valid_q),
        .instruction_badv(commit_badv_q),
        .instruction_ertn(commit_ertn_q),
        .interrupt_pending(interrupt_pending),
        .exception_entry(exception_entry), .ertn_entry(ertn_entry),
        .csr_exception_valid(csr_exception_valid),
        .csr_exception_ecode(csr_exception_ecode),
        .csr_exception_esubcode(csr_exception_esubcode),
        .csr_exception_pc(csr_exception_pc),
        .csr_badv_valid(csr_badv_valid),
        .csr_exception_badv(csr_exception_badv),
        .csr_ertn_valid(csr_ertn_valid),
        .redirect_valid(exception_redirect_valid),
        .redirect_kind(unused_redirect_kind),
        .redirect_target(exception_redirect_target)
    );

    multiplier_v2 u_multiplier (
        .clk(clk), .reset(reset),
        .request_valid(state_q == STATE_EXECUTE &&
                       issue_uop == `V2_UOP_MUL &&
                       !instruction_error_q &&
                       !architectural_illegal),
        .request_ready(multiplier_request_ready),
        .operand1(rf_data1), .operand2(rf_data2),
        .response_valid(multiplier_response_valid),
        .response_ready(state_q == STATE_MEMORY),
        .response_data(multiplier_response_data)
    );

    lsu_request_v2 u_lsu (
        .clk(clk), .reset(reset),
        .request_valid(state_q == STATE_EXECUTE && memory_operation &&
                       !instruction_error_q && !issue_illegal),
        .request_ready(lsu_request_ready),
        .request_write(issue_uop == `V2_UOP_STORE),
        .request_address(issue_result),
        .request_width(issue_mem_width),
        .request_signed(issue_mem_signed),
        .request_write_data(issue_store_data),
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
        .completion_ready(state_q == STATE_MEMORY),
        .completion_data(lsu_completion_data),
        .completion_misaligned(lsu_completion_misaligned),
        .completion_bus_error(lsu_completion_bus_error)
    );

    assign frontend_ready = state_q == STATE_ACCEPT;
    assign memory_operation = issue_uop == `V2_UOP_LOAD ||
                              issue_uop == `V2_UOP_STORE;
    assign architectural_illegal = issue_illegal && !system_recognized;
    assign redirect_valid = (state_q == STATE_EXECUTE && branch_taken &&
                             !instruction_error_q && !architectural_illegal &&
                             !issue_stall) ||
                            exception_redirect_valid;
    assign redirect_target = exception_redirect_valid
        ? exception_redirect_target : branch_target;
    assign commit_valid = state_q == STATE_COMMIT;
    assign commit_pc = commit_pc_q;
    assign commit_inst = commit_inst_q;
    assign commit_we = commit_we_q;
    assign commit_rd = commit_rd_q;
    assign commit_data = commit_data_q;
    assign commit_exception = commit_exception_q;
    assign commit_ecode = commit_ecode_q;
    assign regfile_write = commit_valid && commit_we_q &&
                           !commit_exception_q;

    always @(posedge clk) begin
        if (reset) begin
            state_q <= STATE_ACCEPT;
            instruction_error_q <= 1'b0;
            commit_we_q <= 1'b0;
            commit_exception_q <= 1'b0;
            commit_ecode_q <= 6'b0;
            commit_badv_valid_q <= 1'b0;
            commit_badv_q <= 32'b0;
            commit_csr_write_q <= 1'b0;
            commit_ertn_q <= 1'b0;
        end else begin
            case (state_q)
                STATE_ACCEPT: begin
                    if (frontend_valid) begin
                        instruction_pc_q <= frontend_pc;
                        instruction_q <= frontend_instruction;
                        instruction_error_q <= frontend_error;
                        state_q <= STATE_EXECUTE;
                    end
                end
                STATE_EXECUTE: begin
                    if (!issue_stall) begin
                        commit_pc_q <= instruction_pc_q;
                        commit_next_pc_q <= branch_taken
                            ? branch_target : instruction_pc_q + 32'd4;
                        commit_inst_q <= instruction_q;
                        commit_we_q <= system_recognized
                            ? (system_gpr_write && system_rd != 5'b0)
                            : (issue_reg_write && issue_rd != 5'b0);
                        commit_rd_q <= system_recognized
                            ? system_rd : issue_rd;
                        commit_data_q <= system_recognized
                            ? system_gpr_data : issue_result;
                        commit_exception_q <= instruction_error_q ||
                                              architectural_illegal ||
                                              system_exception;
                        commit_ecode_q <= instruction_error_q
                            ? `V2_ECODE_ADE
                            : (system_exception
                               ? system_exception_ecode
                               : (architectural_illegal
                                  ? `V2_ECODE_INE : 6'b0));
                        commit_badv_valid_q <= instruction_error_q;
                        commit_badv_q <= instruction_pc_q;
                        commit_csr_write_q <= system_recognized &&
                                              system_csr_write;
                        commit_csr_addr_q <= system_csr_addr;
                        commit_csr_write_data_q <= system_csr_write_data;
                        commit_csr_write_mask_q <= system_csr_write_mask;
                        commit_ertn_q <= system_recognized && system_ertn;
                        if (memory_operation && !instruction_error_q &&
                            !architectural_illegal &&
                            !system_recognized) begin
                            if (lsu_request_ready)
                                state_q <= STATE_MEMORY;
                        end else if (issue_uop == `V2_UOP_MUL &&
                                     !instruction_error_q &&
                                     !architectural_illegal) begin
                            if (multiplier_request_ready)
                                state_q <= STATE_MEMORY;
                        end else begin
                            state_q <= STATE_COMMIT;
                        end
                    end
                end
                STATE_MEMORY: begin
                    if (issue_uop == `V2_UOP_MUL &&
                        multiplier_response_valid) begin
                        commit_we_q <= issue_rd != 5'b0;
                        commit_rd_q <= issue_rd;
                        commit_data_q <= multiplier_response_data;
                        commit_exception_q <= 1'b0;
                        commit_ecode_q <= 6'b0;
                        commit_badv_valid_q <= 1'b0;
                        state_q <= STATE_COMMIT;
                    end else if (lsu_completion_valid) begin
                        commit_we_q <= issue_uop == `V2_UOP_LOAD &&
                                       issue_rd != 5'b0 &&
                                       !lsu_completion_misaligned &&
                                       !lsu_completion_bus_error;
                        commit_data_q <= lsu_completion_data;
                        commit_exception_q <= lsu_completion_misaligned ||
                                              lsu_completion_bus_error;
                        commit_ecode_q <= lsu_completion_misaligned
                            ? `V2_ECODE_ALE
                            : (lsu_completion_bus_error
                               ? `V2_ECODE_ADE : 6'b0);
                        commit_badv_valid_q <= lsu_completion_misaligned ||
                                               lsu_completion_bus_error;
                        commit_badv_q <= issue_result;
                        state_q <= STATE_COMMIT;
                    end
                end
                default: begin
                    state_q <= STATE_ACCEPT;
                end
            endcase
        end
    end
endmodule
