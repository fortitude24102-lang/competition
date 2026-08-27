module pair_stage_reg #(
    parameter PAYLOAD_W = 1
)(
    input                      clk,
    input                      reset,
    input                      flush,
    input                      input_valid_0,
    input                      input_valid_1,
    input      [PAYLOAD_W-1:0] input_payload_0,
    input      [PAYLOAD_W-1:0] input_payload_1,
    output                     input_ready,
    output reg                 output_valid_0,
    output reg                 output_valid_1,
    output reg [PAYLOAD_W-1:0] output_payload_0,
    output reg [PAYLOAD_W-1:0] output_payload_1,
    input                      output_ready
);
    assign input_ready = ~output_valid_0 || output_ready;

    always @(posedge clk) begin
        if (reset || flush) begin
            output_valid_0 <= 1'b0;
            output_valid_1 <= 1'b0;
        end else if (input_ready) begin
            output_valid_0 <= input_valid_0;
            output_valid_1 <= input_valid_0 && input_valid_1;
            if (input_valid_0)
                output_payload_0 <= input_payload_0;
            if (input_valid_0 && input_valid_1)
                output_payload_1 <= input_payload_1;
        end
    end
endmodule
