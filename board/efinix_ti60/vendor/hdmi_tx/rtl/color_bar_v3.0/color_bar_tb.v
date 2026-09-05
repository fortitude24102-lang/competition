`timescale  1ns /1ps
module color_bar_tb;

parameter	HACT		= 12'd1200;
parameter	VACT		= 12'd1920;
parameter	HST				= 8'd8;
parameter	HBP				= 8'd46;
parameter	HFP				= 8'd44;
parameter	VST				= 8'd8;
parameter	VBP				= 8'd32;
parameter	VFP				= 8'd177;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg clk_div2 = 'd0;
reg clk_div4 = 'd0;
reg clk_div8 = 'd0;
always #10 clk = ~clk;
always #20 clk_div2 = ~clk_div2;
always #40 clk_div4 = ~clk_div4;
always #80 clk_div8 = ~clk_div8;

initial
begin
        #0
            rst_n = 0;
        # 100

            rst_n = 1;
end 

wire [7:0] r_data;
wire [7:0] g_data;
wire [7:0] b_data;
wire rd_clk ;
reg [5:0]datatype = 6'h24; 
reg clk_sel = 2'd0;//2'd0 = div2;//2'd1 = div4;//2'd2 = div8
assign rd_clk = clk_sel == 2'd0 ? clk_div2 : (clk_sel == 2'd1 ? clk_div4:clk_div8);
always @( posedge clk )
begin
	case( datatype )
	6'h20: begin end 
	6'h21: begin end
	6'h22: begin end
	6'h23: begin end
	6'h24: begin clk_sel <= 2'd0; end 
	6'h28: begin end 
	6'h29: begin end 
	6'h2a: begin end 
	6'h2b: begin end 
	6'h2c: begin end 
	6'h2d: begin end 
	6'h18: begin end 
	6'h19: begin end 
	6'h1a: begin end 
	6'h1c: begin end 
	6'h1d: begin end 
	6'h1e: begin end 
	6'h1f: begin end 
	6'h12: begin end 
	6'h30: begin end 
	6'h13: begin end 
	default:;
	endcase
	
end 



	color_bar_rgb # (
    .DYN_EN(1'b0),
    .HS_POLORY(1'b1),
    .VS_POLORY(1'b1),
    .SYMBOL_WIDTH(8),
    .SYMBOL_NUM(3),
    .PAR_PIXEL_NUM(2),
    .HFP(HFP),
    .HST(HST),
    .HACT(HACT),
    .HBP(HBP),
    .VFP(VFP),
    .VST(VST),
    .VACT(VACT),
    .VBP(VBP),
    .TEST_MODE(2'b00)
  )
  color_bar_rgb_inst (
    .clk(clk),
    .rst_n(rst_n),
    .i_cfg_vid(i_cfg_vid),
    .h_cnt(h_cnt),
    .v_cnt(v_cnt),
    .hs(hs),
    .vs(vs),
    .de(de),
    .o_vid_data({r_data,g_data,b_data})
  );

	

 timing_detec u_timing_detec(
    /*i*/.clk			(clk ),
    /*i*/.rst_n			(),
    /*i*/.i_hs			(hs),
    /*i*/.i_vs			(vs),
    /*i*/.i_de			(de),
    /*i*/.i_vid			(),
    /*o*/.h_sync		(),
    /*o*/.h_back_porch	(),
    /*o*/.h_front_porch	(),
    /*o*/.h_active		(),
    /*o*/.v_active		(),
    /*o*/.v_sync		(),
    /*o*/.v_back_porch	(),
    /*o*/.v_front_porch ()
);


endmodule