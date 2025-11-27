# ==================================================================
# ModelSim Simulation Script - clahe_histogram_stat Module
#
# Usage:
#   1. In ModelSim: do run_histogram_stat.do
#   2. Or command line: vsim -do run_histogram_stat.do
# ==================================================================

# Exit previous simulation
quit -sim

# Delete work library
if {[file exists work]} {
    vdel -all
}

# Create work library
vlib work
vmap work work

# Compile design files
vlog -work work ../clahe_ram_64tiles.v
vlog -work work ../clahe_histogram_stat.v
vlog -work work ../tb/tb_clahe_histogram_stat.v

# Start simulation
vsim -voptargs=+acc work.tb_clahe_histogram_stat

# Add waveforms
add wave -divider "Clock and Reset"
add wave -format logic /tb_clahe_histogram_stat/pclk
add wave -format logic /tb_clahe_histogram_stat/rst_n

add wave -divider "Input Signals"
add wave -format logic /tb_clahe_histogram_stat/in_href
add wave -format logic /tb_clahe_histogram_stat/in_vsync
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/in_y
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/tile_idx

add wave -divider "Ping-pong Control"
add wave -format logic /tb_clahe_histogram_stat/ping_pong_flag
add wave -format logic /tb_clahe_histogram_stat/frame_hist_done

add wave -divider "RAM Port A (Write)"
add wave -format literal -radix hex /tb_clahe_histogram_stat/ram_wr_addr_a
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/ram_wr_data_a
add wave -format logic /tb_clahe_histogram_stat/ram_wr_en_a

add wave -divider "RAM Port B (Read)"
add wave -format literal -radix hex /tb_clahe_histogram_stat/ram_rd_addr_b
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/ram_rd_data_b

add wave -divider "Internal Pipeline"
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/u_dut/pixel_d1
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/u_dut/pixel_d2
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/u_dut/pixel_d3
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/u_dut/hist_count_rd
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/u_dut/hist_count_inc

add wave -divider "Control Signals"
add wave -format logic /tb_clahe_histogram_stat/u_dut/vsync_posedge
add wave -format logic /tb_clahe_histogram_stat/u_dut/vsync_negedge
add wave -format logic /tb_clahe_histogram_stat/u_dut/clear_busy
add wave -format literal -radix unsigned /tb_clahe_histogram_stat/u_dut/clear_addr

# Run simulation
run -all

# Zoom waveform
wave zoom full

puts "Simulation Complete!"
puts "Check Console window for test results"
puts "Check Wave window for waveforms"
puts ""
puts "Verification Points:"
puts "1. Pure color image: each tile's corresponding bin count should be 14400"
puts "2. Ping-pong switching: RAM A and RAM B alternate writing"
puts "3. vsync rising edge triggers RAM clear"
puts "4. frame_hist_done generates single cycle pulse at vsync falling edge"



