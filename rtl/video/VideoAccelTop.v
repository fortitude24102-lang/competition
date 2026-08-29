module VideoAccelTop (
    input  wire        clock,
    input  wire        reset,
    input  wire [23:0] pixel_in,
    input  wire        pixel_in_valid,
    output wire        pixel_in_ready,
    input  wire        pixel_in_start_of_frame,
    input  wire        pixel_in_end_of_line,
    input  wire        pixel_in_end_of_frame,
    input  wire        enable,
    input  wire [1:0]  mode,
    input  wire [7:0]  threshold,
    input  wire        bypass,
    output reg  [23:0] pixel_out,
    output reg         pixel_out_valid,
    input  wire        pixel_out_ready,
    output reg         pixel_out_start_of_frame,
    output reg         pixel_out_end_of_line,
    output reg         pixel_out_end_of_frame,
    output wire        busy,
    output reg         frame_done
);

  assign pixel_in_ready = enable && (!pixel_out_valid || pixel_out_ready);
  assign busy = pixel_out_valid;

  wire [9:0] gray_sum = {2'b0, pixel_in[23:16]} +
                        {2'b0, pixel_in[15:8]} +
                        {2'b0, pixel_in[7:0]};
  wire [9:0] gray_quotient = gray_sum / 10'd3;
  wire [7:0] gray = gray_quotient[7:0];
  wire [23:0] gray_pixel = {gray, gray, gray};
  wire [23:0] threshold_pixel = gray >= threshold ? 24'hffffff : 24'h000000;

  reg [23:0] selected_pixel;
  always @* begin
    selected_pixel = pixel_in;
    if (!bypass) begin
      case (mode)
        2'd1: selected_pixel = gray_pixel;
        2'd2: selected_pixel = threshold_pixel;
        default: selected_pixel = pixel_in;
      endcase
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      pixel_out       <= 24'h000000;
      pixel_out_valid <= 1'b0;
      pixel_out_start_of_frame <= 1'b0;
      pixel_out_end_of_line    <= 1'b0;
      pixel_out_end_of_frame   <= 1'b0;
      frame_done      <= 1'b0;
    end else begin
      frame_done <= pixel_out_valid && pixel_out_ready && pixel_out_end_of_frame;
      if (pixel_out_ready)
        pixel_out_valid <= 1'b0;
      if (pixel_in_valid && pixel_in_ready) begin
        pixel_out <= selected_pixel;
        pixel_out_valid <= 1'b1;
        pixel_out_start_of_frame <= pixel_in_start_of_frame;
        pixel_out_end_of_line <= pixel_in_end_of_line;
        pixel_out_end_of_frame <= pixel_in_end_of_frame;
      end
    end
  end

endmodule
