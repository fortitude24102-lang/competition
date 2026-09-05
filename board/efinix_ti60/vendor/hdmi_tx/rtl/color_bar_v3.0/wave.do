onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/clk
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/rst_n
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/clk_div2
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/clk_div4
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/clk_div8
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/r_data
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/g_data
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/b_data
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/hs
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/vs
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/de
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/h_cnt
add wave -noupdate -group sim:/color_bar_tb/Group1 -radix unsigned /color_bar_tb/v_cnt
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/clk
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/rst_n
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/i_hs
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/i_vs
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/i_de
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/i_vid
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/h_sync
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/h_back_porch
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/h_front_porch
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/h_active
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/v_active
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/v_sync
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/v_back_porch
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/v_front_porch
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/pos_hs
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/neg_hs
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/pos_vs
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/neg_vs
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/pos_de
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/neg_de
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/vs_r0
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/hs_r0
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/de_r0
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/w_v_front_porch
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/w_v_back_porch
add wave -noupdate -group sim:/color_bar_tb/u_timing_detec/Group1 -radix unsigned /color_bar_tb/u_timing_detec/w_v_active
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/clk
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/rst_n
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/i_cfg_vid
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/h_cnt
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/v_cnt
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/hs
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/vs
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/de
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/o_vid_data
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/h_state
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/v_state
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/hs_r1
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/vs_r1
add wave -noupdate -expand -label sim:/color_bar_tb/color_bar_rgb_inst/Group1 -group {Region: sim:/color_bar_tb/color_bar_rgb_inst} /color_bar_tb/color_bar_rgb_inst/de_r1
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {23247370000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 255
configure wave -valuecolwidth 40
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits us
update
WaveRestoreZoom {2710000162 ps} {5075482128 ps}
