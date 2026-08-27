module regfile_v2 #(
    parameter WRITE_THROUGH = 1
)(
    input         clk,
    input  [4:0]  raddr_0,
    input  [4:0]  raddr_1,
    input  [4:0]  raddr_2,
    input  [4:0]  raddr_3,
    output [31:0] rdata_0,
    output [31:0] rdata_1,
    output [31:0] rdata_2,
    output [31:0] rdata_3,
    input         we_0,
    input  [4:0]  waddr_0,
    input  [31:0] wdata_0,
    input         we_1,
    input  [4:0]  waddr_1,
    input  [31:0] wdata_1
);
    reg [31:0] registers [31:0];

    assign rdata_0 = raddr_0 == 5'd0 ? 32'b0
        : WRITE_THROUGH && we_1 && waddr_1 == raddr_0 ? wdata_1
        : WRITE_THROUGH && we_0 && waddr_0 == raddr_0 ? wdata_0
        : registers[raddr_0];
    assign rdata_1 = raddr_1 == 5'd0 ? 32'b0
        : WRITE_THROUGH && we_1 && waddr_1 == raddr_1 ? wdata_1
        : WRITE_THROUGH && we_0 && waddr_0 == raddr_1 ? wdata_0
        : registers[raddr_1];
    assign rdata_2 = raddr_2 == 5'd0 ? 32'b0
        : WRITE_THROUGH && we_1 && waddr_1 == raddr_2 ? wdata_1
        : WRITE_THROUGH && we_0 && waddr_0 == raddr_2 ? wdata_0
        : registers[raddr_2];
    assign rdata_3 = raddr_3 == 5'd0 ? 32'b0
        : WRITE_THROUGH && we_1 && waddr_1 == raddr_3 ? wdata_1
        : WRITE_THROUGH && we_0 && waddr_0 == raddr_3 ? wdata_0
        : registers[raddr_3];

    always @(posedge clk) begin
        if (we_0 && waddr_0 != 5'd0)
            registers[waddr_0] <= wdata_0;
        if (we_1 && waddr_1 != 5'd0)
            registers[waddr_1] <= wdata_1;
    end
endmodule
