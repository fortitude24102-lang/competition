//=================================================================
//
//  Copyright (C) 2022 Persion All rights reserved.
//  文件名称：top.v
//  创 建 者：Ramsey Wang
//  创建日期：2022.04.01
//  描    述：led test
//
//=================================================================


module top
(


    ////////////////////////    CLOCK & PLL     ////////////////////////
	input hdmi_tx_locked,
    input hdmi_tx_slow_clk,


    output [9:0]tmds_data0_o ,
    output [9:0]tmds_data1_o ,
    output [9:0]tmds_data2_o ,
    output [9:0]tmds_clk_o   ,

    output tmds_data0_TX_OE,
    output tmds_data1_TX_OE,
    output tmds_data2_TX_OE,
    output tmds_clk_TX_OE,
	output tmds_data0_TX_RST,
	output tmds_data1_TX_RST,
	output tmds_data2_TX_RST,
	output tmds_clk_TX_RST

);

//=====================================================================================
//localpram
//=====================================================================================
	parameter	MAX_HRES		= 12'd1920;
	parameter	MAX_VRES		= 12'd1536;
	parameter	HSP				= 8'd2;
	parameter	HBP				= 8'd88;
	parameter	HFP				= 8'd120;
	parameter	VSP				= 8'd2;
	parameter	VBP				= 8'd20;
	parameter	VFP				= 8'd20;


  
//=====================================================================================
//hdmi demo
//=====================================================================================
wire                            video_hs;
wire                            video_vs;
wire                            video_de;
wire[7:0]                       video_r;
wire[7:0]                       video_g;
wire[7:0]                       video_b;
wire   							sys_rst_n;
//=====================================================================================
//rest-n
//=====================================================================================

 reset
	#(
		.IN_RST_ACTIVE	("LOW"),
		.OUT_RST_ACTIVE	("LOW"),
		.CYCLE			(3)
	)
	inst_rx_byteclk_rst
	(
		.i_arst	(hdmi_tx_locked),
		.i_clk	(hdmi_tx_slow_clk),
		.o_srst	(sys_rst_n)
	);

//=====================================================================================
//hdmi demo
//=====================================================================================
wire [9:0] tmds_data0;
wire [9:0] tmds_data1;
wire [9:0] tmds_data2;
wire [9:0] tmds_clk ;


assign tmds_data0_TX_OE = 1'b1;
assign tmds_data1_TX_OE = 1'b1;
assign tmds_data2_TX_OE = 1'b1;
assign tmds_clk_TX_OE   = 1'b1;

assign tmds_data0_TX_RST = 1'b0;
assign tmds_data1_TX_RST = 1'b0;
assign tmds_data2_TX_RST = 1'b0;
assign tmds_clk_TX_RST   = 1'b0;


color_bar_rgb #(
	.HS_POLORY 		(1'b1		),
	.VS_POLORY 		(1'b1		),
	.SYMBOL_WIDTH(8),
    .SYMBOL_NUM(3),
    .PAR_PIXEL_NUM(1),
	.HFP 	(HFP		),
	.HST 		(HSP		),
	.HACT 		(MAX_HRES	),
	.HBP 	(HBP		),
	.VFP 	(VFP		),
	.VST 		(VSP		),
	.VACT 		(MAX_VRES	),
	.VBP 	(VBP		),
	.TEST_MODE 		(2'd2		)
	)u_color_bar_rgb(
	/*i*/.clk	(hdmi_tx_slow_clk),
	/*i*/.rst_n	(sys_rst_n ),
	/*o*/.hs	(video_hs),
	/*o*/.vs	(video_vs),
	/*o*/.de	(video_de),
	/*o*/.o_vid_data	({video_r,video_g,video_b})    //像素数据、红色分量
	
	);


dvi_encoder dvi_encoder_m0
(
	.pixelclk      (hdmi_tx_slow_clk        ),// system clock
	.rstin         (~sys_rst_n         ),// reset
	//hdmi tx
	.blue_din      (video_b	),    //(video_b            ),//   
	.green_din     (video_g	),    //(video_g            ),//   
	.red_din       (video_r	),    //(video_r            ),//   
	.hsync         (video_hs),    //(video_hs           ),//   
	.vsync         (video_vs),    //(video_vs           ),//   
	.de            (video_de),      //(video_de           ),// 
	
    .tmds_data0    (tmds_data0),
    .tmds_data1    (tmds_data1),
    .tmds_data2    (tmds_data2),
    .tmds_clk      (tmds_clk  )
);
   
assign tmds_clk_o = ~tmds_clk;
assign tmds_data0_o = ~tmds_data0;
assign tmds_data1_o = ~tmds_data1;
assign tmds_data2_o = ~tmds_data2;


  
 
endmodule
