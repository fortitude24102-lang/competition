`timescale 1ns/1ps
module tb_hdmi_tx_adapter;
    reg pixelclk=0, rst=0, hs=0, vs=0, de=0;
    reg [7:0] red=0, green=0, blue=0;
    wire [9:0] tmds_data0_o, tmds_data1_o, tmds_data2_o, tmds_clk_o;
    wire tmds_data0_TX_OE, tmds_data1_TX_OE, tmds_data2_TX_OE, tmds_clk_TX_OE;
    wire tmds_data0_TX_RST, tmds_data1_TX_RST, tmds_data2_TX_RST, tmds_clk_TX_RST;
    reg [23:0] pixels [0:257];
    integer i;
    hdmi_tx_adapter dut (.*);
    always #5 pixelclk = ~pixelclk;
    task automatic tick;
        @(posedge pixelclk); #1;
        if (tmds_clk_o !== 10'b0000011111 ||
            {tmds_data0_TX_OE,tmds_data1_TX_OE,tmds_data2_TX_OE,tmds_clk_TX_OE} !== 4'hf ||
            {tmds_data0_TX_RST,tmds_data1_TX_RST,tmds_data2_TX_RST,tmds_clk_TX_RST} !== 4'h0)
            $fatal(1, "Official clock inversion / serializer control mismatch");
        @(negedge pixelclk);
    endtask
    task automatic blank;
        de=0; hs=0; vs=0;
        repeat (4) tick();
    endtask
    task automatic words(input [9:0] b, g, r);
        if ({tmds_data2_o,tmds_data1_o,tmds_data0_o} !== {r,g,b})
            $fatal(1, "TMDS got R/G/B %h/%h/%h expected %h/%h/%h", tmds_data2_o,tmds_data1_o,tmds_data0_o,r,g,b);
    endtask
    // Decode the physical-boundary inversion and TMDS transition code.
    // No encode module or DUT internal nets are used to derive expectations.
    function automatic [7:0] decode(input [9:0] physical);
        reg [9:0] word;
        reg [7:0] q;
        word = ~physical;
        q = word[7:0] ^ {8{word[9]}};
        decode = {q[7:1] ^ q[6:0] ^ {7{!word[8]}},q[0]};
    endfunction
    initial begin
        // Reset is asynchronous at the encoder, and inversion yields all ones.
        #2; rst=1; #1;
        words(10'h3ff,10'h3ff,10'h3ff);
        repeat (3) tick(); rst=0;
        blank(); words(10'h0ab,10'h0ab,10'h0ab);
        hs=1; repeat (3) tick(); words(10'h354,10'h0ab,10'h0ab);
        hs=0; vs=1; repeat (3) tick(); words(10'h2ab,10'h0ab,10'h0ab);
        hs=1; repeat (3) tick(); words(10'h154,10'h0ab,10'h0ab);
        // First active sample after blanking has zero running disparity.
        blank(); de=1; red=255; green=0; blue=0;
        repeat (3) tick(); words(10'h2ff,10'h2ff,10'h1ff);
        blank(); de=1; red=0; green=255; blue=0;
        repeat (3) tick(); words(10'h2ff,10'h1ff,10'h2ff);
        blank(); de=1; red=0; green=0; blue=255;
        repeat (3) tick(); words(10'h1ff,10'h2ff,10'h2ff);
        blank(); de=1;
        for (i=0; i<258; i=i+1) begin
            pixels[i] = {8'(i),8'(i+73),8'(255-i)};
            {red,green,blue} = pixels[i];
            tick();
            if (i>=2 && {decode(tmds_data2_o),decode(tmds_data1_o),decode(tmds_data0_o)} !== pixels[i-2])
                $fatal(1,"RGB channel / pipeline mismatch at sample %0d",i-2);
        end
        #2; rst=1; #1; words(10'h3ff,10'h3ff,10'h3ff);
        de=0; repeat (3) tick(); rst=0; blank();
        words(10'h0ab,10'h0ab,10'h0ab);
        $display("PASS HDMI: real vendor encoder, four control tokens, primaries, 256 streamed RGB samples, async reset, inversion, IO controls");
        $finish;
    end
endmodule
