module efinix_user_keys_gpio (
    input wire core_clk,
    input wire reset_n,
    input wire [1:0] user_keys_n,
    input wire [3:0] soc_gpio_IN,
    output wire [3:0] sapphire_gpio_IN
);
    // KEY1/KEY2 contacts are input-only and active low. Debounce is in C.
    (* ASYNC_REG = "TRUE" *) reg [1:0] keys_meta_n;
    (* ASYNC_REG = "TRUE" *) reg [1:0] keys_sync_n;
    always @(posedge core_clk or negedge reset_n) begin
        if (!reset_n) begin
            keys_meta_n <= 2'b11;
            keys_sync_n <= 2'b11;
        end else begin
            keys_meta_n <= user_keys_n;
            keys_sync_n <= keys_meta_n;
        end
    end
    assign sapphire_gpio_IN = {soc_gpio_IN[3:2], keys_sync_n};
endmodule
