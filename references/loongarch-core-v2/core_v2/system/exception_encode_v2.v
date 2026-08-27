`include "core_v2_defs.vh"

module exception_encode_v2(
    input             fetch_address_error,
    input      [31:0] fetch_pc,
    input             system_recognized,
    input             system_exception,
    input      [5:0]  system_ecode,
    input             integer_illegal,
    input             memory_misaligned,
    input      [31:0] memory_address,
    output reg        exception_valid,
    output reg [5:0]  exception_ecode,
    output     [8:0]  exception_esubcode,
    output reg        badv_valid,
    output reg [31:0] exception_badv
);
    assign exception_esubcode = 9'b0;

    always @(*) begin
        exception_valid = 1'b0;
        exception_ecode = 6'b0;
        badv_valid = 1'b0;
        exception_badv = 32'b0;

        if (fetch_address_error) begin
            exception_valid = 1'b1;
            exception_ecode = `V2_ECODE_ADE;
            badv_valid = 1'b1;
            exception_badv = fetch_pc;
        end else if (memory_misaligned) begin
            exception_valid = 1'b1;
            exception_ecode = `V2_ECODE_ALE;
            badv_valid = 1'b1;
            exception_badv = memory_address;
        end else if (system_exception) begin
            exception_valid = 1'b1;
            exception_ecode = system_ecode;
        end else if (integer_illegal && !system_recognized) begin
            exception_valid = 1'b1;
            exception_ecode = `V2_ECODE_INE;
        end
    end
endmodule
