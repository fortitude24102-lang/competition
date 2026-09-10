`timescale 1ps/1ps
module tb_hdmi_subsystem;
    reg gpu_clk = 0, pixel_clk = 0;
    reg gpu_reset = 1, pixel_reset = 1;
    reg [15:0] gpu_pixel = 0;
    reg gpu_valid = 0, gpu_line_last = 0, gpu_frame_last = 0;
    wire gpu_ready, vblank_gpu, vblank, fifo_full, fifo_empty, protocol_error;
    wire [11:0] fifo_level;
    wire [9:0] tmds_data0_o, tmds_data1_o, tmds_data2_o, tmds_clk_o;
    wire tmds_data0_TX_OE, tmds_data1_TX_OE, tmds_data2_TX_OE, tmds_clk_TX_OE;
    wire tmds_data0_TX_RST, tmds_data1_TX_RST, tmds_data2_TX_RST, tmds_clk_TX_RST;
    wire [15:0] video_rgb565;
    wire video_hs, video_vs, video_de;
    integer source_x, source_y, source_frame;
    integer checked_frames, active_count, scaled_count, vblank_count;

    hdmi_subsystem dut (.*);
    always #5000 gpu_clk = ~gpu_clk;
    always #3367 pixel_clk = ~pixel_clk;

    function automatic [15:0] pattern(input integer x, input integer y, input integer frame);
        pattern = (((x & 31) << 11) | ((y & 63) << 5) | ((x ^ y) & 31)) ^ (frame * 16'h4211);
    endfunction

    function automatic [7:0] decode(input [9:0] physical);
        reg [9:0] word;
        reg [7:0] q;
        begin
            word = ~physical;
            q = word[7:0] ^ {8{word[9]}};
            decode = {q[7:1] ^ q[6:0] ^ {7{!word[8]}}, q[0]};
        end
    endfunction

    initial begin
        source_x = 0; source_y = 0; source_frame = 0;
        checked_frames = 0; active_count = 0; scaled_count = 0; vblank_count = 0;
        #37000 gpu_reset = 0;
        #46000 pixel_reset = 0;
        while (source_frame < 3) begin
            @(negedge gpu_clk);
            if (gpu_ready) begin
                gpu_valid = 1;
                gpu_pixel = pattern(source_x, source_y, source_frame);
                gpu_line_last = source_x == 639;
                gpu_frame_last = source_x == 639 && source_y == 479;
                if (source_x == 639) begin
                    source_x = 0;
                    if (source_y == 479) begin source_y = 0; source_frame = source_frame + 1; end
                    else source_y = source_y + 1;
                end else source_x = source_x + 1;
            end else gpu_valid = 0;
        end
        @(negedge gpu_clk); gpu_valid = 0; gpu_line_last = 0; gpu_frame_last = 0;
    end

    always @(posedge gpu_clk) begin
        if (!gpu_reset && vblank_gpu) vblank_count <= vblank_count + 1;
        if (!gpu_reset && fifo_level > 2048) $fatal(1, "FIFO level overflow: %0d", fifo_level);
    end

    always @(negedge pixel_clk) begin : video_check
        integer h, v, ax, ay, sx, sy;
        reg expected_de, expected_scaled;
        h = dut.u_scale.h_count;
        v = dut.u_scale.v_count;
        expected_de = h >= 192 && h < 2112 && v >= 41 && v < 1121;
        ax = h - 192; ay = v - 41;
        expected_scaled = expected_de && ax >= 320 && ax < 1600 && ay >= 60 && ay < 1020;
        if (!pixel_reset) begin
            if (video_de !== expected_de) $fatal(1, "DE mismatch at %0d,%0d", h, v);
            if (video_hs !== (h < 44)) $fatal(1, "HS mismatch at %0d", h);
            if (video_vs !== (v < 5)) $fatal(1, "VS mismatch at %0d", v);
            if (vblank !== !(v >= 41 && v < 1121)) $fatal(1, "vblank mismatch at %0d", v);
            if (checked_frames >= 1 && expected_de) begin
                active_count = active_count + 1;
                if (expected_scaled) begin
                    sx = (ax - 320) >> 1; sy = (ay - 60) >> 1;
                    scaled_count = scaled_count + 1;
                    if (video_rgb565 !== pattern(sx, sy, checked_frames))
                        $fatal(1, "scaled pixel mismatch at %0d,%0d got %h expected %h", h, v, video_rgb565, pattern(sx, sy, checked_frames));
                end else if (video_rgb565 !== 16'h0000)
                    $fatal(1, "border is not black at %0d,%0d", h, v);
            end
            if (h == 2199 && v == 1124) begin
                checked_frames = checked_frames + 1;
                if (checked_frames == 3) begin
                    if (active_count != 2*1920*1080 || scaled_count != 2*1280*960)
                        $fatal(1, "frame geometry mismatch active=%0d scaled=%0d", active_count, scaled_count);
                    if (vblank_count != 3 || protocol_error)
                        $fatal(1, "CDC/display status failure pulses=%0d protocol=%b", vblank_count, protocol_error);
                    if ({tmds_data0_TX_OE,tmds_data1_TX_OE,tmds_data2_TX_OE,tmds_clk_TX_OE} !== 4'hf ||
                        {tmds_data0_TX_RST,tmds_data1_TX_RST,tmds_data2_TX_RST,tmds_clk_TX_RST} !== 4'h0 ||
                        tmds_clk_o !== 10'b0000011111)
                        $fatal(1, "official HDMI serializer boundary mismatch");
                    $display("PASS display: official FIFO CDC, two frame-distinct 640x480 logs, centered 1280x960, vblank sync, official TMDS boundary");
                    $finish;
                end
            end
        end
    end

    initial begin
        #(80ms);
        $fatal(1, "HDMI subsystem timeout");
    end
endmodule
