quit -sim

vlib work
vmap work work

# Compile Utils (Shared from 16tile project)
vlog -work work ../../16tile/tb/bmp_to_videoStream.sv
# Note: bmp_for_videoStream_24bit.sv might be in 16tile or 64tile/tb.
# Checking file system... assuming it's in local tb or needs to be compiled.
# If previous run_top utilized local 'bmp_for_videoStream_24bit.sv', we need to find it.
# The previous view_file of tb showed: .iBMP_FILE_PATH("bmp_test_results/input/")
# Let's assume the util behaves same.
# We will compile the one in 16tile if local one doesn't exist, OR check if it exists in local tb.
# Ideally, we used the one from `projects/64tile_optimized/tb/bmp_for_videoStream_24bit.sv`.
# I should copy that too to be safe, or reference it.
# Simpler: reference the one in `../tb/` if I copied it, but I didn't copy the helper.
# I will reference the one in `../../64tile_optimized/tb/bmp_for_videoStream_24bit.sv` to be 100% sure we use the same util.

vlog -work work ../../64tile_optimized/tb/bmp_for_videoStream_24bit.sv

# Compile RTL (Original 64tile)
vlog -work work ../rtl/clahe_coord_counter.v
vlog -work work ../rtl/clahe_histogram_stat.v
vlog -work work ../rtl/clahe_clipper_cdf.v
vlog -work work ../rtl/clahe_mapping_parallel.v
vlog -work work ../rtl/clahe_ram_64tiles_parallel.v
vlog -work work ../rtl/clahe_ram_true_dual.v
vlog -work work ../rtl/clahe_simple_dual_ram_model.v
vlog -work work ../rtl/clahe_top.v

# Compile Testbench
vlog -work work ../tb/tb_clahe_top_bmp_multi.sv

# Simulate
vsim -voptargs=+acc work.tb_clahe_top_bmp_multi

# Waveform output (Optional)
# add wave -position insertpoint sim:/tb_clahe_top_bmp_multi/*

run -all
quit -f
