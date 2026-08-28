module VideoAccelTop (
    input  wire        clock,
    input  wire        reset,
    input  wire [23:0] pixel_in,
    input  wire        pixel_in_valid,
    input  wire        enable,
    input  wire [1:0]  mode,
    input  wire [7:0]  threshold,
    input  wire        bypass,
    output reg  [23:0] pixel_out,
    output reg         pixel_out_valid,
    output reg         busy,
    output reg         frame_done
);

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
      busy            <= 1'b0;
      frame_done      <= 1'b0;
    end else begin
      pixel_out_valid <= pixel_in_valid && enable;
      busy            <= pixel_in_valid && enable;
      frame_done      <= pixel_in_valid && enable;
      if (pixel_in_valid && enable)
        pixel_out <= selected_pixel;
    end
  end

endmodule

