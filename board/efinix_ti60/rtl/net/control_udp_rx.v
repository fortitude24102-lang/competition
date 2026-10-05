`timescale 1ns/1ps
module control_udp_rx (
    input wire clk,reset,
    input wire [7:0] rx_byte,input wire rx_valid,output wire rx_ready,
    input wire rx_last,input wire [15:0] rx_length,input wire [31:0] current_ms,
    output reg [255:0] packet,output reg packet_valid,input wire packet_ready,
    output reg [31:0] arrival_ms,output reg [31:0] drop_count
);
    reg [255:0] buffer;
    reg [5:0] index;
    reg draining,bad_length;
    reg [31:0] crc,first_ms;
    function [31:0] crc_byte;
        input [31:0] previous;input [7:0] data;reg [31:0] c;integer b;
        begin c=previous^{24'b0,data};for(b=0;b<8;b=b+1) c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
    endfunction
    wire [31:0] received_crc={buffer[231:224],buffer[239:232],buffer[247:240],rx_byte};
    wire hello=buffer[47:40]==1;
    wire keys=buffer[47:40]==2;
    wire fields_ok=buffer[31:0]==32'h31434741 && buffer[39:32]==1 &&
        buffer[63:48]==16'h2000 && ((hello && buffer[223:128]==0) ||
        (keys && buffer[151:128]==0 && buffer[223:192]==0));
    assign rx_ready=1'b1; // FIFO saturation never holds the shared receive RAM.
    always @(posedge clk or posedge reset) begin
        if(reset) begin buffer<=0;index<=0;draining<=0;bad_length<=0;crc<=32'hffffffff;first_ms<=0;packet<=0;packet_valid<=0;arrival_ms<=0;drop_count<=0;end
        else begin
            if(packet_valid && packet_ready) packet_valid<=0;
            if(rx_valid) begin
                if(index==0 && !draining) begin first_ms<=current_ms;bad_length<=rx_length!=32;end
                if(!draining) begin
                    buffer[index*8+:8]<=rx_byte;
                    if(index<28) crc<=crc_byte(index==0 ? 32'hffffffff : crc,rx_byte);
                end
                if(rx_last) begin
                    if(!draining && index==31 && !bad_length && rx_length==32 && fields_ok && received_crc==~crc && packet_ready) begin
                        packet<={rx_byte,buffer[247:0]};arrival_ms<=first_ms;packet_valid<=1;
                    end else drop_count<=drop_count+1'b1;
                    index<=0;draining<=0;bad_length<=0;crc<=32'hffffffff;
                end else if(index==31 || draining) draining<=1;
                else index<=index+1'b1;
            end
        end
    end
endmodule
