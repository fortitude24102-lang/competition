`timescale 1ns/1ps

module tb_video_accel_top;
  logic        clock = 1'b0;
  logic        reset;
  logic [23:0] pixel_in;
  logic        pixel_in_valid;
  logic        enable;
  logic [1:0]  mode;
  logic [7:0]  threshold;
  logic        bypass;
  wire [23:0]  pixel_out;
  wire         pixel_out_valid;
  wire         busy;
  wire         frame_done;

  always #5 clock = ~clock;

  VideoAccelTop dut (
      .clock(clock),
      .reset(reset),
      .pixel_in(pixel_in),
      .pixel_in_valid(pixel_in_valid),
      .enable(enable),
      .mode(mode),
      .threshold(threshold),
      .bypass(bypass),
      .pixel_out(pixel_out),
      .pixel_out_valid(pixel_out_valid),
      .busy(busy),
      .frame_done(frame_done)
  );

  task automatic tick;
    @(posedge clock);
    #1;
  endtask

  task automatic check(input logic condition, input string message);
    if (!condition)
      $fatal(1, "FAIL: %s", message);
  endtask

  task automatic send_and_expect(
      input logic [23:0] sample,
      input logic [1:0] sample_mode,
      input logic [7:0] sample_threshold,
      input logic sample_bypass,
      input logic [23:0] expected
  );
    pixel_in = sample;
    mode = sample_mode;
    threshold = sample_threshold;
    bypass = sample_bypass;
    pixel_in_valid = 1'b1;
    tick();
    check(pixel_out_valid === 1'b1, "valid did not follow accepted pixel");
    check(busy === 1'b1, "busy did not follow accepted pixel");
    check(frame_done === 1'b1, "frame_done did not follow accepted pixel");
    check(pixel_out === expected, "pixel result mismatch");

    pixel_in_valid = 1'b0;
    tick();
    check(pixel_out_valid === 1'b0, "valid lasted longer than one cycle");
    check(busy === 1'b0, "busy lasted longer than one cycle");
    check(frame_done === 1'b0, "frame_done lasted longer than one cycle");
  endtask

  initial begin
    reset = 1'b1;
    pixel_in = 24'h000000;
    pixel_in_valid = 1'b0;
    enable = 1'b0;
    mode = 2'd0;
    threshold = 8'h80;
    bypass = 1'b1;

    repeat (2) tick();
    check(pixel_out === 24'h000000, "reset pixel output is not zero");
    check(pixel_out_valid === 1'b0, "reset valid is not zero");
    check(busy === 1'b0, "reset busy is not zero");
    check(frame_done === 1'b0, "reset frame_done is not zero");

    reset = 1'b0;
    pixel_in = 24'habcdef;
    pixel_in_valid = 1'b1;
    tick();
    check(pixel_out_valid === 1'b0, "disabled accelerator accepted a pixel");
    check(busy === 1'b0, "disabled accelerator asserted busy");
    check(frame_done === 1'b0, "disabled accelerator asserted frame_done");
    pixel_in_valid = 1'b0;

    enable = 1'b1;
    send_and_expect(24'h336699, 2'd0, 8'h80, 1'b1, 24'h336699);
    send_and_expect(24'h336699, 2'd1, 8'h80, 1'b0, 24'h666666);
    send_and_expect(24'h336699, 2'd2, 8'h80, 1'b0, 24'h000000);
    send_and_expect(24'h336699, 2'd2, 8'h40, 1'b0, 24'hffffff);

    $display("PASS: VideoAccelTop standalone regression");
    $finish;
  end
endmodule
