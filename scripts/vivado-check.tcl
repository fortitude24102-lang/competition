if {$argc != 1} {
    error "usage: vivado-check.tcl <Blink.sv>"
}

set rtl_file [file normalize [lindex $argv 0]]
if {![file exists $rtl_file]} {
    error "RTL file does not exist: $rtl_file"
}

set target_part xc7z015clg485-2
create_project -in_memory -part $target_part
read_verilog -sv $rtl_file
synth_design -rtl -top Blink -part $target_part
puts "Vivado RTL elaboration passed for $rtl_file"
close_project
