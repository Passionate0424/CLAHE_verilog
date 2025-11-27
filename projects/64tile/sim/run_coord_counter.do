# ==================================================================
# ModelSim Simulation Script - clahe_coord_counter Module
# 
# Usage:
#   1. In ModelSim: do run_coord_counter.do
#   2. Or command line: vsim -do run_coord_counter.do
# ==================================================================

# Exit previous simulation
quit -sim

# Delete work library (if exists)
if {[file exists work]} {
    vdel -all
}

# Create work library
vlib work
vmap work work

# Compile design files
vlog -work work ../clahe_coord_counter.v
vlog -work work ../tb/tb_clahe_coord_counter.v

# Start simulation
vsim -voptargs=+acc work.tb_clahe_coord_counter

# Add waveforms
add wave -divider "Clock and Reset"
add wave -format logic /tb_clahe_coord_counter/pclk
add wave -format logic /tb_clahe_coord_counter/rst_n

add wave -divider "Input Signals"
add wave -format logic /tb_clahe_coord_counter/in_href
add wave -format logic /tb_clahe_coord_counter/in_vsync

add wave -divider "Pixel Coordinates"
add wave -format literal -radix unsigned /tb_clahe_coord_counter/x_cnt
add wave -format literal -radix unsigned /tb_clahe_coord_counter/y_cnt

add wave -divider "Tile Index"
add wave -format literal -radix unsigned /tb_clahe_coord_counter/tile_x
add wave -format literal -radix unsigned /tb_clahe_coord_counter/tile_y
add wave -format literal -radix unsigned /tb_clahe_coord_counter/tile_idx

add wave -divider "Local Coordinates"
add wave -format literal -radix unsigned /tb_clahe_coord_counter/local_x
add wave -format literal -radix unsigned /tb_clahe_coord_counter/local_y

add wave -divider "Test Signals"
add wave -format literal -radix unsigned /tb_clahe_coord_counter/pixel_count
add wave -format literal -radix unsigned /tb_clahe_coord_counter/line_count
add wave -format literal -radix unsigned /tb_clahe_coord_counter/frame_count

# Run simulation
run -all

# Zoom waveform
wave zoom full

puts "Simulation Complete!"
puts "Check Console window for test results"
puts "Check Wave window for waveforms"



