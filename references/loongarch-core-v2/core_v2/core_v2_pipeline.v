module core_v2_pipeline(
    input         clk,
    input         reset,
    input         flush,
    input         input_valid,
    input  [63:0] input_payload,
    output        input_ready,
    output        output_valid,
    output [63:0] output_payload,
    input         output_ready,
    output [8:0]  stage_valid
);
    wire ready_f1;
    wire ready_f2;
    wire ready_d0;
    wire ready_d1;
    wire ready_e0;
    wire ready_m0;
    wire ready_m1;
    wire ready_c0;
    wire [63:0] payload_f0;
    wire [63:0] payload_f1;
    wire [63:0] payload_f2;
    wire [63:0] payload_d0;
    wire [63:0] payload_d1;
    wire [63:0] payload_e0;
    wire [63:0] payload_m0;
    wire [63:0] payload_m1;
    wire [63:0] payload_c0;

    stage_reg_v2 #(.PAYLOAD_W(64)) u_f0 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(input_valid), .input_payload(input_payload),
        .input_ready(input_ready),
        .output_valid(stage_valid[0]), .output_payload(payload_f0),
        .output_ready(ready_f1)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_f1 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[0]), .input_payload(payload_f0),
        .input_ready(ready_f1),
        .output_valid(stage_valid[1]), .output_payload(payload_f1),
        .output_ready(ready_f2)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_f2 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[1]), .input_payload(payload_f1),
        .input_ready(ready_f2),
        .output_valid(stage_valid[2]), .output_payload(payload_f2),
        .output_ready(ready_d0)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_d0 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[2]), .input_payload(payload_f2),
        .input_ready(ready_d0),
        .output_valid(stage_valid[3]), .output_payload(payload_d0),
        .output_ready(ready_d1)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_d1 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[3]), .input_payload(payload_d0),
        .input_ready(ready_d1),
        .output_valid(stage_valid[4]), .output_payload(payload_d1),
        .output_ready(ready_e0)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_e0 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[4]), .input_payload(payload_d1),
        .input_ready(ready_e0),
        .output_valid(stage_valid[5]), .output_payload(payload_e0),
        .output_ready(ready_m0)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_m0 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[5]), .input_payload(payload_e0),
        .input_ready(ready_m0),
        .output_valid(stage_valid[6]), .output_payload(payload_m0),
        .output_ready(ready_m1)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_m1 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[6]), .input_payload(payload_m0),
        .input_ready(ready_m1),
        .output_valid(stage_valid[7]), .output_payload(payload_m1),
        .output_ready(ready_c0)
    );
    stage_reg_v2 #(.PAYLOAD_W(64)) u_c0 (
        .clk(clk), .reset(reset), .flush(flush),
        .input_valid(stage_valid[7]), .input_payload(payload_m1),
        .input_ready(ready_c0),
        .output_valid(stage_valid[8]), .output_payload(payload_c0),
        .output_ready(output_ready)
    );

    assign output_valid = stage_valid[8];
    assign output_payload = payload_c0;
endmodule
