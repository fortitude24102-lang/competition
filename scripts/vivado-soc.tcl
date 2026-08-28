if {$argc != 2} {
    error "usage: vivado-soc.tcl <filelist.f> <report-directory>"
}

set filelist [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set target_part xc7z015clg485-2

if {![file exists $filelist]} {
    error "RTL file list does not exist: $filelist"
}

file mkdir $report_dir
create_project -in_memory -part $target_part

set input [open $filelist r]
foreach line [split [read $input] "\n"] {
    set rtl_file [string trim $line]
    if {$rtl_file ne ""} {
        read_verilog -sv [file normalize $rtl_file]
    }
}
close $input

synth_design -top SoCTop -part $target_part -mode out_of_context
create_clock -name soc_clock -period 10.000 [get_ports clock]
create_clock -name soc_io_virtual -period 10.000
set data_inputs [get_ports -filter {DIRECTION == IN && NAME != clock}]
set_input_delay -clock soc_io_virtual 2.000 $data_inputs
set_output_delay -clock soc_io_virtual 2.000 [all_outputs]

report_utilization -file [file join $report_dir utilization.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -sort_by group \
    -file [file join $report_dir timing_paths.rpt]
write_checkpoint -force [file join $report_dir SoCTop_ooc.dcp]

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] == 0} {
    error "Vivado did not return a timed SoCTop path"
}

puts "SOC_WNS=[get_property SLACK $worst_path]"
puts "SOC_LOGIC_LEVELS=[get_property LOGIC_LEVELS $worst_path]"
puts "SOC_STARTPOINT=[get_property STARTPOINT_PIN $worst_path]"
puts "SOC_ENDPOINT=[get_property ENDPOINT_PIN $worst_path]"
puts "SOC_LUT=[llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]"
puts "SOC_FF=[llength [get_cells -hier -filter {REF_NAME =~ FD*}]]"
puts "SOC_BRAM=[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]"
puts "SOC_DSP=[llength [get_cells -hier -filter {REF_NAME =~ DSP*}]]"

close_project
