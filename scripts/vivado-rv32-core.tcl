if {$argc != 2} {
    error "usage: vivado-rv32-core.tcl <filelist.f> <report-directory>"
}

set filelist [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set rtl_dir [file dirname $filelist]
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
        read_verilog -sv [file join $rtl_dir $rtl_file]
    }
}
close $input

synth_design -top Rv32Core -part $target_part -mode out_of_context
create_clock -name core_clock -period 10.000 [get_ports clock]

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -sort_by group \
    -file [file join $report_dir timing_paths.rpt]

set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] > 0} {
    puts "RV32CORE_WNS=[get_property SLACK $worst_path]"
    puts "RV32CORE_LOGIC_LEVELS=[get_property LOGIC_LEVELS $worst_path]"
    puts "RV32CORE_STARTPOINT=[get_property STARTPOINT_PIN $worst_path]"
    puts "RV32CORE_ENDPOINT=[get_property ENDPOINT_PIN $worst_path]"
}

close_project
