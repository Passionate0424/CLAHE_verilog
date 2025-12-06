# ==================================================================
# ModelSim Simulation Script - CLAHE 16-tile BMP Multi-Frame Test
# ==================================================================

# Clear and create output directory for BMP images
if {![file exists sim_outputs]} {
    file mkdir sim_outputs
}

# Quit previous simulation
quit -sim

# Delete and recreate work library
if {[file exists work]} {
    vdel -all
}
vlib work
vmap work work

# ==================================================================
# Compile Source Files (16-tile RAM architecture)
# ==================================================================
puts "Compiling CLAHE Source Files..."

# RTL Files (in ../rtl/)
vlog -work work ../rtl/clahe_coord_counter.v
vlog -work work ../rtl/clahe_simple_dual_ram_model.v
vlog -work work ../rtl/clahe_true_dual_port_ram.v
vlog -work work ../rtl/clahe_ram_16tiles_parallel.v
vlog -work work ../rtl/clahe_histogram_stat.v
vlog -work work ../rtl/clahe_clipper_cdf.v
vlog -work work ../rtl/clahe_mapping_parallel.v
vlog -work work ../rtl/clahe_top.v

# Testbench Files (in ../tb/)
vlog -sv -work work ../tb/bmp_to_videoStream.sv
vlog -sv -work work ../tb/bmp_for_videoStream_24bit.sv
vlog -work work ../tb/tb_clahe_top_bmp_multi.v

# ==================================================================
# Start Simulation
# ==================================================================
vsim -voptargs=+acc work.tb_clahe_top_bmp_multi

# ==================================================================
# Waveforms
# ==================================================================
add wave -divider "Control"
add wave -format logic /tb_clahe_top_bmp_multi/pclk
add wave -format logic /tb_clahe_top_bmp_multi/rst_n
add wave -format logic /tb_clahe_top_bmp_multi/clahe_enable
add wave -format logic /tb_clahe_top_bmp_multi/interp_enable

add wave -divider "Input/Output"
add wave -format logic /tb_clahe_top_bmp_multi/in_href
add wave -format logic /tb_clahe_top_bmp_multi/in_vsync
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/in_y
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/out_y
add wave -format logic /tb_clahe_top_bmp_multi/out_href
add wave -format logic /tb_clahe_top_bmp_multi/out_vsync

add wave -divider "Status"
add wave -format logic /tb_clahe_top_bmp_multi/processing
add wave -format logic /tb_clahe_top_bmp_multi/cdf_ready
add wave -format logic /tb_clahe_top_bmp_multi/ping_pong_flag
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/frame_count

# Run Simulation
run -all
