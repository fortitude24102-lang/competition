//rev 3.0 
//suport parallel pixel 
	module color_bar_rgb #(
			parameter DYN_EN = 1'b0,
			parameter HS_POLORY =1'b1,
			parameter VS_POLORY = 1'b1,
			parameter SYMBOL_WIDTH = 'd10,
			parameter SYMBOL_NUM	= 'd3,
			parameter PAR_PIXEL_NUM = 'd1,
			parameter HFP 	= 13'd100,
			parameter HST 			= 13'd100,
			parameter HACT 			= 13'd384,
			parameter HBP 			= 13'd100,
			parameter VFP 			= 13'd4,
			parameter VST 			= 13'd5,
			parameter VACT 			= 13'd288,
			parameter VBP 			= 13'd4,
			parameter TEST_MODE 	= 2'd0
	)(
	input		wire			clk,
	input 		wire 			rst_n,
	//`ifdef TEST_MODE == 2'b11
	input  wire [PAR_PIXEL_NUM*SYMBOL_NUM*SYMBOL_WIDTH-1:0]           i_cfg_vid,
	//`endif
	output 	reg	[15:0] h_cnt = 0,
	output  reg	[15:0] v_cnt = 0,
	output	reg					hs = 0,
	output	reg					vs  = 0,
	output	reg					de = 1'b0,
	output	reg [PAR_PIXEL_NUM*SYMBOL_NUM*SYMBOL_WIDTH-1:0] 			o_vid_data = 'd0  
	
	);


