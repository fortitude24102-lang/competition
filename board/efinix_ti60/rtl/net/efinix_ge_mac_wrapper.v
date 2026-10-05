`timescale 1ns/1ps
// Both official MAC clocks use the PHY RX clock, as in the official GE demo.
module efinix_ge_mac_wrapper #(
    parameter integer TX_TIMEOUT_CYCLES=2500000,
    parameter integer ENABLE_VARIABLE_TX=0
) (
    input wire clk,reset,
    input wire gmii_rx_valid,input wire [7:0] gmii_rx_data,
    output wire gmii_tx_valid,output wire [7:0] gmii_tx_data,
    input wire tx_valid,output wire tx_ready,
    input wire [255:0] tx_header,
    input wire [1023:0] tx_packet,input wire [15:0] tx_length,
    input wire [31:0] local_ip,peer_ip,ports,
    output reg tx_done,tx_error,
    output wire [7:0] rx_byte,output wire rx_valid,input wire rx_ready,
    output wire rx_last,output reg [15:0] rx_length
);
    localparam IDLE=0,SETTLE=1,ARP=2,ARP_WAIT=3,REQUEST=4,WRITE=5,SEND=6;
    reg [2:0] tx_state;
    reg [31:0] timer;
    reg [6:0] tx_index;
    reg [1023:0] active_packet;
    reg [15:0] active_length;
    reg [31:0] active_local_ip,active_peer_ip,active_ports;
    wire ram_req,send_end,mac_missing;
    reg ram_write;
    reg [7:0] ram_data;
    assign tx_ready=tx_state==IDLE;
    always @(posedge clk or posedge reset) begin
        if(reset) begin tx_state<=IDLE;timer<=0;tx_index<=0;tx_done<=0;tx_error<=0;ram_write<=0;ram_data<=0;active_packet<=0;active_length<=32;active_local_ip<=32'hc0a80002;active_peer_ip<=32'hc0a80003;active_ports<=32'h1f901f90;end
        else begin
            tx_done<=0;tx_error<=0;ram_write<=0;
            if(tx_state==IDLE) timer<=0; else timer<=timer+1'b1;
            if(tx_state!=IDLE && timer==TX_TIMEOUT_CYCLES) begin tx_state<=IDLE;tx_done<=1;tx_error<=1;end
            else case(tx_state)
                IDLE: if(tx_valid) begin
                    if(ENABLE_VARIABLE_TX && tx_length!=32 && tx_length!=128) begin tx_done<=1;tx_error<=1;end
                    else begin
                        active_packet<=ENABLE_VARIABLE_TX ? tx_packet : {768'b0,tx_header};
                        active_length<=ENABLE_VARIABLE_TX ? tx_length : 16'd32;
                        active_local_ip<=local_ip;active_peer_ip<=peer_ip;active_ports<=ports;
                        tx_state<=SETTLE;
                    end
                end
                SETTLE: tx_state<=mac_missing ? ARP : REQUEST;
                ARP: tx_state<=ARP_WAIT;
                ARP_WAIT: if(!mac_missing) tx_state<=REQUEST;
                REQUEST: if(ram_req) begin tx_index<=0;tx_state<=WRITE;end
                WRITE: begin
                    ram_write<=1;ram_data<=active_packet[tx_index*8+:8];
                    if({9'b0,tx_index}==active_length-1'b1) tx_state<=SEND; else tx_index<=tx_index+1'b1;
                end
                SEND: if(send_end) begin tx_state<=IDLE;tx_done<=1;end
            endcase
        end
    end

    // ponytail: one admitted frame at a time; stop-and-wait retries cover drops.
    // Never admit a new frame while the shared UDP RAM is being drained.
    reg previous_dv,admitted;
    reg [7:0] cooldown;
    wire [15:0] udp_length;
    wire udp_valid;
    reg previous_udp_valid;
    reg [1:0] read_state;
    reg [10:0] read_address;
    wire allow_frame=read_state==0 && cooldown==0;
    wire mac_rx_valid=gmii_rx_valid && (previous_dv ? admitted : allow_frame);
    assign rx_valid=read_state==2;
    assign rx_last={5'b0,read_address}==rx_length-1'b1;
    always @(posedge clk or posedge reset) begin
        if(reset) begin previous_dv<=0;admitted<=0;cooldown<=0;previous_udp_valid<=0;read_state<=0;read_address<=0;rx_length<=0;end
        else begin
            previous_dv<=gmii_rx_valid;previous_udp_valid<=udp_valid;
            if(gmii_rx_valid && !previous_dv) admitted<=allow_frame;
            if(previous_dv && !gmii_rx_valid && admitted) cooldown<=128;
            else if(cooldown!=0) cooldown<=cooldown-1'b1;
            case(read_state)
                0: if(udp_valid && !previous_udp_valid && udp_length>=8 && udp_length<=1064) begin
                    rx_length<=udp_length-8;read_address<=0;
                    if(udp_length>8) read_state<=1;
                end
                1: read_state<=2; // official dpram registers its read address
                2: if(rx_ready) begin
                    if(rx_last) read_state<=0;
                    else begin read_address<=read_address+1'b1;read_state<=1;end
                end
            endcase
        end
    end
    mac_top u_mac(
        .gmii_tx_clk(clk),.gmii_rx_clk(clk),.rst_n(!reset),
        .source_mac_addr(48'h020000000002),.TTL(8'd64),
        .source_ip_addr(active_local_ip),.destination_ip_addr(active_peer_ip),
        .udp_send_source_port(active_ports[15:0]),.udp_send_destination_port(active_ports[31:16]),
        .ram_wr_data(ram_data),.ram_wr_en(ram_write),.udp_ram_data_req(ram_req),
        .udp_send_data_length(active_length),.udp_tx_req(tx_state==REQUEST),.arp_request_req(tx_state==ARP),
        .mac_data_valid(gmii_tx_valid),.mac_send_end(send_end),.mac_tx_data(gmii_tx_data),
        .rx_dv(mac_rx_valid),.mac_rx_datain(gmii_rx_data),
        .udp_rec_ram_rdata(rx_byte),.udp_rec_ram_read_addr(read_address),
        .udp_rec_data_length(udp_length),.udp_rec_data_valid(udp_valid),
        .arp_found(),.mac_not_exist(mac_missing));
endmodule
