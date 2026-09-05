`timescale 1ns/1ps

module serdes_4b_10to1 (
	input          clk,           // clock input
	input          clkx5,         // 5x clock input
	input [9:0]    data_b,      // input data for serialisation
	input [9:0]    data_g,      // input data for serialisation
	input [9:0]    data_r,      // input data for serialisation
	input [9:0]    data_c,      // input data for serialisation
	output [2:0]	dataout_h,
	output [2:0]	dataout_l,
	output			clk_h,
	output			clk_l,

	output reg [2:0]data_p_h,
	output reg [2:0]data_p_l,
	output reg clk_p_h ,
	output reg clk_p_l ,
	output reg [2:0] data_n_h,
	output reg [2:0] data_n_l,
	output reg clk_n_h ,
	output reg clk_n_l 

  ) ;   
  
reg [2:0] TMDS_mod5 = 0;  // modulus 5 counter

reg [4:0] TMDS_shift_0h = 0, TMDS_shift_0l = 0;
reg [4:0] TMDS_shift_1h = 0, TMDS_shift_1l = 0;
reg [4:0] TMDS_shift_2h = 0, TMDS_shift_2l = 0;
reg [4:0] TMDS_shift_3h = 0, TMDS_shift_3l = 0;
reg [9:0] datain_0;
reg [9:0] datain_1;
reg [9:0] datain_2;
reg [9:0] datain_3;
always @( posedge clk )
begin
	datain_0 <= data_b;
	datain_1 <= data_g;
	datain_2 <= data_r;
	datain_3 <= data_c;
end

wire [4:0] TMDS_0_l = {datain_0[9],datain_0[7],datain_0[5],datain_0[3],datain_0[1]};
wire [4:0] TMDS_0_h = {datain_0[8],datain_0[6],datain_0[4],datain_0[2],datain_0[0]};

wire [4:0] TMDS_1_l = {datain_1[9],datain_1[7],datain_1[5],datain_1[3],datain_1[1]};
wire [4:0] TMDS_1_h = {datain_1[8],datain_1[6],datain_1[4],datain_1[2],datain_1[0]};

wire [4:0] TMDS_2_l = {datain_2[9],datain_2[7],datain_2[5],datain_2[3],datain_3[1]};
wire [4:0] TMDS_2_h = {datain_2[8],datain_2[6],datain_2[4],datain_2[2],datain_3[0]};

wire [4:0] TMDS_3_l = {datain_3[9],datain_3[7],datain_3[5],datain_3[3],datain_3[1]};
wire [4:0] TMDS_3_h = {datain_3[8],datain_3[6],datain_3[4],datain_3[2],datain_3[0]};

always @(posedge clkx5)
begin
	TMDS_shift_0h  <= TMDS_mod5[2] ? TMDS_0_h : TMDS_shift_0h[4:1];
	TMDS_shift_0l  <= TMDS_mod5[2] ? TMDS_0_l : TMDS_shift_0l[4:1];
	TMDS_shift_1h  <= TMDS_mod5[2] ? TMDS_1_h : TMDS_shift_1h[4:1];
	TMDS_shift_1l  <= TMDS_mod5[2] ? TMDS_1_l : TMDS_shift_1l[4:1];
	TMDS_shift_2h  <= TMDS_mod5[2] ? TMDS_2_h : TMDS_shift_2h[4:1];
	TMDS_shift_2l  <= TMDS_mod5[2] ? TMDS_2_l : TMDS_shift_2l[4:1];
	TMDS_shift_3h  <= TMDS_mod5[2] ? TMDS_3_h : TMDS_shift_3h[4:1];
	TMDS_shift_3l  <= TMDS_mod5[2] ? TMDS_3_l : TMDS_shift_3l[4:1];	
	TMDS_mod5 <= (TMDS_mod5[2]) ? 3'd0 : TMDS_mod5 + 3'd1;
end

assign dataout_h = {TMDS_shift_2h[0],TMDS_shift_1h[0],TMDS_shift_0h[0]};
assign dataout_l = {TMDS_shift_2l[0],TMDS_shift_1l[0],TMDS_shift_0l[0]};
assign clk_h = TMDS_shift_3h[0];
assign clk_l = TMDS_shift_3l[0];

always @( posedge clkx5 )
begin
		data_p_h <= dataout_h;
		data_p_l <= dataout_l;
		clk_p_h  <= clk_h;
		clk_p_l  <= clk_l;

		data_n_h <= ~dataout_h;
		data_n_l <= ~dataout_l;
		clk_n_h  <= ~clk_h;
		clk_n_l  <= ~clk_l;
end

// altddio_out	altddio_out_0(
// 			.datain_h ({TMDS_shift_3h[0],TMDS_shift_2h[0],TMDS_shift_1h[0],TMDS_shift_0h[0]}),
// 			.datain_l ({TMDS_shift_3l[0],TMDS_shift_2l[0],TMDS_shift_1l[0],TMDS_shift_0l[0]}),
// 			.outclock (clkx5),
// 			.dataout ({dataout_3_p,dataout_2_p,dataout_1_p,dataout_0_p}),
// 			.aclr (1'b0),
// 			.aset (1'b0),
// 			.oe (1'b1),
// 			.oe_out (),
// 			.outclocken (1'b1),
// 			.sclr (1'b0),
// 			.sset (1'b0));
// defparam
// 	altddio_out_0.extend_oe_disable = "OFF",
// 	altddio_out_0.invert_output = "OFF",
// 	altddio_out_0.lpm_hint = "UNUSED",
// 	altddio_out_0.lpm_type = "altddio_out",
// 	altddio_out_0.oe_reg = "UNREGISTERED",
// 	altddio_out_0.power_up_high = "OFF",
// 	altddio_out_0.width = 4;
	
	
// altddio_out	altddio_out_1(
// 			.datain_h ({~TMDS_shift_3h[0],~TMDS_shift_2h[0],~TMDS_shift_1h[0],~TMDS_shift_0h[0]}),
// 			.datain_l ({~TMDS_shift_3l[0],~TMDS_shift_2l[0],~TMDS_shift_1l[0],~TMDS_shift_0l[0]}),
// 			.outclock (clkx5),
// 			.dataout ({dataout_3_n,dataout_2_n,dataout_1_n,dataout_0_n}),
// 			.aclr (1'b0),
// 			.aset (1'b0),
// 			.oe (1'b1),
// 			.oe_out (),
// 			.outclocken (1'b1),
// 			.sclr (1'b0),
// 			.sset (1'b0));
// defparam
// 	altddio_out_1.extend_oe_disable = "OFF",
// 	altddio_out_1.invert_output = "OFF",
// 	altddio_out_1.lpm_hint = "UNUSED",
// 	altddio_out_1.lpm_type = "altddio_out",
// 	altddio_out_1.oe_reg = "UNREGISTERED",
// 	altddio_out_1.power_up_high = "OFF",
// 	altddio_out_1.width = 4;	



endmodule
