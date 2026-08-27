`include "core_v2_defs.vh"

module redirect_arbiter_v2(
    input         exception_valid,
    input  [31:0] exception_target,
    input         ertn_valid,
    input  [31:0] ertn_target,
    input         interrupt_valid,
    input  [31:0] interrupt_target,
    input         sync_valid,
    input  [31:0] sync_target,
    input         branch_valid,
    input  [31:0] branch_target,
    output reg    redirect_valid,
    output reg [2:0]  redirect_kind,
    output reg [31:0] redirect_target
);
    always @(*) begin
        redirect_valid = 1'b0;
        redirect_kind = `V2_REDIRECT_NONE;
        redirect_target = 32'b0;

        if (exception_valid) begin
            redirect_valid = 1'b1;
            redirect_kind = `V2_REDIRECT_EXCEPTION;
            redirect_target = exception_target;
        end else if (ertn_valid) begin
            redirect_valid = 1'b1;
            redirect_kind = `V2_REDIRECT_ERTN;
            redirect_target = ertn_target;
        end else if (interrupt_valid) begin
            redirect_valid = 1'b1;
            redirect_kind = `V2_REDIRECT_INTERRUPT;
            redirect_target = interrupt_target;
        end else if (sync_valid) begin
            redirect_valid = 1'b1;
            redirect_kind = `V2_REDIRECT_IBAR;
            redirect_target = sync_target;
        end else if (branch_valid) begin
            redirect_valid = 1'b1;
            redirect_kind = `V2_REDIRECT_BRANCH;
            redirect_target = branch_target;
        end
    end
endmodule