//=========================================================
//
//=========================================================
	localparam WHITE_R 		= 8'hff;
	localparam WHITE_G 		= 8'hff;
	localparam WHITE_B 		= 8'hff;
	localparam YELLOW_R 	= 8'hff;
	localparam YELLOW_G 	= 8'hff;
	localparam YELLOW_B 	= 8'h00;                              	
	localparam CYAN_R 		= 8'h00;
	localparam CYAN_G 		= 8'hff;
	localparam CYAN_B 		= 8'hff;                             	
	localparam GREEN_R 		= 8'h00;
	localparam GREEN_G 		= 8'hff;
	localparam GREEN_B 		= 8'h00;
	localparam MAGENTA_R 	= 8'hff;
	localparam MAGENTA_G 	= 8'h00;
	localparam MAGENTA_B 	= 8'hff;
	localparam RED_R 		= 8'hff;
	localparam RED_G 		= 8'h00;
	localparam RED_B 		= 8'h00;
	localparam BLUE_R 		= 8'h00;
	localparam BLUE_G 		= 8'h00;
	localparam BLUE_B 		= 8'hff;
	localparam BLACK_R 		= 8'h00;
	localparam BLACK_G 		= 8'h00;
	localparam BLACK_B 		= 8'h00;
	
	
	localparam S_HBP 	= 2'd0;
	localparam S_HST 	= 2'd1;
	localparam S_HACT 	= 2'd2;
	localparam S_HFP 	= 2'd3;
	localparam S_VBP 	= 2'd0;
	localparam S_VST 	= 2'd1;
	localparam S_VACT 	= 2'd2;
	localparam S_VFP 	= 2'd3;

	localparam HFP_CNT = HFP/PAR_PIXEL_NUM;
	localparam HBP_CNT = HBP/PAR_PIXEL_NUM;
	localparam HACT_CNT = HACT/PAR_PIXEL_NUM;
	localparam HST_CNT = HST/PAR_PIXEL_NUM;
	
	reg	[1:0] 	h_state = S_HST;
	reg	[1:0] 	v_state = S_VST;
	reg	hs_r1 = 1'b0;
	reg vs_r1 = 1'b0;
	reg	de_r1 = 1'b0;

	always @( posedge clk or negedge rst_n )
	begin
		if( ~rst_n ) begin 
			h_state <= S_HST;
			h_cnt <= 0;
		end else begin 
			case(h_state )
			S_HST : begin
					if( h_cnt == HST_CNT - 1) begin
							h_cnt <= 0;
							h_state <= S_HBP;
					end else 
							h_cnt <= h_cnt + 1'b1;
			end
			S_HBP : begin

					if( h_cnt == HBP_CNT - 1) begin
							h_cnt <= 0;
							h_state <= S_HACT;
					end else 
							h_cnt <= h_cnt + 1'b1;
			end

			S_HACT : begin
					if( h_cnt == HACT_CNT - 1) begin
							h_cnt <= 0;
							h_state <= S_HFP;
					end else 
							h_cnt <= h_cnt + 1'b1;
			end
			S_HFP : begin
					if( h_cnt == HFP_CNT - 1) begin
							h_cnt <= 0;
							h_state <= S_HST;
					end else 
							h_cnt <= h_cnt + 1'b1;
			end
			default: begin
					h_state <= S_HST;
					h_cnt <= 0;
			end
			endcase
		end 
	end
	
	always @( posedge clk or negedge rst_n  )
	begin
		if( ~rst_n ) begin 
			v_state <= S_VST;
			v_cnt <= 0;
		end else begin 
			case(v_state )

			S_VST : begin
					if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
						if( v_cnt == VST - 1 ) begin 
							v_cnt <= 0;
							v_state <= S_VBP;
						end else 
							v_cnt <= v_cnt + 1'b1;
					end
			end
			S_VBP : begin
					if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
						if( v_cnt == VBP - 1 ) begin 
							v_cnt <= 0;
							v_state <= S_VACT;
						end else 
							v_cnt <= v_cnt + 1'b1;
					end
			end
			S_VACT : begin
					if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
						if( v_cnt == VACT - 1 ) begin 
							v_cnt <= 0;
							v_state <= S_VFP;
						end else 
							v_cnt <= v_cnt + 1'b1;
					end
			end
			S_VFP : begin
					if( h_cnt == HFP_CNT - 1 && h_state == S_HFP ) begin
						if( v_cnt == VFP - 1 ) begin 
							v_cnt <= 0;
							v_state <= S_VST;
						end else 
							v_cnt <= v_cnt + 1'b1;
					end
			end
			default: begin
					v_state <= S_VST;
					v_cnt <= 0;
			end
			endcase
		end 
	end

	generate
	    if(TEST_MODE  == 2'b00 ) begin : V_MIRROR_P//===========================================================
	    	always@(posedge clk or negedge  rst_n)
			begin
				if(~rst_n)
					o_vid_data <= 'd0;
				else if( h_state == S_HACT && v_state == S_VACT )
					o_vid_data <= o_vid_data + 1'b1; 
				else
					o_vid_data <= 'd0;
			end
		end else if( TEST_MODE == 2'b01 )begin : Clor //===============================================================
			wire pos_vs;
			assign pos_vs = {vs,vs_r1} == 2'b01 ;
			reg [5:0] frame_cnt = 6'd0;
			reg [SYMBOL_NUM*PAR_PIXEL_NUM*SYMBOL_WIDTH-1:0] o_vid_data_buf = 'd0;
			reg [2:0] color_state = 2'b00;
			always @( posedge clk or negedge rst_n )
			begin 
				if( ~rst_n )
					frame_cnt <= 0;
				else if( pos_vs )
					frame_cnt <= frame_cnt + 1'b1;
			end
			//EBU检测图从左至右依次为 白色、黄色、靛色、绿色 紫色、红色、蓝色、黑色
			always @( posedge clk )
			begin 
				case( color_state )
				3'b000 :  begin 

					o_vid_data_buf <= {{PAR_PIXEL_NUM}{WHITE_R,WHITE_G,WHITE_B}};
					if( &frame_cnt & pos_vs )
						color_state <= 3'b001;
				end 

				3'b001 :  begin 
						o_vid_data_buf <= {{PAR_PIXEL_NUM}{YELLOW_R,YELLOW_G,YELLOW_B}};
						if( &frame_cnt & pos_vs )
							color_state <= 3'b010;
				end

				3'b010 :  begin 
						o_vid_data_buf <= {{PAR_PIXEL_NUM}{CYAN_R,CYAN_G,CYAN_B}};
					if( &frame_cnt & pos_vs )
							color_state <= 3'b011;
				end

				3'b011 :  begin 
						o_vid_data_buf <= {{PAR_PIXEL_NUM}{GREEN_R,GREEN_G,GREEN_B}};


						if( &frame_cnt & pos_vs )
							color_state <= 3'b100;
				 end
				 3'b100 : begin 
						o_vid_data_buf <= {{PAR_PIXEL_NUM}{MAGENTA_R,MAGENTA_G,MAGENTA_B}};
						if( &frame_cnt & pos_vs )
							color_state <= 3'b101;
				 end 
				 3'b101: begin 
						o_vid_data_buf <= {{PAR_PIXEL_NUM}{RED_R,RED_G,RED_B}};  


						if( &frame_cnt & pos_vs )
							color_state <= 3'b110;
				 end
				 3'b110: begin 
						o_vid_data_buf <= {{PAR_PIXEL_NUM}{BLUE_R,BLUE_G,BLUE_B}};
						if( &frame_cnt & pos_vs )
							color_state <= 3'b111;
				 end
				 3'b111:begin 
						if( h_cnt <HACT_CNT/8) 
							o_vid_data_buf <=  {{PAR_PIXEL_NUM}{WHITE_R,WHITE_G,WHITE_B}};
						else if( h_cnt <HACT_CNT/8*2)
							o_vid_data_buf <= {{PAR_PIXEL_NUM}{YELLOW_R,YELLOW_G,YELLOW_B}};
						else if( h_cnt <HACT_CNT/8*3)
							o_vid_data_buf <= {{PAR_PIXEL_NUM}{CYAN_R,CYAN_G,CYAN_B}};
						else if(h_cnt <HACT_CNT/8*4)
							o_vid_data_buf <= {{PAR_PIXEL_NUM}{GREEN_R,GREEN_G,GREEN_B}};
						else if(h_cnt <HACT_CNT/8*5)
							o_vid_data_buf <= {{PAR_PIXEL_NUM}{MAGENTA_R,MAGENTA_G,MAGENTA_B}};
						else if(h_cnt <HACT_CNT/8*6)
							o_vid_data_buf <= {{PAR_PIXEL_NUM}{RED_R,RED_G,RED_B}}; 
						else if(h_cnt <HACT_CNT/8*7)
							o_vid_data_buf <= {{PAR_PIXEL_NUM}{BLUE_R,BLUE_G,BLUE_B}};
						else 
							o_vid_data_buf <= {{PAR_PIXEL_NUM}{BLACK_R,BLACK_G,BLACK_B}};
							
						if( &frame_cnt & pos_vs )
							color_state <= 3'b000;
				 end 

				default:;
				endcase // color_state
			end

			always@(posedge clk or negedge  rst_n)
			begin
				if(~rst_n) begin
						o_vid_data <= 0;
					end
				else if(h_state == S_HACT && v_state == S_VACT) 
						o_vid_data <= o_vid_data_buf ;
				else 	
						o_vid_data <= 'd0;
			end

		end else if( TEST_MODE == 2'b10 )begin : ColorBar//===============================================================
			always@(posedge clk or negedge  rst_n)
			begin
				if(~rst_n) begin
						o_vid_data <= 0;
				end else if(h_state == S_HACT ) begin
					if( h_cnt <HACT_CNT/8) 
						o_vid_data <=  {{PAR_PIXEL_NUM}{WHITE_R,WHITE_G,WHITE_B}};
					else if( h_cnt <HACT_CNT/8*2)
						o_vid_data <= {{PAR_PIXEL_NUM}{YELLOW_R,YELLOW_G,YELLOW_B}};
					else if( h_cnt <HACT_CNT/8*3)
						o_vid_data <= {{PAR_PIXEL_NUM}{CYAN_R,CYAN_G,CYAN_B}};
					else if(h_cnt <HACT_CNT/8*4)
						o_vid_data <= {{PAR_PIXEL_NUM}{GREEN_R,GREEN_G,GREEN_B}};
					else if(h_cnt <HACT_CNT/8*5)
						o_vid_data <= {{PAR_PIXEL_NUM}{MAGENTA_R,MAGENTA_G,MAGENTA_B}};
					else if(h_cnt <HACT_CNT/8*6)
						o_vid_data <= {{PAR_PIXEL_NUM}{RED_R,RED_G,RED_B}}; 
					else if(h_cnt <HACT_CNT/8*7)
						o_vid_data <= {{PAR_PIXEL_NUM}{BLUE_R,BLUE_G,BLUE_B}};
					else 
						o_vid_data <= {{PAR_PIXEL_NUM}{BLACK_R,BLACK_G,BLACK_B}};
				end else 
						o_vid_data <= 'd0;	
			end 

		end else begin //=======================================================================================
			always@( posedge clk or negedge rst_n )
			begin 
				if( !rst_n ) begin
					o_vid_data <= 'd0 ;
				end else begin
					o_vid_data <= i_cfg_vid ;
				end 
			end
		end //==================================================================================================
	endgenerate 
	

	
	always @( posedge clk or negedge rst_n )
	begin
		if( !rst_n ) begin
			de 	  <= 'd0;
		end else begin
			de <= (h_state == S_HACT & v_state == S_VACT );
		end 
	end
	always @( posedge clk or negedge rst_n )
	begin
		if( !rst_n ) begin
			vs 	  <= 'd0;
			vs_r1 <= 'd0;
		end else begin
			vs <= (VS_POLORY == 1'b1) ? (v_state == S_VST) : ~(v_state == S_VST );
			vs_r1 <= vs;
		end 
	end
	
	always @( posedge clk or negedge rst_n)
	begin
		if( !rst_n ) begin
			hs_r1 <= 'd0;
		end else begin
			hs <= (HS_POLORY == 1'b1) ? (h_state == S_HST) : ~(h_state == S_HST);
		end 
	end
	
	
	endmodule
	
	

