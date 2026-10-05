`timescale 1ns/1ps
// Buffer and replay the classification prefix. Never share a payload with DMA.
module udp_payload_router (
    input wire clk,reset,
    input wire [7:0] rx_byte,input wire rx_valid,output wire rx_ready,
    input wire rx_last,input wire [15:0] rx_length,
    output wire [7:0] asset_byte,output wire asset_valid,input wire asset_ready,
    output wire asset_last,output wire [15:0] asset_length,
    output wire [7:0] control_byte,output wire control_valid,input wire control_ready,
    output wire control_last,output wire [15:0] control_length
);
    localparam HEADER=0,REPLAY=1,STREAM=2,DRAIN=3;
    reg [1:0] state,index;
    reg [31:0] prefix;
    reg [15:0] length;
    reg owner,header_last;
    wire selected_ready=owner ? control_ready : asset_ready;
    assign rx_ready=(state==HEADER || state==DRAIN) || (state==STREAM && selected_ready);
    assign asset_valid=!owner && (state==REPLAY || (state==STREAM && rx_valid));
    assign control_valid=owner && (state==REPLAY || (state==STREAM && rx_valid));
    assign asset_byte=state==REPLAY ? prefix[index*8+:8] : rx_byte;
    assign control_byte=asset_byte;
    assign asset_last=state==REPLAY ? (header_last && index==3) : rx_last;
    assign control_last=asset_last;
    assign asset_length=length;
    assign control_length=length;
    always @(posedge clk or posedge reset) begin
        if(reset) begin state<=HEADER;index<=0;prefix<=0;length<=0;owner<=0;header_last<=0;end
        else case(state)
            HEADER: if(rx_valid && rx_ready) begin
                prefix[index*8+:8]<=rx_byte;
                if(index==0) length<=rx_length;
                if(index==3) begin
                    index<=0;header_last<=rx_last;
                    if({rx_byte,prefix[23:0]}==32'h54535341) begin owner<=0;state<=REPLAY;end
                    // The control parser drains and counts malformed lengths.
                    else if({rx_byte,prefix[23:0]}==32'h31434741) begin owner<=1;state<=REPLAY;end
                    else state<=rx_last ? HEADER : DRAIN;
                end else if(rx_last) index<=0;
                else index<=index+1'b1;
            end
            REPLAY: if(selected_ready) begin
                if(index==3) begin index<=0;state<=header_last ? HEADER : STREAM;end
                else index<=index+1'b1;
            end
            STREAM: if(rx_valid && rx_ready && rx_last) begin state<=HEADER;index<=0;end
            DRAIN: if(rx_valid && rx_last) begin state<=HEADER;index<=0;end
        endcase
    end
endmodule
