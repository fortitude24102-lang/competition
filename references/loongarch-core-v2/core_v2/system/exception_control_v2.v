`include "core_v2_defs.vh"

module exception_control_v2(
    input             boundary_valid,
    input      [31:0] boundary_pc,
    input      [31:0] boundary_next_pc,
    input             instruction_exception,
    input      [5:0]  instruction_ecode,
    input      [8:0]  instruction_esubcode,
    input             instruction_badv_valid,
    input      [31:0] instruction_badv,
    input             instruction_ertn,
    input             interrupt_pending,
    input      [31:0] exception_entry,
    input      [31:0] ertn_entry,
    output            csr_exception_valid,
    output     [5:0]  csr_exception_ecode,
    output     [8:0]  csr_exception_esubcode,
    output     [31:0] csr_exception_pc,
    output            csr_badv_valid,
    output     [31:0] csr_exception_badv,
    output            csr_ertn_valid,
    output            redirect_valid,
    output     [2:0]  redirect_kind,
    output     [31:0] redirect_target
);
    wire take_instruction_exception;
    wire take_ertn;
    wire take_interrupt;

    assign take_instruction_exception = boundary_valid &&
                                        instruction_exception;
    assign take_ertn = boundary_valid && !instruction_exception &&
                       instruction_ertn;
    assign take_interrupt = boundary_valid && !instruction_exception &&
                            !instruction_ertn && interrupt_pending;

    assign csr_exception_valid = take_instruction_exception || take_interrupt;
    assign csr_exception_ecode = take_instruction_exception
        ? instruction_ecode : `V2_ECODE_INT;
    assign csr_exception_esubcode = take_instruction_exception
        ? instruction_esubcode : 9'b0;
    assign csr_exception_pc = take_interrupt
        ? boundary_next_pc : boundary_pc;
    assign csr_badv_valid = take_instruction_exception &&
                            instruction_badv_valid;
    assign csr_exception_badv = instruction_badv;
    assign csr_ertn_valid = take_ertn;

    assign redirect_valid = take_instruction_exception || take_ertn ||
                            take_interrupt;
    assign redirect_kind = take_instruction_exception
        ? `V2_REDIRECT_EXCEPTION
        : take_ertn
            ? `V2_REDIRECT_ERTN
            : take_interrupt
                ? `V2_REDIRECT_INTERRUPT
                : `V2_REDIRECT_NONE;
    assign redirect_target = take_ertn
        ? ertn_entry
        : (take_instruction_exception || take_interrupt)
            ? exception_entry
            : 32'b0;
endmodule
