//////////////////////////////////////////////////////////////////////////////////////
//Module Name : udp_tx
//Description : This module is used to send UDP data and generate UDP checksum
//
//////////////////////////////////////////////////////////////////////////////////////
`timescale 1 ns/1 ns
module udp_tx
       (
         input                    clk,
         input                    rst_n,
         
         input      [31:0]        source_ip_addr,
         input      [31:0]        destination_ip_addr,
         
         input      [15:0]        udp_send_source_port,
         input      [15:0]        udp_send_destination_port,
         input      [15:0]        udp_send_data_length,
         
         input      [7:0]         ram_wr_data,        //write data to udp tx ram
         input                    ram_wr_en,         //write en
         output reg               udp_ram_data_req,      //request data written to ram
         
         input                    udp_tx_req,
         input                    udp_data_req,
         output reg               udp_tx_ready,
         output reg [7:0]         udp_tx_data,
         output                   udp_tx_end
         
       ) ;
       
reg  [3:0]                header_checksum_cnt ;
reg                       checksum_finish ;
reg  [10:0]               ram_write_addr  ;
reg  [10:0]               ram_read_addr   ;
reg  [7:0]                ram_rdata_d0  ;
reg  [7:0]                ram_rdata_d1  ;
reg  [7:0]                ram_wr_data_d0 ;
reg  [7:0]                ram_wr_data_d1 ;

wire [7:0]                ram_rdata ;
reg  [5:0]                ram_data_length ;

reg  [15:0]               udp_send_cnt  ;
reg  [15:0]               udp_data_length ;      //valid data length
reg  [15:0]               udp_total_data_length ;//data length when transfer

reg [15:0]                timeout ;




parameter IDLE              = 7'b000_0001 ;
parameter HEADER_CHECKSUM   = 7'b000_0010 ;
parameter GEN_CHECKSUM      = 7'b000_0100 ;
parameter GEN_ODD_CHECKSUM  = 7'b000_1000 ;
parameter GEN_CHECKSUM_END  = 7'b001_0000 ;
parameter SEND_WAIT         = 7'b010_0000 ;
parameter UDP_SEND          = 7'b100_0000 ;


reg [6:0]    state  ;
reg [6:0]    next_state ;


always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      state  <=  IDLE  ;
    else
      state  <= next_state ;
  end
  
always @(*)
  begin
    case(state)
      IDLE            :
        begin
          if (udp_tx_req)
            next_state <= HEADER_CHECKSUM ;
          else
            next_state <= IDLE ;
        end
        
      HEADER_CHECKSUM :
        begin
          if (header_checksum_cnt == 16'd8)
            begin
              if (udp_data_length == 16'd9)
                next_state <= GEN_ODD_CHECKSUM ;
              else
                next_state <= GEN_CHECKSUM ;
            end
          else
            next_state <= HEADER_CHECKSUM ;
        end
      GEN_CHECKSUM    :
        begin
          if (udp_data_length[0] == 1'b0 && udp_send_cnt == udp_data_length - 9)
            next_state <= GEN_CHECKSUM_END ;
          else if (udp_data_length[0] == 1'b1 && udp_send_cnt == udp_data_length - 10)
            next_state <= GEN_ODD_CHECKSUM ;
          else
            next_state <= GEN_CHECKSUM ;
        end
      GEN_ODD_CHECKSUM:
        begin
          if (udp_send_cnt == udp_data_length - 9)
            next_state <= GEN_CHECKSUM_END ;
          else
            next_state <= GEN_ODD_CHECKSUM ;
        end
      GEN_CHECKSUM_END :
        begin
          if (checksum_finish)
            next_state <= SEND_WAIT ;
          else
            next_state <= GEN_CHECKSUM_END ;
        end
      SEND_WAIT      :
        begin
          if (udp_data_req)
            next_state <= UDP_SEND ;
          else if (timeout == 16'hffff)
            next_state <= IDLE ;
          else
            next_state <= SEND_WAIT ;
        end
        
      UDP_SEND       :
        begin
          if (udp_send_cnt == udp_total_data_length)
            next_state <= IDLE ;
          else
            next_state <= UDP_SEND ;
        end
      default        :
        next_state <= IDLE ;
    endcase
  end
  
  
  
  
  
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      udp_tx_ready <= 1'b0 ;
    else if (state == SEND_WAIT)
      udp_tx_ready <= 1'b1 ;
    else
      udp_tx_ready <= 1'b0 ;
  end
  
  
//timeout counter
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      ram_write_addr <= 11'd0 ;
    else if (ram_wr_en)
      ram_write_addr <= ram_write_addr + 1'b1 ;
    else
      ram_write_addr <= 11'd0 ;
  end
  
  
//timeout counter
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      timeout <= 16'd0 ;
    else if (state == SEND_WAIT)
      timeout <= timeout + 1'b1 ;
    else
      timeout <= 16'd0 ;
  end
  
  
  
dpram
  #(
    .WIDTH(8),
    .DEPTH(11)
  )
  udp_send_ram
  (
    .clock      (clk             ),
    .data       (ram_wr_data     ),
    .rdaddress  (ram_read_addr   ),
    .wraddress  (ram_write_addr  ),
    .wren       (ram_wr_en       ),
    .q          (ram_rdata     )
  );
  
  
always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      begin
        ram_wr_data_d0 <= 8'd0 ;
        ram_wr_data_d1 <= 8'd0 ;
      end
    else
      begin
        ram_wr_data_d0 <= ram_wr_data ;
        ram_wr_data_d1 <= ram_wr_data_d0 ;
      end
  end
//ram signal

always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      begin
        ram_rdata_d0 <= 8'd0 ;
        ram_rdata_d1 <= 8'd0 ;
      end
    else
      begin
        ram_rdata_d0 <= ram_rdata ;
        ram_rdata_d1 <= ram_rdata_d0 ;
      end
  end
  
  
  
always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      ram_read_addr <= 11'd0 ;
    else if (state == UDP_SEND && udp_send_cnt > 4)
      ram_read_addr <= udp_send_cnt[10:0] - 5 ;
    else
      ram_read_addr <= 11'd0 ;
  end
  
  
//checksum counter
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      udp_send_cnt  <= 16'd0 ;
    else if (state == GEN_CHECKSUM || state == GEN_ODD_CHECKSUM ||  state == UDP_SEND)
      udp_send_cnt <= udp_send_cnt + 1'b1 ;
    else
      udp_send_cnt <= 16'd0 ;
  end
  
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      header_checksum_cnt  <= 4'd0 ;
    else if (state == HEADER_CHECKSUM)
      header_checksum_cnt <= header_checksum_cnt + 1'b1 ;
    else
      header_checksum_cnt <= 4'd0 ;
  end
//generate udp and ip data length
always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      begin
        udp_total_data_length <= 16'd0 ;
        udp_data_length <= 16'd0 ;
      end
    else
      begin
        udp_data_length <= udp_send_data_length + 8;
        if (udp_send_data_length < 18)
          udp_total_data_length <= 26 ;
        else
          udp_total_data_length <= udp_send_data_length + 8 ;
      end
  end
  
always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      udp_ram_data_req <= 1'b0 ;
    else if (state == HEADER_CHECKSUM && header_checksum_cnt == 4'd5)
      udp_ram_data_req <= 1'b1 ;
    else
      udp_ram_data_req <= 1'b0 ;
  end
  
//*****************************************************************************************//
//generate udp checksum
//*****************************************************************************************//


//checksum function
function    [31:0]  checksum_adder
  (
    input       [31:0]  dataina,
    input       [31:0]  datainb
  );
  
  begin
    checksum_adder = dataina + datainb;
  end
endfunction

function    [31:0]  checksum_out
  (
    input       [31:0]  dataina
  );
  
  begin
    checksum_out = dataina[15:0]+dataina[31:16];
  end
  
endfunction

reg  [16:0] checksum_tmp0 ;
reg  [16:0] checksum_tmp1 ;
reg  [16:0] checksum_tmp2 ;
reg  [16:0] checksum_tmp3 ;
reg  [16:0] checksum_tmp4 ;
reg  [17:0] checksum_tmp5 ;
reg  [17:0] checksum_tmp6 ;
reg  [18:0] checksum_tmp7 ;
reg  [19:0] checksum_tmp8 ;

reg  [31:0] checksum_tmp9 ;

reg  [31:0] checksum_buf ;
reg  [31:0] check_out ;
reg  [31:0] checkout_buf ;
wire [15:0] checksum ;
reg  [2:0]  checksum_cnt ;


always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      begin
        checksum_tmp0 <= 17'd0 ;
        checksum_tmp1 <= 17'd0 ;
        checksum_tmp2 <= 17'd0 ;
        checksum_tmp3 <= 17'd0 ;
        checksum_tmp4 <= 17'd0 ;
        checksum_tmp5 <= 18'd0 ;
        checksum_tmp6 <= 18'd0 ;
        checksum_tmp7 <= 19'd0 ;
        checksum_tmp8 <= 20'd0 ;
      end
    else if (state == HEADER_CHECKSUM)
      begin
        checksum_tmp0 <= checksum_adder(source_ip_addr[31:16],source_ip_addr[15:0]);  //source ip address
        checksum_tmp1 <= checksum_adder(destination_ip_addr[31:16],destination_ip_addr[15:0]);     //destination ip address
        checksum_tmp2 <= checksum_adder({8'd0,8'd17},udp_data_length);                   //protocol type
        checksum_tmp3 <= checksum_adder(udp_send_source_port,udp_send_destination_port);           //udp data length
        checksum_tmp4 <= checksum_adder(udp_data_length, 16'd0);
        checksum_tmp5 <= checksum_adder(checksum_tmp0, checksum_tmp1);
        checksum_tmp6 <= checksum_adder(checksum_tmp2, checksum_tmp3);
        checksum_tmp7 <= checksum_adder(checksum_tmp5, checksum_tmp6);
        checksum_tmp8 <= checksum_adder(checksum_tmp4, checksum_tmp7);
      end
    else if (state == IDLE)
      begin
        checksum_tmp0 <= 17'd0 ;
        checksum_tmp1 <= 17'd0 ;
        checksum_tmp2 <= 17'd0 ;
        checksum_tmp3 <= 17'd0 ;
        checksum_tmp4 <= 17'd0 ;
        checksum_tmp5 <= 18'd0 ;
        checksum_tmp6 <= 18'd0 ;
        checksum_tmp7 <= 19'd0 ;
        checksum_tmp8 <= 20'd0 ;
      end
      
  end
  
always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      checksum_tmp9 <= 32'd0 ;
    else if (state == GEN_CHECKSUM)
      begin
        if(udp_send_cnt[0] == 1'b1)
          checksum_tmp9 <= checksum_adder({ram_wr_data_d1,ram_wr_data_d0},checksum_buf);
      end
    else if (state == GEN_ODD_CHECKSUM)
      checksum_tmp9 <= checksum_adder({ram_wr_data_d0,8'h00},checksum_tmp9);        //if udp data length is odd, fill with one byte 8'h00
    else if (state == IDLE)
      checksum_tmp9 <= 32'd0 ;
  end
  
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      checksum_buf <= 32'd0 ;
    else if (state == GEN_CHECKSUM)
      checksum_buf <= checksum_tmp9 ;
    else
      checksum_buf <= 32'd0 ;
  end
  
always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      checksum_cnt <= 3'd0 ;
    else if (state ==  GEN_CHECKSUM_END)
      checksum_cnt <= checksum_cnt + 1'b1 ;
    else
      checksum_cnt <= 3'd0 ;
  end
  
always @(posedge clk or negedge rst_n)
  begin
    if(rst_n == 1'b0)
      check_out <= 32'd0;
    else if (state ==  GEN_CHECKSUM_END)
      begin
        if(checksum_cnt == 3'd0)
          check_out <= checksum_adder(checksum_tmp9, checksum_tmp8);
        else if (checksum_cnt == 3'd1)
          check_out <= checksum_out(check_out) ;
        else if (checksum_cnt == 3'd2)
          check_out <= checksum_out(check_out) ;
      end
  end
  
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      checkout_buf <= 32'd0 ;
    else if (state == GEN_CHECKSUM_END)
      checkout_buf <= check_out ;
  end
  
assign checksum = ~checkout_buf[15:0] ;


always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      checksum_finish <= 1'b0 ;
    else if (state == GEN_CHECKSUM_END && checksum_cnt == 3'd4)
      checksum_finish <= 1'b1 ;
    else
      checksum_finish <= 1'b0 ;
  end
  
//*****************************************************************************************//
//send udp data
//*****************************************************************************************//
always @(posedge clk or negedge rst_n)
  begin
    if (~rst_n)
      udp_tx_data <= 8'h00  ;
    else if (state == UDP_SEND)
      begin
        case(udp_send_cnt)
          16'd0   :  udp_tx_data <= udp_send_source_port[15:8] ;
          16'd1   :  udp_tx_data <= udp_send_source_port[7:0] ;
          16'd2   :  udp_tx_data <= udp_send_destination_port[15:8] ;
          16'd3   :  udp_tx_data <= udp_send_destination_port[7:0] ;
          16'd4   :  udp_tx_data <= udp_data_length[15:8] ;
          16'd5   :  udp_tx_data <= udp_data_length[7:0] ;
          16'd6   :  udp_tx_data <= checksum[15:8] ;
          16'd7   :  udp_tx_data <= checksum[7:0]  ;
          default :
            begin
              if (udp_data_length < 26)
                begin
                  if (udp_send_cnt <= udp_data_length - 1)
                    udp_tx_data <= ram_rdata_d0 ;
                  else
                    udp_tx_data <= 8'h00 ;
                end
              else
                udp_tx_data <= ram_rdata_d0 ;
            end
        endcase
      end
    else
      udp_tx_data <= 8'h00 ;
  end
  
endmodule
