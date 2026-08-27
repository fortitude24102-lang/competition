module cpucfg_table_v2(
    input      [31:0] index,
    output reg [31:0] value
);
    always @(*) begin
        case (index)
            32'h00000001: value = 32'h0001f1f4;
            32'h00000002: value = 32'h00000000;
            // Cache capability fields stay clear until the v2 cache and CACOP
            // path are implemented together.  Software uses these bits to
            // decide whether cache maintenance instructions are legal.
            32'h00000010: value = 32'h00000000;
            32'h00000011: value = 32'h00000000;
            32'h00000012: value = 32'h00000000;
            32'h00000013: value = 32'h00000000;
            default: value = 32'h00000000;
        endcase
    end
endmodule
