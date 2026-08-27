`include "core_v2_defs.vh"

module csr_file_v2(
    input             clk,
    input             reset,
    input      [13:0] read_addr,
    output reg [31:0] read_data,
    output reg [31:0] read_data_registered,
    input             write_valid,
    input      [13:0] write_addr,
    input      [31:0] write_data,
    input      [31:0] write_mask,
    input             exception_valid,
    input      [5:0]  exception_ecode,
    input      [8:0]  exception_esubcode,
    input      [31:0] exception_pc,
    input             badv_valid,
    input      [31:0] exception_badv,
    input             ertn_valid,
    input      [7:0]  hardware_interrupt,
    input             timer_interrupt,
    input             ipi_interrupt,
    output     [31:0] exception_entry,
    output     [31:0] ertn_entry,
    output            interrupt_pending,
    output     [1:0]  current_plv,
    output            interrupt_enable,
    output            direct_address,
    output            paging_enable
);
    reg [8:0] crmd_q;
    reg [2:0] prmd_q;
    reg [12:0] ecfg_q;
    reg [1:0] estat_sw_q;
    reg [5:0] estat_ecode_q;
    reg [8:0] estat_esubcode_q;
    reg [31:0] era_q;
    reg [31:0] badv_q;
    reg [25:0] eentry_va_q;
    reg [31:0] save0_q;
    reg [31:0] save1_q;
    reg [31:0] save2_q;
    reg [31:0] save3_q;
    reg [31:0] tid_q;
    reg [2:0] llbctl_q;
    reg [31:0] dmw0_q;
    reg [31:0] dmw1_q;
    reg [4:0] read_select_q;

    localparam [4:0] CSR_SELECT_NONE   = 5'd0;
    localparam [4:0] CSR_SELECT_CRMD   = 5'd1;
    localparam [4:0] CSR_SELECT_PRMD   = 5'd2;
    localparam [4:0] CSR_SELECT_ECFG   = 5'd3;
    localparam [4:0] CSR_SELECT_ESTAT  = 5'd4;
    localparam [4:0] CSR_SELECT_ERA    = 5'd5;
    localparam [4:0] CSR_SELECT_BADV   = 5'd6;
    localparam [4:0] CSR_SELECT_EENTRY = 5'd7;
    localparam [4:0] CSR_SELECT_SAVE0  = 5'd8;
    localparam [4:0] CSR_SELECT_SAVE1  = 5'd9;
    localparam [4:0] CSR_SELECT_SAVE2  = 5'd10;
    localparam [4:0] CSR_SELECT_SAVE3  = 5'd11;
    localparam [4:0] CSR_SELECT_TID    = 5'd12;
    localparam [4:0] CSR_SELECT_TCFG   = 5'd13;
    localparam [4:0] CSR_SELECT_TVAL   = 5'd14;
    localparam [4:0] CSR_SELECT_LLBCTL = 5'd15;
    localparam [4:0] CSR_SELECT_DMW0   = 5'd16;
    localparam [4:0] CSR_SELECT_DMW1   = 5'd17;

    wire [12:0] interrupt_status;
    wire [31:0] estat_value;
    wire [31:0] masked_write_data;
    reg [31:0] current_write_value;
    wire [31:0] timer_value;
    wire [31:0] timer_config_value;
    wire timer_interrupt_internal;
    wire timer_config_write;
    wire timer_clear;

    assign timer_config_write = write_valid && !exception_valid &&
                                !ertn_valid &&
                                write_addr == `V2_CSR_TCFG;
    assign timer_clear = write_valid && !exception_valid && !ertn_valid &&
                         write_addr == `V2_CSR_TICLR &&
                         masked_write_data[0];

    timer_v2 u_timer (
        .clk(clk), .reset(reset),
        .config_write(timer_config_write),
        .config_value(masked_write_data),
        .clear_interrupt(timer_clear),
        .current_value(timer_value),
        .interrupt_pending(timer_interrupt_internal),
        .config_read_value(timer_config_value)
    );

    assign interrupt_status = {
        ipi_interrupt,
        timer_interrupt | timer_interrupt_internal,
        1'b0,
        hardware_interrupt,
        estat_sw_q
    };
    assign estat_value = {
        1'b0,
        estat_esubcode_q,
        estat_ecode_q,
        3'b0,
        interrupt_status
    };
    assign exception_entry = {eentry_va_q, 6'b0};
    assign ertn_entry = era_q;
    assign current_plv = crmd_q[1:0];
    assign interrupt_enable = crmd_q[2];
    assign direct_address = crmd_q[3];
    assign paging_enable = crmd_q[4];
    assign interrupt_pending = crmd_q[2] &&
                               (|(interrupt_status & ecfg_q));

    always @(*) begin
        case (write_addr)
            `V2_CSR_CRMD: current_write_value = {23'b0, crmd_q};
            `V2_CSR_PRMD: current_write_value = {29'b0, prmd_q};
            `V2_CSR_ECFG: current_write_value = {19'b0, ecfg_q};
            `V2_CSR_ESTAT: current_write_value = estat_value;
            `V2_CSR_ERA: current_write_value = era_q;
            `V2_CSR_BADV: current_write_value = badv_q;
            `V2_CSR_EENTRY: current_write_value = exception_entry;
            `V2_CSR_SAVE0: current_write_value = save0_q;
            `V2_CSR_SAVE1: current_write_value = save1_q;
            `V2_CSR_SAVE2: current_write_value = save2_q;
            `V2_CSR_SAVE3: current_write_value = save3_q;
            `V2_CSR_TID: current_write_value = tid_q;
            `V2_CSR_TCFG: current_write_value = timer_config_value;
            `V2_CSR_TVAL: current_write_value = timer_value;
            `V2_CSR_LLBCTL: current_write_value = {29'b0, llbctl_q};
            `V2_CSR_DMW0: current_write_value = dmw0_q;
            `V2_CSR_DMW1: current_write_value = dmw1_q;
            default: current_write_value = 32'b0;
        endcase
    end
    assign masked_write_data = (current_write_value & ~write_mask) |
                               (write_data & write_mask);

    always @(*) begin
        case (read_addr)
            `V2_CSR_CRMD: read_data = {23'b0, crmd_q};
            `V2_CSR_PRMD: read_data = {29'b0, prmd_q};
            `V2_CSR_ECFG: read_data = {19'b0, ecfg_q};
            `V2_CSR_ESTAT: read_data = estat_value;
            `V2_CSR_ERA: read_data = era_q;
            `V2_CSR_BADV: read_data = badv_q;
            `V2_CSR_EENTRY: read_data = exception_entry;
            `V2_CSR_CPUID: read_data = 32'b0;
            `V2_CSR_SAVE0: read_data = save0_q;
            `V2_CSR_SAVE1: read_data = save1_q;
            `V2_CSR_SAVE2: read_data = save2_q;
            `V2_CSR_SAVE3: read_data = save3_q;
            `V2_CSR_TID: read_data = tid_q;
            `V2_CSR_TCFG: read_data = timer_config_value;
            `V2_CSR_TVAL: read_data = timer_value;
            `V2_CSR_TICLR: read_data = 32'b0;
            `V2_CSR_LLBCTL: read_data = {29'b0, llbctl_q};
            `V2_CSR_DMW0: read_data = dmw0_q;
            `V2_CSR_DMW1: read_data = dmw1_q;
            default: read_data = 32'b0;
        endcase
    end

    always @(*) begin
        case (read_select_q)
            CSR_SELECT_CRMD: read_data_registered = {23'b0, crmd_q};
            CSR_SELECT_PRMD: read_data_registered = {29'b0, prmd_q};
            CSR_SELECT_ECFG: read_data_registered = {19'b0, ecfg_q};
            CSR_SELECT_ESTAT: read_data_registered = estat_value;
            CSR_SELECT_ERA: read_data_registered = era_q;
            CSR_SELECT_BADV: read_data_registered = badv_q;
            CSR_SELECT_EENTRY: read_data_registered = exception_entry;
            CSR_SELECT_SAVE0: read_data_registered = save0_q;
            CSR_SELECT_SAVE1: read_data_registered = save1_q;
            CSR_SELECT_SAVE2: read_data_registered = save2_q;
            CSR_SELECT_SAVE3: read_data_registered = save3_q;
            CSR_SELECT_TID: read_data_registered = tid_q;
            CSR_SELECT_TCFG: read_data_registered = timer_config_value;
            CSR_SELECT_TVAL: read_data_registered = timer_value;
            CSR_SELECT_LLBCTL: read_data_registered = {29'b0, llbctl_q};
            CSR_SELECT_DMW0: read_data_registered = dmw0_q;
            CSR_SELECT_DMW1: read_data_registered = dmw1_q;
            default: read_data_registered = 32'b0;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            read_select_q <= CSR_SELECT_NONE;
            crmd_q <= 9'h008;
            prmd_q <= 3'b0;
            ecfg_q <= 13'b0;
            estat_sw_q <= 2'b0;
            estat_ecode_q <= 6'b0;
            estat_esubcode_q <= 9'b0;
            era_q <= 32'b0;
            badv_q <= 32'b0;
            eentry_va_q <= 26'h0700000;
            save0_q <= 32'b0;
            save1_q <= 32'b0;
            save2_q <= 32'b0;
            save3_q <= 32'b0;
            tid_q <= 32'b0;
            llbctl_q <= 3'b0;
            dmw0_q <= 32'b0;
            dmw1_q <= 32'b0;
        end else begin
            case (read_addr)
                `V2_CSR_CRMD: read_select_q <= CSR_SELECT_CRMD;
                `V2_CSR_PRMD: read_select_q <= CSR_SELECT_PRMD;
                `V2_CSR_ECFG: read_select_q <= CSR_SELECT_ECFG;
                `V2_CSR_ESTAT: read_select_q <= CSR_SELECT_ESTAT;
                `V2_CSR_ERA: read_select_q <= CSR_SELECT_ERA;
                `V2_CSR_BADV: read_select_q <= CSR_SELECT_BADV;
                `V2_CSR_EENTRY: read_select_q <= CSR_SELECT_EENTRY;
                `V2_CSR_SAVE0: read_select_q <= CSR_SELECT_SAVE0;
                `V2_CSR_SAVE1: read_select_q <= CSR_SELECT_SAVE1;
                `V2_CSR_SAVE2: read_select_q <= CSR_SELECT_SAVE2;
                `V2_CSR_SAVE3: read_select_q <= CSR_SELECT_SAVE3;
                `V2_CSR_TID: read_select_q <= CSR_SELECT_TID;
                `V2_CSR_TCFG: read_select_q <= CSR_SELECT_TCFG;
                `V2_CSR_TVAL: read_select_q <= CSR_SELECT_TVAL;
                `V2_CSR_LLBCTL: read_select_q <= CSR_SELECT_LLBCTL;
                `V2_CSR_DMW0: read_select_q <= CSR_SELECT_DMW0;
                `V2_CSR_DMW1: read_select_q <= CSR_SELECT_DMW1;
                default: read_select_q <= CSR_SELECT_NONE;
            endcase

            if (exception_valid) begin
                prmd_q <= crmd_q[2:0];
                crmd_q[2:0] <= 3'b000;
                estat_ecode_q <= exception_ecode;
                estat_esubcode_q <= exception_esubcode;
                era_q <= exception_pc;
                if (badv_valid)
                    badv_q <= exception_badv;
            end else if (ertn_valid) begin
                crmd_q[2:0] <= prmd_q;
                if (llbctl_q[2])
                    llbctl_q[1] <= 1'b1;
            end else if (write_valid) begin
                case (write_addr)
                    `V2_CSR_CRMD: crmd_q <= masked_write_data[8:0];
                    `V2_CSR_PRMD: prmd_q <= masked_write_data[2:0];
                    `V2_CSR_ECFG: ecfg_q <=
                        masked_write_data[12:0] & 13'h1bff;
                    `V2_CSR_ESTAT: estat_sw_q <= masked_write_data[1:0];
                    `V2_CSR_ERA: era_q <= masked_write_data;
                    `V2_CSR_BADV: badv_q <= masked_write_data;
                    `V2_CSR_EENTRY: eentry_va_q <= masked_write_data[31:6];
                    `V2_CSR_SAVE0: save0_q <= masked_write_data;
                    `V2_CSR_SAVE1: save1_q <= masked_write_data;
                    `V2_CSR_SAVE2: save2_q <= masked_write_data;
                    `V2_CSR_SAVE3: save3_q <= masked_write_data;
                    `V2_CSR_TID: tid_q <= masked_write_data;
                    `V2_CSR_LLBCTL: llbctl_q <= masked_write_data[2:0];
                    `V2_CSR_DMW0: dmw0_q <= masked_write_data;
                    `V2_CSR_DMW1: dmw1_q <= masked_write_data;
                    default: begin end
                endcase
            end
        end
    end
endmodule
