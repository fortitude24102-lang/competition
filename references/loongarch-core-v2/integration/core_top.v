// ============================================================================
// core_top — CPU-5 封装（nscscc-solo-la-soc 官方契约）
// ============================================================================
module core_top #(
    parameter TLBNUM = 32
)(
    input           aclk,
    input           aresetn,
    input  [7:0]    intrpt,

    output [3:0]    arid,
    output [31:0]   araddr,
    output [7:0]    arlen,
    output [2:0]    arsize,
    output [1:0]    arburst,
    output [1:0]    arlock,
    output [3:0]    arcache,
    output [2:0]    arprot,
    output          arvalid,
    input           arready,
    input  [3:0]    rid,
    input  [31:0]   rdata,
    input  [1:0]    rresp,
    input           rlast,
    input           rvalid,
    output          rready,

    output [3:0]    awid,
    output [31:0]   awaddr,
    output [7:0]    awlen,
    output [2:0]    awsize,
    output [1:0]    awburst,
    output [1:0]    awlock,
    output [3:0]    awcache,
    output [2:0]    awprot,
    output          awvalid,
    input           awready,
    output [3:0]    wid,
    output [31:0]   wdata,
    output [3:0]    wstrb,
    output          wlast,
    output          wvalid,
    input           wready,
    input  [3:0]    bid,
    input  [1:0]    bresp,
    input           bvalid,
    output          bready,

    input           break_point,
    input           infor_flag,
    input  [4:0]    reg_num,
    output          ws_valid,
    output [31:0]   rf_rdata,

    output [31:0]   debug0_wb_pc,
    output [3:0]    debug0_wb_rf_wen,
    output [4:0]    debug0_wb_rf_wnum,
    output [31:0]   debug0_wb_rf_wdata,
    output [31:0]   debug0_wb_inst
);

    // The synchronous reset reaches several thousand CPU registers.  Request
    // local inverter replication so reset release is not a device-wide routed
    // data path at the target clock rate.
    (* max_fanout = 64 *) wire cpu_reset = ~aresetn;

    assign ws_valid = 1'b0;
    assign rf_rdata = 32'b0;

`ifdef CPU5_USE_CORE_V2
    wire        v2_commit_valid;
    wire [31:0] v2_commit_pc;
    wire [31:0] v2_commit_inst;
    wire        v2_commit_we;
    wire [4:0]  v2_commit_rd;
    wire [31:0] v2_commit_data;

    assign debug0_wb_pc = v2_commit_pc;
    assign debug0_wb_inst = v2_commit_inst;
    assign debug0_wb_rf_wen = {4{v2_commit_valid && v2_commit_we}};
    assign debug0_wb_rf_wnum = v2_commit_rd;
    assign debug0_wb_rf_wdata = v2_commit_data;

    /* verilator lint_off PINCONNECTEMPTY */
    core_v2_axi_top u_cpu_v2 (
        .clk(aclk), .reset(cpu_reset), .hardware_interrupt(intrpt),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache),
        .arprot(arprot), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache),
        .awprot(awprot), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready), .bid(bid), .bresp(bresp),
        .bvalid(bvalid), .bready(bready),
        .commit_valid(v2_commit_valid), .commit_pc(v2_commit_pc),
        .commit_inst(v2_commit_inst), .commit_we(v2_commit_we),
        .commit_rd(v2_commit_rd), .commit_data(v2_commit_data),
        .commit_exception(), .commit_ecode()
    );
    /* verilator lint_on PINCONNECTEMPTY */

`else
    wire [7:0] cpu_arlen, cpu_awlen;
    wire       cpu_wlast;

    assign arid    = 4'h0;
    assign arlen   = cpu_arlen;
    assign arsize  = (araddr[31:20] == 12'h1F0) ? 3'b000 : 3'b010;
    assign arburst = 2'b01;
    assign arlock  = 2'b00;
    assign arcache = 4'h0;
    assign awid    = 4'h0;
    assign awlen   = cpu_awlen;
    assign awsize  = 3'b010;
    assign awburst = 2'b01;
    assign awlock  = 2'b00;
    assign awcache = 4'h0;
    assign wid     = 4'h0;
    assign wlast   = cpu_wlast;

    wire        dbg_wb_we;
    wire [4:0]  dbg_wb_rd;
    wire [31:0] dbg_wb_data;
    wire [3:0]  dbg_dc_state;
    assign debug0_wb_pc       = 32'b0;
    assign debug0_wb_inst     = 32'b0;
    assign debug0_wb_rf_wen   = {4{dbg_wb_we}};
    assign debug0_wb_rf_wnum  = dbg_wb_rd;
    assign debug0_wb_rf_wdata = dbg_wb_data;

    cpu_core u_cpu(
        .clk(aclk), .reset(cpu_reset), .hw_int(intrpt),
        .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_araddr(araddr),   .axi_arprot(arprot),
        .axi_arlen(cpu_arlen),
        .axi_rvalid(rvalid),   .axi_rready(rready),
        .axi_rdata(rdata),     .axi_rresp(rresp),
        .axi_rlast(rlast),
        .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_awaddr(awaddr),   .axi_awprot(awprot),
        .axi_awlen(cpu_awlen),
        .axi_wvalid(wvalid),   .axi_wready(wready),
        .axi_wdata(wdata),     .axi_wstrb(wstrb),
        .axi_wlast(cpu_wlast),
        .axi_bvalid(bvalid),   .axi_bready(bready),
        .axi_bresp(bresp),
        .debug_pc(),
        .debug_wb_we(dbg_wb_we), .debug_wb_rd(dbg_wb_rd), .debug_wb_data(dbg_wb_data),
        .debug_dc_state(dbg_dc_state)
    );
`endif

    // ------------------------------------------------------------------
    // 仿真探针（有界心跳，不刷屏）
    // ------------------------------------------------------------------

endmodule
