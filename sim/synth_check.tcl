set rtl E:/ZEROiZATION/rhbd_mem_ctrl/rtl
read_verilog [glob $rtl/*.v]
synth_design -top fpga_top -part xc7a35tcpg236-1 -include_dirs $rtl -mode out_of_context
report_utilization
puts "=== TMR CHECK ==="
puts "state copy 0 FFs: [llength [get_cells -hier -filter {NAME =~ *state_code_r0_reg*}]]"
puts "state copy 1 FFs: [llength [get_cells -hier -filter {NAME =~ *state_code_r1_reg*}]]"
puts "state copy 2 FFs: [llength [get_cells -hier -filter {NAME =~ *state_code_r2_reg*}]]"
puts "tamper latch FFs: [llength [get_cells -hier -filter {NAME =~ *tamper_latch*reg*}]]"
puts "voter cells: [llength [get_cells -hier -filter {NAME =~ *fsm_voter*}]]"
puts "=== SYNTHESIS DONE ==="

