`timescale 1ns/1ps
module udp_tx_arbiter (
    input wire clk,reset,
    input wire asset_tx_valid,output wire asset_tx_ready,
    input wire [31:0] asset_session,asset_ports,asset_peer_ip,asset_local_ip,
    input wire [15:0] asset_length,input wire [1023:0] asset_packet,
    output wire asset_done,asset_error,
    input wire control_tx_valid,output wire control_tx_ready,
    input wire [31:0] control_session,control_ports,control_peer_ip,control_local_ip,
    input wire [15:0] control_length,input wire [1023:0] control_packet,
    output wire control_done,control_error,
    output wire tx_valid,input wire tx_ready,
    output wire [31:0] tx_session,tx_ports,tx_peer_ip,tx_local_ip,
    output wire [15:0] tx_length,output wire [1023:0] tx_packet,
    input wire tx_done,tx_error
);
    reg active,owner,prefer_control;
    wire select_control=control_tx_valid && (!asset_tx_valid || prefer_control);
    assign tx_valid=!active && (asset_tx_valid || control_tx_valid);
    assign control_tx_ready=!active && tx_ready && select_control;
    assign asset_tx_ready=!active && tx_ready && !select_control;
    assign tx_packet=select_control ? control_packet : asset_packet;
    assign tx_length=select_control ? control_length : asset_length;
    assign tx_session=select_control ? control_session : asset_session;
    assign tx_ports=select_control ? control_ports : asset_ports;
    assign tx_peer_ip=select_control ? control_peer_ip : asset_peer_ip;
    assign tx_local_ip=select_control ? control_local_ip : asset_local_ip;
    assign asset_done=active && !owner && tx_done;
    assign asset_error=asset_done && tx_error;
    assign control_done=active && owner && tx_done;
    assign control_error=control_done && tx_error;
    always @(posedge clk or posedge reset) begin
        if(reset) begin active<=0;owner<=0;prefer_control<=0;end
        else begin
            if(tx_valid && tx_ready) begin active<=1;owner<=select_control;prefer_control<=!select_control;end
            if(active && tx_done) active<=0;
        end
    end
endmodule
