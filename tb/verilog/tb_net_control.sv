`timescale 1ns/1ps
// Detects header corruption, admission without validation, torn APB snapshots,
// unbounded CPU backpressure, stale timestamps, and mutable in-flight TX.
module tb_net_control;
    reg gpu_clk=0,ge_clk=0,gpu_reset=1,ge_reset=1;
    always #5 gpu_clk=~gpu_clk;
    always #7 ge_clk=~ge_clk;
    reg [7:0] rx_byte=0;reg rx_valid=0,rx_last=0;reg [15:0] rx_length=0;
    wire rx_ready;wire [7:0] asset_byte,control_byte;
    wire asset_valid,asset_last,control_valid,control_ready,control_last;
    reg asset_ready=1;wire [15:0] asset_length,control_length;
    udp_payload_router router(.clk(ge_clk),.reset(gpu_reset|ge_reset),.*);
    wire [255:0] packet;wire packet_valid,packet_ready;wire [31:0] arrival_ms,drop_count,ge_time_ms;
    control_udp_rx parser(.clk(ge_clk),.reset(gpu_reset|ge_reset),.rx_byte(control_byte),.rx_valid(control_valid),.rx_ready(control_ready),.rx_last(control_last),.rx_length(control_length),.current_ms(ge_time_ms),.*);
    reg [15:0] paddr=0;reg psel=0,penable=0,pwrite=0;reg [31:0] pwdata=0;
    wire [31:0] prdata;wire pready,pslverror;
    wire [1023:0] tx_packet;wire [15:0] tx_length;wire tx_packet_valid;
    reg tx_packet_ready=0,tx_done=0,tx_error=0;
    reg [31:0] configured_local_ip=32'hc0a80002,configured_peer_ip=32'hc0a80003;
    wire [31:0] tx_local_ip,tx_peer_ip;
    net_control_bridge #(.GPU_CYCLES_PER_MS(100)) bridge(.*,.rx_packet(packet),.rx_packet_valid(packet_valid),.rx_packet_ready(packet_ready),.rx_arrival_ms(arrival_ms),.rx_drop_count(drop_count));
    reg [7:0] bytes[0:63];integer asset_count=0,accepted=0;
    reg [255:0] golden;
    always @(posedge ge_clk) begin
        if(asset_valid && asset_ready) begin
            if(asset_byte!==8'(asset_count<4 ? (asset_count==0?65:asset_count==1?83:asset_count==2?83:84):asset_count)) $fatal(1,"ASST replay corrupted byte %0d",asset_count);
            if(asset_last!==(asset_count==9)) $fatal(1,"ASST last corruption");
            asset_count=asset_count+1;
        end
        if(packet_valid && packet_ready) accepted=accepted+1;
    end
    task automatic make_control(input integer kind,input integer sequence_value);
        reg [31:0] crc;integer i,b;
        begin
            for(i=0;i<64;i=i+1) bytes[i]=0;
            {bytes[0],bytes[1],bytes[2],bytes[3]}=32'h41474331;
            bytes[4]=1;bytes[5]=8'(kind);bytes[7]=32;
            {bytes[8],bytes[9],bytes[10],bytes[11]}=32'h12345678;
            {bytes[12],bytes[13],bytes[14],bytes[15]}=32'(sequence_value);
            if(kind==2) bytes[19]=8'h11;
            crc=32'hffffffff;
            for(i=0;i<28;i=i+1) begin
                crc=crc^bytes[i];for(b=0;b<8;b=b+1) crc=crc[0]?(crc>>1)^32'hedb88320:crc>>1;
            end
            {bytes[28],bytes[29],bytes[30],bytes[31]}=~crc;
        end
    endtask
    task automatic seal_control;
        reg [31:0] c;integer j,b;
        begin
            c=32'hffffffff;
            for(j=0;j<28;j=j+1) begin c=c^bytes[j];for(b=0;b<8;b=b+1) c=c[0]?(c>>1)^32'hedb88320:c>>1;end
            {bytes[28],bytes[29],bytes[30],bytes[31]}=~c;
        end
    endtask
    task automatic send_bytes(input integer count,input integer declared,input integer last_at);
        integer i;
        begin
            for(i=0;i<count;i=i+1) begin
                @(negedge ge_clk);rx_byte=bytes[i];rx_valid=1;rx_last=(i==last_at);rx_length=16'(declared);
                do @(posedge ge_clk);while(!rx_ready);
            end
            @(negedge ge_clk);rx_valid=0;rx_last=0;
            repeat(16) @(negedge gpu_clk);
        end
    endtask
    task automatic apb(input bit write,input [15:0] address,input [31:0] value,input bit err,input [31:0] expected,input bit check_value);
        begin
            @(negedge gpu_clk);paddr=address;pwdata=value;pwrite=write;psel=1;penable=0;
            @(negedge gpu_clk);penable=1;#1;
            if(pslverror!==err || !pready) $fatal(1,"APB %h error expected %b got %b",address,err,pslverror);
            if(check_value && prdata!==expected) $fatal(1,"APB %h expected %h got %h",address,expected,prdata);
            @(negedge gpu_clk);psel=0;penable=0;pwrite=0;
        end
    endtask
    integer i,k,old_accepted;reg [31:0] frozen_age;
    initial begin
        #100;gpu_reset=0;ge_reset=0;repeat(40) @(negedge gpu_clk);
        apb(0,16'h0300,0,0,32'h4d475431,1);
        apb(0,16'h0320,0,1,0,0);apb(1,16'h030c,1,1,0,0);
        for(i=0;i<10;i=i+1) bytes[i]=8'(i);
        {bytes[0],bytes[1],bytes[2],bytes[3]}=32'h41535354;
        fork begin asset_ready=0;repeat(20) @(negedge ge_clk);asset_ready=1;end send_bytes(10,10,9);join
        if(asset_count!=10) $fatal(1,"ASST truncated");
        bytes[0]=0;send_bytes(10,10,9);send_bytes(3,3,2);
        make_control(1,1);send_bytes(32,32,31);
        if(accepted!=1) $fatal(1,"valid HELLO lost");
        apb(1,16'h0308,1,0,0,0);apb(0,16'h0320,0,0,32'h31434741,1);
        @(negedge gpu_clk);paddr=16'h0310;#1;frozen_age=prdata;
        make_control(2,2);send_bytes(32,32,31);
        apb(0,16'h032c,0,0,32'h01000000,1);
        repeat(250) @(negedge gpu_clk);
        apb(0,16'h0310,0,0,frozen_age,1);
        apb(1,16'h030c,1,0,0,0);apb(1,16'h030c,1,1,0,0);
        apb(1,16'h0308,1,0,0,0);apb(0,16'h032c,0,0,32'h02000000,1);apb(1,16'h030c,1,0,0,0);
        old_accepted=accepted;
        make_control(2,3);bytes[19]=8'hff;send_bytes(32,32,31);
        make_control(3,3);send_bytes(32,32,31);
        make_control(2,3);bytes[16]=1;send_bytes(32,32,31);
        make_control(1,3);send_bytes(31,32,30);
        make_control(1,3);send_bytes(33,32,32);
        make_control(1,3);send_bytes(32,33,31);
        if(accepted!=old_accepted || drop_count!=6) $fatal(1,"invalid acceptance/drop count %d %d",accepted,drop_count);
        for(k=0;k<7;k=k+1) begin make_control(2,10+k);send_bytes(32,32,31);end
        if(accepted-old_accepted!=4 || drop_count!=9) $fatal(1,"depth four overflow not drained %d %d",accepted,drop_count);
        repeat(3000) @(negedge gpu_clk);
        apb(1,16'h0308,1,0,0,0);
        @(negedge gpu_clk);paddr=16'h0310;#1;if(prdata<25) $fatal(1,"GPU millisecond age absent %d",prdata);
        for(k=0;k<4;k=k+1) begin
            if(k!=0) apb(1,16'h0308,1,0,0,0);
            apb(1,16'h030c,1,0,0,0);
        end
        make_control(1,99);send_bytes(32,32,31);if(accepted-old_accepted!=5) $fatal(1,"overflow recovery");
        apb(1,16'h0318,1,1,0,0);
        apb(1,16'h03c0,64,1,0,0);
        apb(1,16'h03c0,128,0,0,0);
        for(i=0;i<31;i=i+1) apb(1,16'(16'h0340+4*i),32'h12340000+i,0,0,0);
        apb(1,16'h0318,1,1,0,0);
        apb(1,16'h03bc,32'h1234001f,0,0,0);apb(1,16'h0318,1,0,0,0);
        wait(tx_packet_valid);#1;
        if(tx_length!=128 || tx_packet[1023:992]!=32'h1234001f || tx_packet[31:0]!=32'h12340000) $fatal(1,"TX CDC corruption");
        configured_local_ip=32'h0a010203;configured_peer_ip=32'h0a010204;#1;
        if(tx_local_ip!=32'hc0a80002 || tx_peer_ip!=32'hc0a80003) $fatal(1,"committed IP snapshot mutated");
        apb(1,16'h0340,0,1,0,0);apb(1,16'h0318,1,1,0,0);
        if(tx_packet[31:0]!=32'h12340000) $fatal(1,"busy TX mutated");
        @(negedge ge_clk);tx_packet_ready=1;@(negedge ge_clk);tx_packet_ready=0;
        repeat(10) @(negedge ge_clk);tx_done=1;tx_error=1;@(negedge ge_clk);tx_done=0;tx_error=0;
        repeat(30) @(negedge gpu_clk);apb(0,16'h031c,0,0,1,1);
        apb(1,16'h0318,1,1,0,0);
        ge_reset=1;#31;ge_reset=0;repeat(40) @(negedge gpu_clk);
        apb(0,16'h0304,0,0,4,1);apb(0,16'h0320,0,1,0,0);
        apb(1,16'h03c0,32,0,0,0);
        for(i=0;i<8;i=i+1) apb(1,16'(16'h0340+4*i),32'hdead0000+i,0,0,0);
        apb(1,16'h0318,1,0,0,0);wait(tx_packet_valid);
        gpu_reset=1;#23;gpu_reset=0;repeat(40) @(negedge gpu_clk);
        if(tx_packet_valid) $fatal(1,"GPU reset retained TX");
        apb(0,16'h0301,0,1,0,0);apb(1,16'h03c4,1,1,0,0);
        // Independent PC golden vectors; CRC values are literals, not DUT math.
        golden=256'h414743310101002012345678010203040000000000000000000000003e0b1a63;
        for(i=0;i<32;i=i+1) bytes[i]=golden[(31-i)*8+:8];send_bytes(32,32,31);
        apb(1,16'h0308,1,0,0,0);apb(1,16'h0308,1,1,0,0);
        apb(0,16'h032c,0,0,32'h04030201,1);apb(0,16'h033c,0,0,32'h631a0b3e,1);apb(1,16'h030c,1,0,0,0);
        golden=256'h41474331010200201234567801020305000000ffa1b2c3d400000000e633fa88;
        for(i=0;i<32;i=i+1) bytes[i]=golden[(31-i)*8+:8];send_bytes(32,32,31);
        apb(1,16'h0308,1,0,0,0);apb(0,16'h0330,0,0,32'hff000000,1);apb(0,16'h0334,0,0,32'hd4c3b2a1,1);apb(1,16'h030c,1,0,0,0);
        old_accepted=accepted;
        make_control(1,1);bytes[19]=1;seal_control();send_bytes(32,32,31);
        make_control(2,1);bytes[16]=1;seal_control();send_bytes(32,32,31);
        make_control(2,1);bytes[27]=1;seal_control();send_bytes(32,32,31);
        make_control(1,1);bytes[4]=2;seal_control();send_bytes(32,32,31);
        if(accepted!=old_accepted || drop_count!=4) $fatal(1,"CRC-valid invalid fields admitted");
        apb(0,16'h0314,0,0,4,1);apb(1,16'h0300,1,1,0,0);
        // Eight words are sufficient for ACK, and every commit consumes its mask.
        apb(1,16'h0318,1,1,0,0);
        apb(0,16'h0304,0,0,12,1);
        for(i=0;i<8;i=i+1) apb(1,16'(16'h0340+4*i),32'hca000000+i,0,0,0);
        apb(1,16'h0318,1,0,0,0);wait(tx_packet_valid);
        apb(1,16'h03c0,128,1,0,0);
        if(tx_length!=32 || tx_packet[255:224]!=32'hca000007) $fatal(1,"32 TX wrong descriptor");
        @(negedge ge_clk);tx_packet_ready=1;@(negedge ge_clk);tx_packet_ready=0;
        repeat(10) @(negedge ge_clk);tx_done=1;@(negedge ge_clk);tx_done=0;
        repeat(30) @(negedge gpu_clk);apb(0,16'h031c,0,0,1,1);apb(0,16'h0304,0,0,4,1);
        apb(1,16'h0318,1,1,0,0);apb(0,16'h0304,0,0,12,1);
        $display("PASS control router CRC reserved fields depth4 snapshot age async reset TX atomic128");$finish;
    end
    initial begin #1000000;$fatal(1,"control timeout");end
endmodule
