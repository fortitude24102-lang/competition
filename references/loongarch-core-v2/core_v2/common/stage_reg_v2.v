module stage_reg_v2 #(
    parameter PAYLOAD_W = 1
)(
    input                      clk,
    input                      reset,
    input                      flush,
    input                      input_valid,
    input      [PAYLOAD_W-1:0] input_payload,
    output                     input_ready,
    output reg                 output_valid,
    output reg [PAYLOAD_W-1:0] output_payload,
    input                      output_ready
);
    assign input_ready = ~output_valid || output_ready;

    always @(posedge clk) begin
        if (reset || flush) begin
            output_valid <= 1'b0;
        end else if (input_ready) begin
            output_valid <= input_valid;
            if (input_valid)
                output_payload <= input_payload;
        end
    end
endmodule
