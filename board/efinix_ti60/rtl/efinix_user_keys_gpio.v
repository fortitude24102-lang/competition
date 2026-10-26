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

// J28 UP/DOWN/LEFT/RIGHT/MID; COM is ground, contacts have input pullups.
module efinix_nav_keys (
 input wire clk, input wire reset, input wire [4:0] keys_n,
 input wire [15:0] address, input wire [31:0] core_data,
 output wire [31:0] data
);
 (* ASYNC_REG = "TRUE" *) reg [4:0] meta_n, sync_n;
 always @(posedge clk or posedge reset)
  if(reset) begin meta_n<=5'b11111;sync_n<=5'b11111;end
  else begin meta_n<=keys_n;sync_n<=meta_n;end
 // STATUS bits0..20 retain their ABI, including extended-arena bit20.
 assign data = address==16'h0008 ? core_data | 32'h00200000 | {~sync_n,27'b0} : core_data;
endmodule
