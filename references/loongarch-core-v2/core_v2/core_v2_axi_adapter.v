module core_v2_axi_adapter(
    input             clk,
    input             reset,
    input             instruction_request_valid,
    output            instruction_request_ready,
    input      [31:0] instruction_request_address,
    output            instruction_response_valid,
    input             instruction_response_ready,
    output     [31:0] instruction_response_data,
    output            instruction_response_error,
    input             data_request_valid,
    output            data_request_ready,
    input             data_request_write,
    input      [31:0] data_request_address,
    input      [3:0]  data_request_strobe,
    input      [31:0] data_request_data,
    output            data_response_valid,
    input             data_response_ready,
    output     [31:0] data_response_data,
    output            data_response_error,
    output     [3:0]  arid,
    output     [31:0] araddr,
    output     [7:0]  arlen,
    output     [2:0]  arsize,
    output     [1:0]  arburst,
    output     [1:0]  arlock,
    output     [3:0]  arcache,
    output     [2:0]  arprot,
    output            arvalid,
    input             arready,
    input      [3:0]  rid,
    input      [31:0] rdata,
    input      [1:0]  rresp,
    input             rlast,
    input             rvalid,
    output            rready,
    output     [3:0]  awid,
    output     [31:0] awaddr,
    output     [7:0]  awlen,
    output     [2:0]  awsize,
    output     [1:0]  awburst,
    output     [1:0]  awlock,
    output     [3:0]  awcache,
    output     [2:0]  awprot,
    output            awvalid,
    input             awready,
    output     [3:0]  wid,
    output     [31:0] wdata,
    output     [3:0]  wstrb,
    output            wlast,
    output            wvalid,
    input             wready,
    input      [3:0]  bid,
    input      [1:0]  bresp,
    input             bvalid,
    output            bready
);
    localparam OWNER_INSTRUCTION = 1'b0;
    localparam OWNER_DATA = 1'b1;

    reg [31:0] read_request_address_q [0:3];
    reg        read_request_owner_q [0:3];
    reg [1:0]  read_request_read_ptr_q;
    reg [1:0]  read_request_write_ptr_q;
    reg [2:0]  read_request_count_q;

    reg        read_owner_q [0:7];
    reg [2:0]  read_owner_read_ptr_q;
    reg [2:0]  read_owner_write_ptr_q;
    reg [3:0]  read_owner_count_q;

    reg [31:0] instruction_response_data_q [0:7];
    reg        instruction_response_error_q [0:7];
    reg [2:0]  instruction_response_read_ptr_q;
    reg [2:0]  instruction_response_write_ptr_q;
    reg [3:0]  instruction_response_count_q;
    reg        data_read_response_valid_q;
    reg [31:0] data_read_response_data_q;
    reg        data_read_response_error_q;

    reg        data_operation_busy_q;
    reg        write_active_q;
    reg        write_aw_pending_q;
    reg        write_w_pending_q;
    reg [31:0] write_address_q;
    reg [3:0]  write_strobe_q;
    reg [31:0] write_data_q;
    reg        write_response_valid_q;
    reg        write_response_error_q;

    wire read_request_space;
    wire data_read_select;
    wire instruction_request_accept;
    wire data_read_accept;
    wire data_write_accept;
    wire read_request_push;
    wire read_address_valid;
    wire read_address_ready;
    wire [31:0] read_address;
    wire read_address_buffer_valid;
    wire read_address_buffer_ready;
    wire read_address_owner;
    wire read_buffer_accept;
    wire read_address_accept;
    wire read_data_accept;
    wire read_owner_head;
    wire instruction_read_data_accept;
    wire data_read_data_accept;
    wire instruction_response_accept;
    wire data_read_response_accept;
    wire write_address_accept;
    wire write_data_accept;
    wire write_response_accept;
    wire data_response_accept;

    assign read_request_space = read_request_count_q < 3'd4;
    assign data_read_select = data_request_valid &&
                              !data_request_write &&
                              !data_operation_busy_q &&
                              read_request_space;
    assign instruction_request_ready = read_request_space &&
                                       !data_read_select;
    assign data_request_ready = !data_operation_busy_q &&
        (data_request_write ? !write_active_q : read_request_space);

    assign instruction_request_accept = instruction_request_valid &&
                                                instruction_request_ready;
    assign data_read_accept = data_request_valid && data_request_ready &&
                              !data_request_write;
    assign data_write_accept = data_request_valid && data_request_ready &&
                               data_request_write;
    assign read_request_push = instruction_request_accept ||
                               data_read_accept;

    assign arid = 4'b0;
    assign arlen = 8'b0;
    assign arsize = (araddr[31:20] == 12'h1f0) ? 3'b000 : 3'b010;
    assign arburst = 2'b01;
    assign arlock = 2'b0;
    assign arcache = 4'b0;
    assign arprot = 3'b0;
    assign read_address_valid = read_request_count_q != 3'b0;
    assign read_address = read_address_valid ?
        read_request_address_q[read_request_read_ptr_q] : 32'b0;
    assign read_buffer_accept = read_address_valid && read_address_ready;
    assign arvalid = read_address_buffer_valid &&
                     read_owner_count_q < 4'd8;
    assign read_address_buffer_ready = arready &&
                                       read_owner_count_q < 4'd8;
    assign read_address_accept = arvalid && arready;

    axi_ar_buffer_v2 u_ar_buffer (
        .clk(clk),
        .reset(reset),
        .input_valid(read_address_valid),
        .input_ready(read_address_ready),
        .input_address(read_address),
        .input_owner(read_request_owner_q[read_request_read_ptr_q]),
        .output_valid(read_address_buffer_valid),
        .output_ready(read_address_buffer_ready),
        .output_address(araddr),
        .output_owner(read_address_owner)
    );

    assign read_owner_head = read_owner_q[read_owner_read_ptr_q];
    assign rready = read_owner_count_q != 4'b0 &&
        ((read_owner_head == OWNER_INSTRUCTION &&
          instruction_response_count_q < 4'd8) ||
         (read_owner_head == OWNER_DATA &&
          !data_read_response_valid_q));
    assign read_data_accept = rvalid && rready;
    assign instruction_read_data_accept = read_data_accept &&
        read_owner_head == OWNER_INSTRUCTION;
    assign data_read_data_accept = read_data_accept &&
        read_owner_head == OWNER_DATA;

    assign instruction_response_valid =
        instruction_response_count_q != 4'b0;
    assign instruction_response_data = instruction_response_valid ?
        instruction_response_data_q[instruction_response_read_ptr_q] :
        32'b0;
    assign instruction_response_error = instruction_response_valid &&
        instruction_response_error_q[instruction_response_read_ptr_q];
    assign instruction_response_accept = instruction_response_valid &&
                                         instruction_response_ready;

    assign data_response_valid = write_response_valid_q ||
                                 data_read_response_valid_q;
    assign data_response_data = write_response_valid_q ? 32'b0 :
        (data_read_response_valid_q ? data_read_response_data_q : 32'b0);
    assign data_response_error = write_response_valid_q ?
        write_response_error_q : data_read_response_error_q;
    assign data_read_response_accept = !write_response_valid_q &&
        data_read_response_valid_q && data_response_ready;
    assign data_response_accept = data_response_valid && data_response_ready;

    assign awid = 4'b0;
    assign awaddr = awvalid ? write_address_q : 32'b0;
    assign awlen = 8'b0;
    assign awsize = 3'b010;
    assign awburst = 2'b01;
    assign awlock = 2'b0;
    assign awcache = 4'b0;
    assign awprot = 3'b0;
    assign awvalid = write_active_q && write_aw_pending_q;
    assign write_address_accept = awvalid && awready;

    assign wid = 4'b0;
    assign wdata = wvalid ? write_data_q : 32'b0;
    assign wstrb = wvalid ? write_strobe_q : 4'b0;
    assign wlast = 1'b1;
    assign wvalid = write_active_q && write_w_pending_q;
    assign write_data_accept = wvalid && wready;

    assign bready = write_active_q && !write_aw_pending_q &&
                    !write_w_pending_q && !write_response_valid_q;
    assign write_response_accept = bvalid && bready;

    always @(posedge clk) begin
        if (reset) begin
            read_request_read_ptr_q <= 2'b0;
            read_request_write_ptr_q <= 2'b0;
            read_request_count_q <= 3'b0;
        end else begin
            if (read_request_push) begin
                read_request_address_q[read_request_write_ptr_q] <=
                    data_read_accept ? data_request_address :
                                       instruction_request_address;
                read_request_owner_q[read_request_write_ptr_q] <=
                    data_read_accept ? OWNER_DATA : OWNER_INSTRUCTION;
                read_request_write_ptr_q <=
                    read_request_write_ptr_q + 2'd1;
            end
            if (read_buffer_accept)
                read_request_read_ptr_q <=
                    read_request_read_ptr_q + 2'd1;
            case ({read_request_push, read_buffer_accept})
                2'b10: read_request_count_q <= read_request_count_q + 3'd1;
                2'b01: read_request_count_q <= read_request_count_q - 3'd1;
                default: read_request_count_q <= read_request_count_q;
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            read_owner_read_ptr_q <= 3'b0;
            read_owner_write_ptr_q <= 3'b0;
            read_owner_count_q <= 4'b0;
        end else begin
            if (read_address_accept) begin
                read_owner_q[read_owner_write_ptr_q] <=
                    read_address_owner;
                read_owner_write_ptr_q <= read_owner_write_ptr_q + 3'd1;
            end
            if (read_data_accept)
                read_owner_read_ptr_q <= read_owner_read_ptr_q + 3'd1;
            case ({read_address_accept, read_data_accept})
                2'b10: read_owner_count_q <= read_owner_count_q + 4'd1;
                2'b01: read_owner_count_q <= read_owner_count_q - 4'd1;
                default: read_owner_count_q <= read_owner_count_q;
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            instruction_response_read_ptr_q <= 3'b0;
            instruction_response_write_ptr_q <= 3'b0;
            instruction_response_count_q <= 4'b0;
            data_read_response_valid_q <= 1'b0;
            data_read_response_data_q <= 32'b0;
            data_read_response_error_q <= 1'b0;
        end else begin
            if (instruction_read_data_accept) begin
                instruction_response_data_q[
                    instruction_response_write_ptr_q] <= rdata;
                instruction_response_error_q[
                    instruction_response_write_ptr_q] <=
                    rresp != 2'b00 || !rlast || rid != 4'b0;
                instruction_response_write_ptr_q <=
                    instruction_response_write_ptr_q + 3'd1;
            end
            if (instruction_response_accept)
                instruction_response_read_ptr_q <=
                    instruction_response_read_ptr_q + 3'd1;
            case ({instruction_read_data_accept,
                   instruction_response_accept})
                2'b10: instruction_response_count_q <=
                    instruction_response_count_q + 4'd1;
                2'b01: instruction_response_count_q <=
                    instruction_response_count_q - 4'd1;
                default: instruction_response_count_q <=
                    instruction_response_count_q;
            endcase

            if (data_read_data_accept) begin
                data_read_response_valid_q <= 1'b1;
                data_read_response_data_q <= rdata;
                data_read_response_error_q <=
                    rresp != 2'b00 || !rlast || rid != 4'b0;
            end else if (data_read_response_accept) begin
                data_read_response_valid_q <= 1'b0;
                data_read_response_error_q <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            data_operation_busy_q <= 1'b0;
            write_active_q <= 1'b0;
            write_aw_pending_q <= 1'b0;
            write_w_pending_q <= 1'b0;
            write_address_q <= 32'b0;
            write_strobe_q <= 4'b0;
            write_data_q <= 32'b0;
            write_response_valid_q <= 1'b0;
            write_response_error_q <= 1'b0;
        end else begin
            if (data_read_accept || data_write_accept)
                data_operation_busy_q <= 1'b1;
            else if (data_response_accept)
                data_operation_busy_q <= 1'b0;

            if (data_write_accept) begin
                write_active_q <= 1'b1;
                write_aw_pending_q <= 1'b1;
                write_w_pending_q <= 1'b1;
                write_address_q <= data_request_address;
                write_strobe_q <= data_request_strobe;
                write_data_q <= data_request_data;
            end
            if (write_address_accept)
                write_aw_pending_q <= 1'b0;
            if (write_data_accept)
                write_w_pending_q <= 1'b0;
            if (write_response_accept) begin
                write_active_q <= 1'b0;
                write_response_valid_q <= 1'b1;
                write_response_error_q <=
                    bresp != 2'b00 || bid != 4'b0;
            end else if (write_response_valid_q && data_response_ready) begin
                write_response_valid_q <= 1'b0;
                write_response_error_q <= 1'b0;
            end
        end
    end
endmodule
