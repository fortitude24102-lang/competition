`timescale 1ns/1ps
// Detects torn CDC data, overwriting before consumption, duplicate transfers,
// stale packets after either side resets, and failure to resume after reset.
module tb_net_async_mailbox;
    reg wr_clk=0,rd_clk=0,wr_reset=1,rd_reset=1;
    always #5 wr_clk=~wr_clk;
    always #7 rd_clk=~rd_clk;
    reg [31:0] wr_data=0;
    reg wr_valid=0,rd_ready=0;
    wire wr_ready,rd_valid;
    wire [31:0] rd_data;
    net_async_mailbox #(.DATA_WIDTH(32)) dut(.*);
    integer seen=0;
    always @(posedge rd_clk) if(rd_valid && rd_ready) seen=seen+1;
    task automatic put(input [31:0] value);
        begin
            @(negedge wr_clk);wr_data=value;wr_valid=1;
            do @(posedge wr_clk);while(!wr_ready);
            @(negedge wr_clk);wr_valid=0;wr_data=32'hbadbad00;
        end
    endtask
    task automatic take(input [31:0] expected);
        begin
            wait(rd_valid);@(negedge rd_clk);
            repeat(8) begin
                if(rd_valid!==1'b1 || rd_data!==expected || wr_ready!==1'b0)
                    $fatal(1,"mailbox snapshot/backpressure corruption");
                @(negedge rd_clk);
            end
            rd_ready=1;@(negedge rd_clk);rd_ready=0;
        end
    endtask
    integer i;
    initial begin
        #31;wr_reset=0;rd_reset=0;
        repeat(8) @(negedge wr_clk);
        if(wr_ready!==1'b1 || rd_valid!==1'b0) $fatal(1,"mailbox idle not ready");
        put(32'h01234567);take(32'h01234567);
        put(32'h89abcdef);take(32'h89abcdef);
        repeat(12) @(negedge wr_clk);
        if(seen!=2 || rd_valid) $fatal(1,"mailbox duplicated a transaction");
        put(32'hdeadbeef);wait(rd_valid);
        wr_reset=1;#23;wr_reset=0;
        repeat(12) @(negedge wr_clk);
        if(rd_valid || !wr_ready || seen!=2) $fatal(1,"source reset retained transaction");
        put(32'hcafef00d);wait(rd_valid);
        rd_reset=1;#19;rd_reset=0;
        repeat(12) @(negedge wr_clk);
        if(rd_valid || !wr_ready || seen!=2) $fatal(1,"destination reset retained transaction");
        for(i=0;i<32;i=i+1) begin
            put(32'h55000000+i);take(32'h55000000+i);
        end
        repeat(12) @(negedge wr_clk);
        if(seen!=34 || rd_valid) $fatal(1,"mailbox re-entry count mismatch");
        $display("PASS mailbox asynchronous snapshots backpressure ordering both resets re-entry");
        $finish;
    end
    initial begin #100000;$fatal(1,"mailbox timeout");end
endmodule
