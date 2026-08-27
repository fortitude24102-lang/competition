module frontend_single_v2 #(
    parameter [31:0] RESET_PC = 32'h1c000000
)(
    input         clk,
    input         reset,
    input         redirect_valid,
    input  [31:0] redirect_target,
    output        output_valid,
    input         output_ready,
    output [31:0] output_pc,
    output [31:0] output_instruction,
    output        output_error,
    output        instruction_request_valid,
    input         instruction_request_ready,
    output [31:0] instruction_request_address,
    input         instruction_response_valid,
    output        instruction_response_ready,
    input  [31:0] instruction_response_data,
    input         instruction_response_error
);
    reg [31:0] pc_q;
    reg [31:0] request_pc_q [0:3];
    reg [1:0] request_read_ptr_q;
    reg [1:0] request_write_ptr_q;
    reg [2:0] request_count_q;
    reg [31:0] output_pc_q [0:3];
    reg [31:0] output_instruction_q [0:3];
    reg output_error_q [0:3];
    reg [1:0] output_read_ptr_q;
    reg [1:0] output_write_ptr_q;
    reg [2:0] output_count_q;
    reg [2:0] stale_response_count_q;
    reg response_hold_valid_q;
    reg [31:0] response_hold_pc_q;
    reg [31:0] response_hold_instruction_q;
    reg response_hold_error_q;
    wire request_accept;
    wire response_accept;
    wire response_is_stale;
    wire response_enqueue;
    wire response_direct_enqueue;
    wire response_hold_capture;
    wire response_hold_enqueue;
    wire [31:0] response_enqueue_pc;
    wire [31:0] response_enqueue_instruction;
    wire response_enqueue_error;
    wire output_accept;
    wire output_has_space;

    assign output_valid = output_count_q != 3'd0 && !redirect_valid;
    assign output_pc = output_pc_q[output_read_ptr_q];
    assign output_instruction =
        output_instruction_q[output_read_ptr_q];
    assign output_error = output_error_q[output_read_ptr_q];
    assign output_accept = output_valid && output_ready;
    assign output_has_space = output_count_q < 3'd4;

    assign response_is_stale = stale_response_count_q != 3'd0;
    assign instruction_response_ready = request_count_q != 3'd0 &&
        (response_is_stale || !response_hold_valid_q || output_has_space);
    assign response_accept = instruction_response_valid &&
                             instruction_response_ready;
    assign response_direct_enqueue = response_accept &&
        !response_is_stale && !response_hold_valid_q && output_has_space;
    assign response_hold_capture = response_accept &&
        !response_is_stale && (response_hold_valid_q || !output_has_space);
    assign response_hold_enqueue = response_hold_valid_q &&
                                   output_has_space;
    assign response_enqueue = response_direct_enqueue ||
                              response_hold_enqueue;
    assign response_enqueue_pc = response_hold_enqueue
        ? response_hold_pc_q : request_pc_q[request_read_ptr_q];
    assign response_enqueue_instruction = response_hold_enqueue
        ? response_hold_instruction_q : instruction_response_data;
    assign response_enqueue_error = response_hold_enqueue
        ? response_hold_error_q : instruction_response_error;

    assign instruction_request_valid = !reset &&
        (request_count_q < 3'd4 || response_accept);
    assign instruction_request_address = pc_q;
    assign request_accept = instruction_request_valid &&
                            instruction_request_ready;

    always @(posedge clk) begin
        if (reset) begin
            pc_q <= RESET_PC;
            request_read_ptr_q <= 2'b0;
            request_write_ptr_q <= 2'b0;
            request_count_q <= 3'b0;
            output_read_ptr_q <= 2'b0;
            output_write_ptr_q <= 2'b0;
            output_count_q <= 3'b0;
            stale_response_count_q <= 3'b0;
            response_hold_valid_q <= 1'b0;
        end else begin
            if (response_enqueue) begin
                output_pc_q[output_write_ptr_q] <=
                    response_enqueue_pc;
                output_instruction_q[output_write_ptr_q] <=
                    response_enqueue_instruction;
                output_error_q[output_write_ptr_q] <=
                    response_enqueue_error;
            end
            if (response_hold_capture) begin
                response_hold_pc_q <= request_pc_q[request_read_ptr_q];
                response_hold_instruction_q <= instruction_response_data;
                response_hold_error_q <= instruction_response_error;
            end
            if (redirect_valid) begin
                pc_q <= redirect_target;
                output_read_ptr_q <= 2'b0;
                output_write_ptr_q <= 2'b0;
                output_count_q <= 3'b0;
                stale_response_count_q <= request_count_q +
                                          {2'b0, request_accept} -
                                          {2'b0, response_accept};
                response_hold_valid_q <= 1'b0;
            end else begin
                if (response_hold_capture) begin
                    response_hold_valid_q <= 1'b1;
                end else if (response_hold_enqueue) begin
                    response_hold_valid_q <= 1'b0;
                end
                if (request_accept)
                    pc_q <= pc_q + 32'd4;

                if (response_enqueue)
                    output_write_ptr_q <= output_write_ptr_q + 2'd1;
                if (output_accept)
                    output_read_ptr_q <= output_read_ptr_q + 2'd1;
                case ({response_enqueue, output_accept})
                    2'b10: output_count_q <= output_count_q + 3'd1;
                    2'b01: output_count_q <= output_count_q - 3'd1;
                    default: output_count_q <= output_count_q;
                endcase
                if (response_accept && response_is_stale)
                    stale_response_count_q <=
                        stale_response_count_q - 3'd1;
            end

            if (request_accept) begin
                request_pc_q[request_write_ptr_q] <= pc_q;
                request_write_ptr_q <= request_write_ptr_q + 2'd1;
            end
            if (response_accept)
                request_read_ptr_q <= request_read_ptr_q + 2'd1;
            case ({request_accept, response_accept})
                2'b10: request_count_q <= request_count_q + 3'd1;
                2'b01: request_count_q <= request_count_q - 3'd1;
                default: request_count_q <= request_count_q;
            endcase
        end
    end
endmodule
