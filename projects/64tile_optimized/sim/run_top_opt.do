quit -sim

vlib work
vmap work work

# Compile Utils
vlog -work work ../../16tile/tb/bmp_to_videoStream.sv
vlog -work work ../tb/bmp_for_videoStream_24bit.sv

# Compile RTL
vlog -work work ../rtl/clahe_coord_counter.v
vlog -work work ../rtl/clahe_histogram_stat.v
vlog -work work ../rtl/clahe_clipper_cdf.v
vlog -work work ../rtl/clahe_mapping_parallel.v
vlog -work work ../rtl/clahe_ram_banked.v
vlog -work work ../rtl/clahe_top.v

# Compile Testbench
vlog -work work ../tb/tb_clahe_top_bmp_multi.sv

# Simulate
vsim -voptargs=+acc work.tb_clahe_top_bmp_multi

# Waveform output
add wave -position insertpoint sim:/tb_clahe_top_bmp_multi/*
add wave -position insertpoint sim:/tb_clahe_top_bmp_multi/u_dut/*
add wave -position insertpoint sim:/tb_clahe_top_bmp_multi/u_dut/ram_banked_inst/*

run -all
quit -f
