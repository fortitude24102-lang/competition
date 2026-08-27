module timer_v2(
    input             clk,
    input             reset,
    input             config_write,
    input      [31:0] config_value,
    input             clear_interrupt,
    output     [31:0] current_value,
    output            interrupt_pending,
    output     [31:0] config_read_value
);
    reg [31:0] counter_q;
    reg [31:0] reload_q;
    reg        enabled_q;
    reg        periodic_q;
    reg        interrupt_q;

    assign current_value = enabled_q ? counter_q : 32'hffffffff;
    assign interrupt_pending = interrupt_q;
    assign config_read_value = {reload_q[31:2], periodic_q, enabled_q};

    always @(posedge clk) begin
        if (reset) begin
            counter_q <= 32'hffffffff;
            reload_q <= 32'b0;
            enabled_q <= 1'b0;
            periodic_q <= 1'b0;
            interrupt_q <= 1'b0;
        end else if (config_write) begin
            enabled_q <= config_value[0];
            periodic_q <= config_value[1];
            counter_q <= {config_value[31:2], 2'b00};
            reload_q <= {config_value[31:2], 2'b00};
            interrupt_q <= 1'b0;
        end else begin
            if (clear_interrupt)
                interrupt_q <= 1'b0;

            if (enabled_q) begin
                if (counter_q == 32'b0) begin
                    interrupt_q <= 1'b1;
                    if (periodic_q)
                        counter_q <= reload_q;
                    else begin
                        counter_q <= 32'hffffffff;
                        enabled_q <= 1'b0;
                    end
                end else begin
                    counter_q <= counter_q - 32'd4;
                end
            end
        end
    end
endmodule
