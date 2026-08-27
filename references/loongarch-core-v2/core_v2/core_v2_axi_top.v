module core_v2_axi_top(
    input             clk,
    input             reset,
    input      [7:0]  hardware_interrupt,
    output     [3:0]  arid,
    output     [31:0] araddr,
    output     [7:0]  arlen,
    output     [2:0]  arsize,
    output     [1:0]  arburst,
    output     [1:0]  arlock,
    output     [3:0]  arcache,
    output     [2:0]  arprot,
    output            arvalid,
    input             arready,
    input      [3:0]  rid,
    input      [31:0] rdata,
    input      [1:0]  rresp,
    input             rlast,
    input             rvalid,
    output            rready,
    output     [3:0]  awid,
    output     [31:0] awaddr,
    output     [7:0]  awlen,
    output     [2:0]  awsize,
    output     [1:0]  awburst,
    output     [1:0]  awlock,
    output     [3:0]  awcache,
    output     [2:0]  awprot,
    output            awvalid,
    input             awready,
    output     [3:0]  wid,
    output     [31:0] wdata,
    output     [3:0]  wstrb,
    output            wlast,
    output            wvalid,
    input             wready,
    input      [3:0]  bid,
    input      [1:0]  bresp,
    input             bvalid,
    output            bready,
    output            commit_valid,
    output     [31:0] commit_pc,
    output     [31:0] commit_inst,
    output            commit_we,
    output     [4:0]  commit_rd,
    output     [31:0] commit_data,
    output            commit_exception,
    output     [5:0]  commit_ecode
);
    wire instruction_request_valid;
    wire instruction_request_ready;
    wire [31:0] instruction_request_address;
    wire instruction_response_valid;
    wire instruction_response_ready;
    wire [31:0] instruction_response_data;
    wire instruction_response_error;
    wire data_request_valid;
    wire data_request_ready;
    wire data_request_write;
    wire [31:0] data_request_address;
    wire [3:0] data_request_strobe;
    wire [31:0] data_request_data;
    wire data_response_valid;
    wire data_response_ready;
    wire [31:0] data_response_data;
    wire data_response_error;

    core_v2 u_core (
        .clk(clk), .reset(reset),
        .hardware_interrupt(hardware_interrupt),
        .instruction_request_valid(instruction_request_valid),
        .instruction_request_ready(instruction_request_ready),
        .instruction_request_address(instruction_request_address),
        .instruction_response_valid(instruction_response_valid),
        .instruction_response_ready(instruction_response_ready),
        .instruction_response_data(instruction_response_data),
        .instruction_response_error(instruction_response_error),
        .data_request_valid(data_request_valid),
        .data_request_ready(data_request_ready),
        .data_request_write(data_request_write),
        .data_request_address(data_request_address),
        .data_request_strobe(data_request_strobe),
        .data_request_data(data_request_data),
        .data_response_valid(data_response_valid),
        .data_response_ready(data_response_ready),
        .data_response_data(data_response_data),
        .data_response_error(data_response_error),
        .commit_valid(commit_valid), .commit_pc(commit_pc),
        .commit_inst(commit_inst), .commit_we(commit_we),
        .commit_rd(commit_rd), .commit_data(commit_data),
        .commit_exception(commit_exception), .commit_ecode(commit_ecode)
    );

    core_v2_axi_adapter u_adapter (
        .clk(clk), .reset(reset),
        .instruction_request_valid(instruction_request_valid),
        .instruction_request_ready(instruction_request_ready),
        .instruction_request_address(instruction_request_address),
        .instruction_response_valid(instruction_response_valid),
        .instruction_response_ready(instruction_response_ready),
        .instruction_response_data(instruction_response_data),
        .instruction_response_error(instruction_response_error),
        .data_request_valid(data_request_valid),
        .data_request_ready(data_request_ready),
        .data_request_write(data_request_write),
        .data_request_address(data_request_address),
        .data_request_strobe(data_request_strobe),
        .data_request_data(data_request_data),
        .data_response_valid(data_response_valid),
        .data_response_ready(data_response_ready),
        .data_response_data(data_response_data),
        .data_response_error(data_response_error),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache),
        .arprot(arprot), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache),
        .awprot(awprot), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );
endmodule
