module core_v2(
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
    wire frontend_valid;
    wire frontend_ready;
    wire [31:0] frontend_pc;
    wire [31:0] frontend_inst;
    wire frontend_error;
    wire redirect_valid;
    wire [31:0] redirect_target;

    frontend_single_v2 u_frontend (
        .clk(clk), .reset(reset),
        .redirect_valid(redirect_valid),
        .redirect_target(redirect_target),
        .output_valid(frontend_valid), .output_ready(frontend_ready),
        .output_pc(frontend_pc),
        .output_instruction(frontend_inst),
        .output_error(frontend_error),
        .instruction_request_valid(instruction_request_valid),
        .instruction_request_ready(instruction_request_ready),
        .instruction_request_address(instruction_request_address),
        .instruction_response_valid(instruction_response_valid),
        .instruction_response_ready(instruction_response_ready),
        .instruction_response_data(instruction_response_data),
        .instruction_response_error(instruction_response_error)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    integer_pipeline_v2 u_pipeline (
        .clk(clk), .reset(reset),
        .input_valid(frontend_valid), .input_ready(frontend_ready),
        .input_pc(frontend_pc), .input_inst(frontend_inst),
        .input_error(frontend_error),
        .hardware_interrupt(hardware_interrupt),
        .commit_valid(commit_valid), .commit_ready(1'b1),
        .commit_pc(commit_pc), .commit_inst(commit_inst),
        .commit_we(commit_we), .commit_rd(commit_rd),
        .commit_data(commit_data),
        .commit_exception(commit_exception), .commit_ecode(commit_ecode),
        .commit_badv_valid(), .commit_badv(),
        .redirect_valid(redirect_valid),
        .redirect_target(redirect_target),
        .data_request_valid(data_request_valid),
        .data_request_ready(data_request_ready),
        .data_request_write(data_request_write),
        .data_request_address(data_request_address),
        .data_request_strobe(data_request_strobe),
        .data_request_data(data_request_data),
        .data_response_valid(data_response_valid),
        .data_response_ready(data_response_ready),
        .data_response_data(data_response_data),
        .data_response_error(data_response_error)
    );
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
