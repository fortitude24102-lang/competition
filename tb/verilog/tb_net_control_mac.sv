`timescale 1ns/1ps
// Real vendor MAC peers, management RX/TX while Asset DMA is inactive, then
// ASST after a management session changed the last shared TX descriptor.
module tb_net_control_mac;
    reg gpu_clk=0,ge_clk=0,gpu_reset=1,ge_reset=1;
    always #5 gpu_clk=~gpu_clk;always #4 ge_clk=~ge_clk;
    reg [15:0] paddr=0;reg psel=0,penable=0,pwrite=0;reg [31:0] pwdata=0;
    wire [31:0] prdata;wire pready,pslverror;
    wire gmii_rx_valid,gmii_tx_valid;wire [7:0] gmii_rx_data,gmii_tx_data;
    reg [31:0] asset_session=32'h12345678;reg asset_active=0,asset_abort=0,asset_drop=0;
    wire meta_valid,payload_valid,payload_last,stream_error;reg meta_ready=0,payload_ready=0;
    wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,meta_crc32;
    wire [15:0] meta_length,meta_flags;wire [7:0] payload_data;
    reg control_tx_valid=0;wire control_tx_ready,control_tx_done,control_tx_error;
    reg [1023:0] control_tx_packet=0;reg [15:0] control_tx_length=128;
    reg [31:0] control_tx_session=32'hdeadbeef,control_tx_local_ip=32'hc0a80002,control_tx_peer_ip=32'hc0a80003,control_tx_ports=32'h1f9a1f9a;
    wire [7:0] control_rx_byte;wire control_rx_valid,control_rx_last;reg control_rx_ready=1;wire [15:0] control_rx_length;
    wire [31:0] configured_local_ip,configured_peer_ip;
    efinix_asset_network_shared #(.TX_TIMEOUT_CYCLES(20000),.ENABLE_CONTROL(1)) dut(.*);
    reg peer_req=0,peer_wr=0,peer_arp_req=0;reg [7:0] peer_data=0;reg [15:0] peer_length=32;
    wire peer_ram_req,peer_end,peer_rx_valid;wire [15:0] peer_rx_length;
    wire [7:0] peer_rx_byte;reg [10:0] peer_rx_address=0;
    mac_top peer(.gmii_tx_clk(ge_clk),.gmii_rx_clk(ge_clk),.rst_n(!ge_reset),
        .source_mac_addr(48'h020000000003),.TTL(8'd64),.source_ip_addr(32'hc0a80003),.destination_ip_addr(32'hc0a80002),
        .udp_send_source_port(16'd8090),.udp_send_destination_port(16'd8090),
        .ram_wr_data(peer_data),.ram_wr_en(peer_wr),.udp_ram_data_req(peer_ram_req),.udp_send_data_length(peer_length),
        .udp_tx_req(peer_req),.arp_request_req(peer_arp_req),.mac_data_valid(gmii_rx_valid),.mac_send_end(peer_end),.mac_tx_data(gmii_rx_data),
        .rx_dv(gmii_tx_valid),.mac_rx_datain(gmii_tx_data),.udp_rec_ram_rdata(peer_rx_byte),.udp_rec_ram_read_addr(peer_rx_address),
        .udp_rec_data_length(peer_rx_length),.udp_rec_data_valid(peer_rx_valid),.arp_found(),.mac_not_exist());
    reg [7:0] bytes[0:95];integer i,b,received=0;reg [31:0] crc;
    always @(posedge ge_clk) if(control_rx_valid && control_rx_ready) begin
        if(control_rx_byte!==bytes[received] || control_rx_last!==(received==31) || control_rx_length!=32) $fatal(1,"management RX corruption %d",received);
        received=received+1;
    end
    task automatic send_peer(input integer count);
        integer j;
        begin
            @(negedge ge_clk);peer_length=16'(count);peer_req=1;
            wait(peer_ram_req);@(negedge ge_clk);peer_req=0;repeat(2) @(negedge ge_clk);
            for(j=0;j<count;j=j+1) begin peer_wr=1;peer_data=bytes[j];@(negedge ge_clk);end
            peer_wr=0;wait(peer_end);repeat(300) @(negedge ge_clk);
        end
    endtask
    task automatic apb_write(input [15:0] address,input [31:0] value);
        begin
            @(negedge gpu_clk);paddr=address;pwdata=value;pwrite=1;psel=1;penable=0;
            @(negedge gpu_clk);penable=1;#1;if(pslverror) $fatal(1,"resource APB rejected");
            @(negedge gpu_clk);psel=0;penable=0;pwrite=0;
        end
    endtask
    initial begin
        for(i=0;i<128;i=i+1) control_tx_packet[i*8+:8]=8'(i);
        #100;gpu_reset=0;ge_reset=0;repeat(25) @(negedge gpu_clk);
        @(negedge ge_clk);control_tx_valid=1;do @(posedge ge_clk);while(!control_tx_ready);
        @(negedge ge_clk);control_tx_valid=0;
        // Mutate producer after acceptance: wrapper must own a complete copy.
        control_tx_packet=0;
        wait(peer_rx_valid);repeat(4) @(negedge ge_clk);
        if(peer_rx_length!=136) $fatal(1,"128 payload UDP length %d",peer_rx_length);
        for(i=0;i<128;i=i+1) begin
            peer_rx_address=11'(i);repeat(2) @(negedge ge_clk);
            if(peer_rx_byte!==8'(i)) $fatal(1,"128 payload byte %d got %h",i,peer_rx_byte);
        end
        if(dut.tx_count!=0 || dut.busy) $fatal(1,"management changed resource completion");
        @(negedge ge_clk);peer_arp_req=1;@(negedge ge_clk);peer_arp_req=0;
        wait(!peer.mac_not_exist);repeat(300) @(negedge ge_clk);
        for(i=0;i<32;i=i+1) bytes[i]=8'(i);
        {bytes[0],bytes[1],bytes[2],bytes[3]}=32'h41474331;
        send_peer(32);if(received!=32 || meta_valid || payload_valid) $fatal(1,"control leaked into inactive Asset DMA");
        asset_active=1;
        // ASST DATA answers an independent resource request, not control TX.
        for(i=0;i<8;i=i+1) apb_write(16'(16'h0220+4*i),32'h41535354+i);
        apb_write(16'h0208,1);wait(!dut.busy);repeat(300) @(negedge ge_clk);
        // Change the shared descriptor again after the resource request.
        @(negedge ge_clk);control_tx_length=32;control_tx_valid=1;
        do @(posedge ge_clk);while(!control_tx_ready);
        @(negedge ge_clk);control_tx_valid=0;wait(control_tx_done);repeat(300) @(negedge ge_clk);
        for(i=0;i<96;i=i+1) bytes[i]=i>=32?8'(i-32):0;
        {bytes[0],bytes[1],bytes[2],bytes[3]}=32'h41535354;
        bytes[5]=1;bytes[7]=2;{bytes[8],bytes[9],bytes[10],bytes[11]}=asset_session;
        bytes[15]=7;bytes[21]=64;bytes[23]=1;
        crc=32'hffffffff;for(i=32;i<96;i=i+1) begin crc=crc^bytes[i];for(b=0;b<8;b=b+1) crc=crc[0]?(crc>>1)^32'hedb88320:crc>>1;end
        {bytes[28],bytes[29],bytes[30],bytes[31]}=~crc;
        fork send_peer(96);begin
            wait(meta_valid);@(negedge gpu_clk);if(meta_session!=asset_session || meta_length!=64) $fatal(1,"resource session contaminated");
            meta_ready=1;@(negedge gpu_clk);meta_ready=0;
            for(i=0;i<64;i=i+1) begin
                wait(payload_valid);@(negedge gpu_clk);if(payload_data!==8'(i)) $fatal(1,"ASST payload %d",i);
                payload_ready=1;@(negedge gpu_clk);payload_ready=0;
            end
        end join
        // Invalid TX lengths must produce a bounded error without RAM writes.
        @(negedge ge_clk);control_tx_length=64;control_tx_valid=1;
        do @(posedge ge_clk);while(!control_tx_ready);
        @(negedge ge_clk);control_tx_valid=0;
        wait(control_tx_done);if(!control_tx_error) $fatal(1,"unsupported length accepted");
        $display("PASS shared real MAC immutable128 management without DMA RX split independent ASST session length rejection");$finish;
    end
    initial begin #400000;$fatal(1,"shared MAC timeout tx=%d rx=%b peer=%b resource=%h meta=%b",dut.u_ge.tx_state,dut.u_ge.udp_valid,peer_rx_valid,dut.resource_session,meta_valid);end
endmodule
