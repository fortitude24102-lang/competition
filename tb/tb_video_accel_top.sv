`timescale 1ns/1ps

module tb_video_accel_top;
  logic        clock = 1'b0;
  logic        reset;
  logic [23:0] pixel_in;
  logic        pixel_in_valid;
  wire         pixel_in_ready;
  logic        pixel_in_start_of_frame;
  logic        pixel_in_end_of_line;
  logic        pixel_in_end_of_frame;
  logic        enable;
  logic [1:0]  mode;
  logic [7:0]  threshold;
  logic        bypass;
  wire [23:0]  pixel_out;
  wire         pixel_out_valid;
  logic        pixel_out_ready;
  wire         pixel_out_start_of_frame;
  wire         pixel_out_end_of_line;
  wire         pixel_out_end_of_frame;
  wire         busy;
  wire         frame_done;

  always #5 clock = ~clock;

  VideoAccelTop dut (
      .clock(clock),
      .reset(reset),
      .pixel_in(pixel_in),
      .pixel_in_valid(pixel_in_valid),
      .pixel_in_ready(pixel_in_ready),
      .pixel_in_start_of_frame(pixel_in_start_of_frame),
      .pixel_in_end_of_line(pixel_in_end_of_line),
      .pixel_in_end_of_frame(pixel_in_end_of_frame),
      .enable(enable),
      .mode(mode),
      .threshold(threshold),
      .bypass(bypass),
      .pixel_out(pixel_out),
      .pixel_out_valid(pixel_out_valid),
      .pixel_out_ready(pixel_out_ready),
      .pixel_out_start_of_frame(pixel_out_start_of_frame),
      .pixel_out_end_of_line(pixel_out_end_of_line),
      .pixel_out_end_of_frame(pixel_out_end_of_frame),
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

  task automatic set_input(
      input logic [23:0] sample,
      input logic sample_sof,
      input logic sample_eol,
      input logic sample_eof
  );
    pixel_in = sample;
    pixel_in_start_of_frame = sample_sof;
    pixel_in_end_of_line = sample_eol;
    pixel_in_end_of_frame = sample_eof;
    pixel_in_valid = 1'b1;
  endtask

  initial begin
    reset = 1'b1;
    pixel_in = 24'h000000;
    pixel_in_valid = 1'b0;
    pixel_in_start_of_frame = 1'b0;
    pixel_in_end_of_line = 1'b0;
    pixel_in_end_of_frame = 1'b0;
    pixel_out_ready = 1'b0;
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
    set_input(24'habcdef, 1'b1, 1'b1, 1'b1);
    tick();
    check(pixel_in_ready === 1'b0, "disabled accelerator accepted input");
    check(pixel_out_valid === 1'b0, "disabled accelerator produced output");

    enable = 1'b1;
    set_input(24'h336699, 1'b1, 1'b0, 1'b0);
    #1;
    check(pixel_in_ready === 1'b1, "empty output register did not accept input");
    tick();
    pixel_in_valid = 1'b0;
    check(pixel_out_valid === 1'b1, "accepted input did not produce output");
    check(pixel_out === 24'h336699, "bypass pixel mismatch");
    check(pixel_out_start_of_frame === 1'b1, "start-of-frame was not preserved");
    check(pixel_out_end_of_line === 1'b0, "end-of-line changed during processing");
    check(pixel_out_end_of_frame === 1'b0, "end-of-frame changed during processing");
    check(pixel_in_ready === 1'b0, "full output register accepted input while stalled");

    repeat (3) begin
      tick();
      check(pixel_out_valid === 1'b1, "stalled output valid was dropped");
      check(pixel_out === 24'h336699, "stalled output data changed");
      check(pixel_out_start_of_frame === 1'b1, "stalled frame flag changed");
      check(frame_done === 1'b0, "non-final beat asserted frame_done");
    end

    pixel_out_ready = 1'b1;
    tick();
    check(pixel_out_valid === 1'b0, "transferred output was not retired");
    check(frame_done === 1'b0, "non-final transfer asserted frame_done");

    bypass = 1'b0;
    mode = 2'd2;
    threshold = 8'h40;
    set_input(24'hc0c0c0, 1'b0, 1'b1, 1'b1);
    tick();
    pixel_in_valid = 1'b0;
    check(pixel_out_valid === 1'b1, "final pixel was not produced");
    check(pixel_out === 24'hffffff, "threshold pixel mismatch");
    check(pixel_out_end_of_line === 1'b1, "final line marker was lost");
    check(pixel_out_end_of_frame === 1'b1, "final frame marker was lost");
    check(frame_done === 1'b0, "frame_done asserted before output transfer");
    tick();
    check(pixel_out_valid === 1'b0, "final output was not retired");
    check(frame_done === 1'b1, "accepted final beat did not assert frame_done");
    tick();
    check(frame_done === 1'b0, "frame_done lasted longer than one cycle");

    bypass = 1'b1;
    set_input(24'h010203, 1'b1, 1'b0, 1'b0);
    tick();
    set_input(24'h040506, 1'b0, 1'b1, 1'b1);
    tick();
    check(pixel_out_valid === 1'b1, "simultaneous transfer inserted a bubble");
    check(pixel_out === 24'h040506, "simultaneous transfer lost the next beat");
    check(pixel_out_end_of_frame === 1'b1, "simultaneous transfer lost the next frame marker");
    pixel_in_valid = 1'b0;
    tick();
    check(frame_done === 1'b1, "back-to-back final beat did not complete");

    $display("PASS: VideoAccelTop standalone regression");
    $finish;
  end
endmodule
