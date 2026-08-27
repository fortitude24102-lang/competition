module hazard_unit_v2(
    input  [4:0] rs1,
    input  [4:0] rs2,
    input        use_rs1,
    input        use_rs2,
    input        e0_valid,
    input        e0_we,
    input        e0_ready,
    input  [4:0] e0_rd,
    input        m0_valid,
    input        m0_we,
    input        m0_ready,
    input  [4:0] m0_rd,
    input        m1_valid,
    input        m1_we,
    input        m1_ready,
    input  [4:0] m1_rd,
    output       stall
);
    wire wait_e0 = e0_valid && e0_we && !e0_ready && e0_rd != 5'd0 &&
                   ((use_rs1 && rs1 == e0_rd) ||
                    (use_rs2 && rs2 == e0_rd));
    wire wait_m0 = m0_valid && m0_we && !m0_ready && m0_rd != 5'd0 &&
                   ((use_rs1 && rs1 == m0_rd) ||
                    (use_rs2 && rs2 == m0_rd));
    wire wait_m1 = m1_valid && m1_we && !m1_ready && m1_rd != 5'd0 &&
                   ((use_rs1 && rs1 == m1_rd) ||
                    (use_rs2 && rs2 == m1_rd));

    assign stall = wait_e0 || wait_m0 || wait_m1;
endmodule
