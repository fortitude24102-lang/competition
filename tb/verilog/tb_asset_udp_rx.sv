`timescale 1ns/1ps
module tb_asset_udp_rx;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [7:0] rx_byte=0;
    reg rx_valid=0, rx_last=0;
    reg [15:0] rx_length=0;
    reg [31:0] current_session=32'h12345678;
    wire rx_ready, meta_valid, payload_valid, payload_last, stream_error;
    reg meta_ready=0, payload_ready=0;
    wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,meta_crc32,error_count;
    wire [15:0] meta_length,meta_flags;
    wire [7:0] payload_data;
    reg [7:0] packet[0:1055];
    asset_udp_rx #(.TIMEOUT_CYCLES(8)) dut(.*);

    task automatic make_packet(input integer length);
        integer i;
        integer b;
        reg [31:0] crc;
        begin
            for(i=0;i<length;i=i+1) packet[i]=i>=32 ? 8'(i-32) : 0;
            packet[0]=8'h41; packet[1]=8'h53; packet[2]=8'h53; packet[3]=8'h54;
            packet[5]=1; packet[7]=2;
            packet[8]=8'h12; packet[9]=8'h34; packet[10]=8'h56; packet[11]=8'h78;
            packet[15]=7;
            packet[20]=8'((length-32)>>8); packet[21]=8'(length-32);
            packet[23]=1;
            crc=32'hffffffff;
            for(i=32;i<length;i=i+1) begin
                crc=crc^packet[i];
                for(b=0;b<8;b=b+1) crc=crc[0] ? (crc>>1)^32'hedb88320 : crc>>1;
            end
            crc=~crc;
            {packet[28],packet[29],packet[30],packet[31]}=crc;
        end
    endtask

    task automatic send_packet(input integer actual_length,input integer announced_length);
        integer i;
        begin
            for(i=0;i<actual_length;i=i+1) begin
                @(negedge clk);
                rx_valid=1; rx_byte=packet[i]; rx_last=(i==actual_length-1);
                rx_length=16'(announced_length);
                if(!rx_ready) $fatal(1,"RX unexpectedly backpressured");
            end
            @(negedge clk);
            rx_valid=0; rx_last=0;
        end
    endtask

    task automatic receive_packet(input integer length);
        integer i;
        begin
            repeat(3) @(negedge clk);
            if(!meta_valid || meta_session!=32'h12345678 || meta_asset_id!=7 ||
                meta_length!=16'(length-32) || meta_flags!=1)
                $fatal(1,"metadata mismatch");
            meta_ready=1;
            @(negedge clk); meta_ready=0;
            for(i=0;i<length-32;i=i+1) begin
                payload_ready=(i%3!=0);
                if(!payload_ready) begin
                    if(!payload_valid || payload_data!=8'(i)) $fatal(1,"unstable payload");
                    @(negedge clk);
                    payload_ready=1;
                end
                if(!payload_valid || payload_data!=8'(i) || payload_last!=(i==length-33))
                    $fatal(1,"payload mismatch at byte %0d",i);
                @(negedge clk);
            end
            payload_ready=0;
        end
    endtask

    initial begin
        repeat(3) @(negedge clk); reset=0;
        make_packet(96); send_packet(96,96); receive_packet(96);
        if(error_count!=0) $fatal(1,"legal packet rejected");
        make_packet(96); packet[7]=1; send_packet(96,96);
        repeat(3) @(negedge clk);
        if(meta_valid || error_count!=1) $fatal(1,"GET was accepted");
        make_packet(96); send_packet(95,96);
        repeat(3) @(negedge clk);
        if(meta_valid || error_count!=2) $fatal(1,"truncation was accepted");
        make_packet(96); packet[8]=0; send_packet(96,96);
        repeat(3) @(negedge clk);
        if(meta_valid || error_count!=3) $fatal(1,"wrong session was accepted");
        make_packet(96); send_packet(96,96); receive_packet(96);
        if(error_count!=3) $fatal(1,"recovery failed");
        make_packet(1056); send_packet(1056,1056); receive_packet(1056);
        make_packet(96); send_packet(96,1057);
        repeat(3) @(negedge clk);
        if(meta_valid || error_count!=4) $fatal(1,"oversized packet accepted");
        make_packet(96);
        @(negedge clk); rx_valid=1; rx_byte=packet[0]; rx_length=96; rx_last=0;
        @(negedge clk); rx_valid=0;
        repeat(11) @(negedge clk);
        if(meta_valid || error_count!=5) $fatal(1,"stalled packet did not timeout");
        make_packet(96); send_packet(96,96); receive_packet(96);
        if(error_count!=5) $fatal(1,"timeout recovery failed");
        make_packet(96);packet[32]=packet[32]^1;send_packet(96,96);
        repeat(3) @(negedge clk);
        if(meta_valid || error_count!=6) $fatal(1,"bad payload CRC accepted");
        make_packet(35);packet[23]=0;send_packet(35,35);
        repeat(3) @(negedge clk);
        if(meta_valid || error_count!=7) $fatal(1,"unaligned non-LAST accepted");
        make_packet(35);send_packet(35,35);receive_packet(35);
        $display("PASS asset_udp_rx valid/bad type/truncation/session/backpressure/boundaries/timeout/recovery");
        $finish;
    end
endmodule
