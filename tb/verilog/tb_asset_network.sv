`timescale 1ns/1ps
module tb_asset_network;
    reg gpu_clk=0,ge_clk=0,gpu_reset=1,ge_reset=1;
    always #5 gpu_clk=~gpu_clk;
    always #4 ge_clk=~ge_clk;
    reg [15:0] paddr=0;reg psel=0,penable=0,pwrite=0;reg [31:0] pwdata=0;
    wire [31:0] prdata;wire pready,pslverror;
    wire gmii_rx_valid,gmii_tx_valid;wire [7:0] gmii_rx_data,gmii_tx_data;
    reg [31:0] asset_session=32'h12345678;reg asset_active=1,asset_abort=0,asset_drop=0;
    wire meta_valid,payload_valid,payload_last,stream_error;reg meta_ready=0,payload_ready=0;
    wire [31:0] meta_session,meta_asset_id,meta_offset,meta_sequence,meta_crc32;
    wire [15:0] meta_length,meta_flags;wire [7:0] payload_data;
    efinix_asset_network #(.TX_TIMEOUT_CYCLES(20000)) dut(.*);
    reg peer_req=0,peer_wr=0,peer_arp_req=0;reg [7:0] peer_data=0;reg [15:0] peer_length=96;
    wire peer_ram_req,peer_end,peer_rx_valid;wire [15:0] peer_rx_length;
    wire [7:0] peer_rx_byte;reg [10:0] peer_rx_address=0;
    mac_top peer(.gmii_tx_clk(ge_clk),.gmii_rx_clk(ge_clk),.rst_n(!ge_reset),
        .source_mac_addr(48'h020000000003),.TTL(8'd64),.source_ip_addr(32'hc0a80003),.destination_ip_addr(32'hc0a80002),
        .udp_send_source_port(16'd8080),.udp_send_destination_port(16'd8080),
        .ram_wr_data(peer_data),.ram_wr_en(peer_wr),.udp_ram_data_req(peer_ram_req),.udp_send_data_length(peer_length),
        .udp_tx_req(peer_req),.arp_request_req(peer_arp_req),.mac_data_valid(gmii_rx_valid),.mac_send_end(peer_end),.mac_tx_data(gmii_rx_data),
        .rx_dv(gmii_tx_valid),.mac_rx_datain(gmii_tx_data),.udp_rec_ram_rdata(peer_rx_byte),.udp_rec_ram_read_addr(peer_rx_address),
        .udp_rec_data_length(peer_rx_length),.udp_rec_data_valid(peer_rx_valid),.arp_found(),.mac_not_exist());
    reg [7:0] packet[0:1055];
    task automatic make_packet(input integer count);
        integer i,b;reg [31:0] crc;
        begin
            for(i=0;i<count+32;i=i+1) packet[i]=i>=32 ? 8'(i-32):0;
            {packet[0],packet[1],packet[2],packet[3]}=32'h41535354;
            packet[5]=1;packet[7]=2;
            {packet[8],packet[9],packet[10],packet[11]}=asset_session;
            packet[15]=7;{packet[20],packet[21]}=16'(count);packet[23]=1;
            crc=32'hffffffff;
            for(i=32;i<count+32;i=i+1) begin
                crc=crc^packet[i];for(b=0;b<8;b=b+1) crc=crc[0] ? (crc>>1)^32'hedb88320 : crc>>1;
            end
            {packet[28],packet[29],packet[30],packet[31]}=~crc;
        end
    endtask
    task automatic apb_write(input [15:0] address,input [31:0] value,input expected_error);
        begin
            @(negedge gpu_clk);paddr=address;pwdata=value;pwrite=1;psel=1;penable=0;
            @(negedge gpu_clk);penable=1;#1;
            if(pslverror!==expected_error) $fatal(1,"APB error mismatch %h",address);
            @(negedge gpu_clk);psel=0;penable=0;pwrite=0;
        end
    endtask
    task automatic send_data(input integer count);
        integer i;
        begin
            @(negedge ge_clk);peer_length=16'(count+32);peer_req=1;
            wait(peer_ram_req);@(negedge ge_clk);peer_req=0;
            // mac_test enters WRITE_RAM on the next edge, then registers data
            // on the following edge; the MAC samples it one edge later.
            repeat(2) @(negedge ge_clk);
            for(i=0;i<count+32;i=i+1) begin peer_wr=1;peer_data=packet[i];@(negedge ge_clk);end
            peer_wr=0;wait(peer_end);repeat(300) @(negedge ge_clk);
            $display("peer DATA done %t udpvalid=%b udpstate=%h checksum=%h error=%b",$time,dut.u_ge.udp_valid,dut.u_ge.u_mac.mac_rx0.udp0.state,dut.u_ge.u_mac.mac_rx0.udp0.checksum,dut.u_ge.u_mac.mac_rx0.udp0.mac_rec_error);
        end
    endtask
    task automatic receive_data(input integer count);
        integer i;
        begin
            wait(meta_valid);@(negedge gpu_clk);
            if(meta_length!=count || meta_session!=asset_session || meta_asset_id!=7) $fatal(1,"network metadata");
            repeat(7) @(negedge gpu_clk);
            meta_ready=1;@(negedge gpu_clk);meta_ready=0;
            for(i=0;i<count;i=i+1) begin
                payload_ready=0;wait(payload_valid);@(negedge gpu_clk);
                repeat(i%3) @(negedge gpu_clk);
                if(payload_data!==8'(i) || payload_last!==(i==count-1)) $fatal(1,"network payload %d got %h",i,payload_data);
                payload_ready=1;@(negedge gpu_clk);payload_ready=0;
            end
        end
    endtask
    integer k;
    always @(posedge ge_clk) if(dut.u_ge.u_mac.mac_rx0.udp0.udp_checksum_error)
        $display("UDP checksum failure %h received length %d",dut.u_ge.u_mac.mac_rx0.udp0.checksum,dut.u_ge.u_mac.mac_rx0.udp0.udp_data_length);
    initial begin
        #100;gpu_reset=0;ge_reset=0;repeat(25) @(negedge gpu_clk);
        for(k=0;k<8;k=k+1) apb_write(16'(16'h0220+4*k),32'h41535354+k,0);
        apb_write(16'h0208,1,0);
        $display("network SEND accepted %t",$time);
        apb_write(16'h020c,0,1);
        wait(peer_rx_valid);repeat(4) @(negedge ge_clk);
        $display("network peer received GET %t",$time);
        if(peer_rx_length!=40) $fatal(1,"GET UDP length");
        wait(!dut.busy);
        if(!dut.done || dut.error || dut.tx_count!=1) $fatal(1,"GET completion");
        // The vendor peer learns its destination from ARP replies, not requests.
        // Resolve before DATA, just as the PC network stack does.
        @(negedge ge_clk);peer_arp_req=1;
        @(negedge ge_clk);peer_arp_req=0;
        wait(!peer.mac_not_exist);repeat(300) @(negedge ge_clk);
        make_packet(64);fork send_data(64);receive_data(64);join
        make_packet(1024);fork send_data(1024);receive_data(1024);join
        make_packet(64);packet[32]=8'hff;send_data(64);repeat(500) @(negedge gpu_clk);
        if(meta_valid) $fatal(1,"corrupt DATA CRC admitted");
        make_packet(64);fork send_data(64);receive_data(64);join
        // A receive-domain reset flushes both FIFO halves and APB completion state.
        ge_reset=1;#41;ge_reset=0;repeat(30) @(negedge gpu_clk);
        if(meta_valid || payload_valid || dut.busy) $fatal(1,"asynchronous reset did not flush");
        apb_write(16'h0201,1,1);
        asset_active=0;apb_write(16'h0208,1,1);
        $display("PASS network real MAC ARP/GET/DATA64/DATA1024 CRC rejection async clocks backpressure reset");$finish;
    end
    initial begin #400000;$fatal(1,"network timeout tx=%d parser=%d busy=%b rx=%b reject=%d",dut.u_ge.tx_state,dut.u_parser.state,dut.busy,dut.u_ge.udp_valid,dut.u_parser.error_count);end
endmodule
