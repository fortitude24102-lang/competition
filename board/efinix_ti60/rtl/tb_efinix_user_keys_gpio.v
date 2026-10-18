`timescale 1ns/1ps
module tb_efinix_user_keys_gpio;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 1;
    reg [1:0] keys_n = 0;
    reg [3:0] gpio_in = 4'b1010;
    wire [3:0] sapphire_in;
    efinix_user_keys_gpio dut(clk, reset_n, keys_n, gpio_in, sapphire_in);
    integer failures = 0;

    task check;
        input [3:0] expected;
        begin
            #1;
            if (sapphire_in !== expected) begin
                $display("FAIL t=%0t got=%b expected=%b", $time, sapphire_in, expected);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        #1 reset_n = 0;
        check(4'b1011); // Reset reads both keys released despite low pads.
        @(negedge clk) reset_n = 1;
        @(posedge clk) check(4'b1011); // First stage only.
        @(posedge clk) check(4'b1000); // Second stage reaches GPIO.
        @(negedge clk) keys_n = 2'b10;
        check(4'b1000); // Async pads cannot bypass synchronization.
        @(posedge clk) check(4'b1000);
        @(posedge clk) check(4'b1010);
        @(negedge clk) gpio_in = 4'b0101;
        check(4'b0110); // Preserve upper bits; LED pad lower bits ignored.
        #1 reset_n = 0;
        check(4'b0111);
        if (failures) $fatal(1, "key GPIO synchronization failed");
        $display("PASS user keys GPIO: reset, two flip-flops, polarity, upper GPIO preservation");
        $finish;
    end
endmodule
