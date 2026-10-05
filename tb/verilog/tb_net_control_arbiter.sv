`timescale 1ns/1ps
module tb_net_control_arbiter;
    reg clk=0,reset=1;always #5 clk=~clk;
    reg asset_tx_valid=0,control_tx_valid=0;wire asset_tx_ready,control_tx_ready;
    reg [31:0] asset_session=32'haaaa,control_session=32'hbbbb;
    reg [31:0] asset_ports=32'h1f901f90,control_ports=32'h1f9a1f9a;
    reg [31:0] asset_peer_ip=3,asset_local_ip=2,control_peer_ip=5,control_local_ip=4;
    reg [15:0] asset_length=32,control_length=128;
    reg [1023:0] asset_packet=1024'h11223344,control_packet=1024'haabbccdd;
    wire asset_done,asset_error,control_done,control_error;
    wire tx_valid;reg tx_ready=0;wire [31:0] tx_session,tx_ports,tx_peer_ip,tx_local_ip;
    wire [15:0] tx_length;wire [1023:0] tx_packet;reg tx_done=0,tx_error=0;
    udp_tx_arbiter dut(.*);
    integer count=0;reg owners[0:3];
    always @(posedge clk) if(tx_valid && tx_ready) begin
        owners[count]=control_tx_ready;
        if(control_tx_ready) begin
            if(tx_packet!==control_packet || tx_session!==control_session || tx_ports!==control_ports || tx_peer_ip!==control_peer_ip || tx_local_ip!==control_local_ip || tx_length!=128) $fatal(1,"control descriptor torn");
        end else if(tx_packet!==asset_packet || tx_session!==asset_session || tx_ports!==asset_ports || tx_peer_ip!==asset_peer_ip || tx_local_ip!==asset_local_ip || tx_length!=32) $fatal(1,"asset descriptor torn");
        count=count+1;
    end
    task automatic complete(input bit error_value);
        begin
            repeat(4) @(negedge clk);
            if(tx_valid || asset_tx_ready || control_tx_ready) $fatal(1,"packet owner changed mid-flight");
            tx_done=1;tx_error=error_value;#1;
            if(owners[count-1]) begin if(!control_done || control_error!=error_value || asset_done || asset_error) $fatal(1,"control completion routing");end
            else if(!asset_done || asset_error!=error_value || control_done || control_error) $fatal(1,"asset completion routing");
            @(negedge clk);tx_done=0;tx_error=0;
        end
    endtask
    initial begin
        #30;reset=0;@(negedge clk);asset_tx_valid=1;control_tx_valid=1;
        repeat(4) @(negedge clk);if(count!=0) $fatal(1,"ignored MAC backpressure");
        tx_ready=1;@(negedge clk);complete(0);
        @(negedge clk);complete(1);
        @(negedge clk);complete(0);
        if(count!=3 || owners[0]==owners[1] || owners[1]==owners[2]) $fatal(1,"packet round robin fairness");
        asset_tx_valid=0;control_tx_valid=0;reset=1;#12;reset=0;
        @(negedge clk);tx_done=1;tx_error=1;#1;if(asset_done || control_done || asset_error || control_error) $fatal(1,"idle completion leaked");
        $display("PASS TX packet arbitration descriptor ownership backpressure fairness done/error/reset");$finish;
    end
    initial begin #10000;$fatal(1,"arbiter timeout");end
endmodule
