# Run with efx_run.bat --flow sta_tclsh --tcl_script <this file> on a
# fully compiled candidate. Report physical delays even across clock groups.
report_path -from [get_cells {*u_tx*wr_snapshot* *u_request*wr_snapshot*}] -to [get_cells {*u_asset_network/tx_packet[*]~FF *u_asset_network/tx_length[*]~FF *u_asset_network/tx_local_ip[*]~FF *u_asset_network/tx_peer_ip[*]~FF *u_shared/descriptor[*]~FF}] -npaths 1488 -nworst 1 -summary -file net-mailbox-data.rpt
report_path -from [get_cells {*u_tx*request~FF *u_request*request~FF}] -to [get_cells {*u_tx*request_sync0* *u_request*request_sync0*}] -npaths 2 -nworst 1 -summary -file net-mailbox-request.rpt
report_path -from [get_cells {*u_tx*acknowledge~FF *u_request*acknowledge~FF}] -to [get_cells {*u_tx*acknowledge_sync0* *u_request*acknowledge_sync0*}] -npaths 2 -nworst 1 -summary -file net-mailbox-ack.rpt
write_sdc outflow/net-mailbox-applied.sdc
