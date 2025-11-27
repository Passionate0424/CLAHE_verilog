# ==================================================================
# ModelSim Simulation Script - clahe_clipper_cdf Module
#
# Usage:
#   vsim -do run_clipper_cdf.do
# ==================================================================

quit -sim

if {[file exists work]} {
    vdel -all
}

vlib work
vmap work work

# Compile files
vlog -work work ../clahe_clipper_cdf.v
vlog -work work ../tb/tb_clahe_clipper_cdf.v

# Start simulation
vsim -voptargs=+acc work.tb_clahe_clipper_cdf

# Add waveforms
add wave -divider "Clock and Reset"
add wave -format logic /tb_clahe_clipper_cdf/pclk
add wave -format logic /tb_clahe_clipper_cdf/rst_n

add wave -divider "Control Signals"
add wave -format logic /tb_clahe_clipper_cdf/frame_hist_done
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/clip_limit
add wave -format logic /tb_clahe_clipper_cdf/ping_pong_flag
add wave -format logic /tb_clahe_clipper_cdf/processing
add wave -format logic /tb_clahe_clipper_cdf/cdf_done

add wave -divider "State Machine"
add wave -format literal /tb_clahe_clipper_cdf/u_dut/state
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/tile_cnt
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/bin_cnt

add wave -divider "Histogram Read"
add wave -format literal -radix hex /tb_clahe_clipper_cdf/hist_rd_addr
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/hist_rd_data_a
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/hist_rd_data_b

add wave -divider "Clip Processing"
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/excess_total
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/excess_per_bin
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/valid_bins_cnt

add wave -divider "CDF Calculation"
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_min
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_range
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_temp

add wave -divider "CDF LUT Output"
add wave -format literal -radix hex /tb_clahe_clipper_cdf/cdf_wr_addr
add wave -format literal -radix unsigned /tb_clahe_clipper_cdf/cdf_wr_data
add wave -format logic /tb_clahe_clipper_cdf/cdf_wr_en

# 运行仿真
run -all

wave zoom full

puts "========================================" 
puts "  Clipper & CDF Simulation Complete"
puts "========================================"
puts "Verification Points:"
puts "1. State machine transitions correctly"
puts "2. Clip bins exceeding threshold"
puts "3. Excess values redistributed correctly"
puts "4. CDF monotonically increasing"
puts "5. Mapping values in range 0-255"
puts "========================================"


