module lsu_request_v2(
    input             clk,
    input             reset,
    input             request_valid,
    output            request_ready,
    input             request_write,
    input      [31:0] request_address,
    input      [1:0]  request_width,
    input             request_signed,
    input      [31:0] request_write_data,
    output            bus_request_valid,
    input             bus_request_ready,
    output            bus_request_write,
    output     [31:0] bus_request_address,
    output     [3:0]  bus_request_strobe,
    output     [31:0] bus_request_data,
    input             bus_response_valid,
    output            bus_response_ready,
    input      [31:0] bus_response_data,
    input             bus_response_error,
    output            completion_valid,
    input             completion_ready,
    output     [31:0] completion_data,
    output            completion_misaligned,
    output            completion_bus_error
);
    localparam STATE_IDLE = 2'd0;
    localparam STATE_REQUEST = 2'd1;
    localparam STATE_RESPONSE = 2'd2;
    localparam STATE_COMPLETE = 2'd3;

    reg [1:0] state_q;
    reg       write_q;
    reg [31:0] address_q;
    reg [1:0] width_q;
    reg       signed_q;
    reg [3:0] write_strobe_q;
    reg [31:0] write_data_q;
    reg [31:0] completion_data_q;
    reg        completion_misaligned_q;
    reg        completion_bus_error_q;

    wire request_aligned;
    wire [3:0] request_strobe;
    wire [31:0] request_bus_data;
    wire [31:0] unused_request_load_data;
    wire unused_response_aligned;
    wire [3:0] unused_response_strobe;
    wire [31:0] unused_response_write_data;
    wire [31:0] formatted_response_data;

    lsu_format_v2 u_request_format (
        .address_low(request_address[1:0]),
        .width(request_width),
        .load_signed(request_signed),
        .store_data(request_write_data),
        .read_data(32'b0),
        .aligned(request_aligned),
        .write_strobe(request_strobe),
        .write_data(request_bus_data),
        .load_data(unused_request_load_data)
    );

    lsu_format_v2 u_response_format (
        .address_low(address_q[1:0]),
        .width(width_q),
        .load_signed(signed_q),
        .store_data(32'b0),
        .read_data(bus_response_data),
        .aligned(unused_response_aligned),
        .write_strobe(unused_response_strobe),
        .write_data(unused_response_write_data),
        .load_data(formatted_response_data)
    );

    assign request_ready = (state_q == STATE_IDLE);
    assign bus_request_valid = (state_q == STATE_REQUEST);
    assign bus_request_write = write_q;
    assign bus_request_address = address_q;
    assign bus_request_strobe = write_strobe_q;
    assign bus_request_data = write_data_q;
    assign bus_response_ready = (state_q == STATE_RESPONSE);
    assign completion_valid = (state_q == STATE_COMPLETE);
    assign completion_data = completion_data_q;
    assign completion_misaligned = completion_misaligned_q;
    assign completion_bus_error = completion_bus_error_q;

    always @(posedge clk) begin
        if (reset) begin
            state_q <= STATE_IDLE;
            write_q <= 1'b0;
            address_q <= 32'b0;
            width_q <= 2'b0;
            signed_q <= 1'b0;
            write_strobe_q <= 4'b0;
            write_data_q <= 32'b0;
            completion_data_q <= 32'b0;
            completion_misaligned_q <= 1'b0;
            completion_bus_error_q <= 1'b0;
        end else begin
            case (state_q)
                STATE_IDLE: begin
                    if (request_valid) begin
                        write_q <= request_write;
                        address_q <= request_address;
                        width_q <= request_width;
                        signed_q <= request_signed;
                        write_strobe_q <= request_strobe;
                        write_data_q <= request_bus_data;
                        completion_data_q <= 32'b0;
                        completion_misaligned_q <= !request_aligned;
                        completion_bus_error_q <= 1'b0;
                        state_q <= request_aligned ? STATE_REQUEST : STATE_COMPLETE;
                    end
                end
                STATE_REQUEST: begin
                    if (bus_request_ready)
                        state_q <= STATE_RESPONSE;
                end
                STATE_RESPONSE: begin
                    if (bus_response_valid) begin
                        completion_data_q <= write_q ? 32'b0 : formatted_response_data;
                        completion_bus_error_q <= bus_response_error;
                        state_q <= STATE_COMPLETE;
                    end
                end
                default: begin
                    if (completion_ready)
                        state_q <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
