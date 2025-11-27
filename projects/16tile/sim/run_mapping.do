# ==================================================================
# ModelSim Simulation Script - clahe_mapping Module (Standard CLAHE)
#
# Description:
#   测试标准CLAHE映射模块，包含四tile双线性插值功能
#
# Usage:
#   vsim -do run_mapping.do
# ==================================================================

quit -sim

if {[file exists work]} {
    vdel -all
}

vlib work
vmap work work

# Compile files
vlog -work work ../clahe_mapping.v
vlog -work work ../tb/tb_clahe_mapping.v

# Start simulation
vsim -voptargs=+acc work.tb_clahe_mapping

# Add waveforms
add wave -divider "Clock and Reset"
add wave -format logic /tb_clahe_mapping/pclk
add wave -format logic /tb_clahe_mapping/rst_n

add wave -divider "Input Signals"
add wave -format logic /tb_clahe_mapping/in_href
add wave -format logic /tb_clahe_mapping/in_vsync
add wave -format literal -radix unsigned /tb_clahe_mapping/in_y
add wave -format literal -radix unsigned /tb_clahe_mapping/in_u
add wave -format literal -radix unsigned /tb_clahe_mapping/in_v
add wave -format literal -radix unsigned /tb_clahe_mapping/tile_idx
add wave -format literal -radix unsigned /tb_clahe_mapping/pixel_x
add wave -format literal -radix unsigned /tb_clahe_mapping/pixel_y

add wave -divider "Control Signals"
add wave -format logic /tb_clahe_mapping/clahe_enable
add wave -format logic /tb_clahe_mapping/interp_enable
add wave -format logic /tb_clahe_mapping/cdf_ready

add wave -divider "CDF LUT Access (64-tile)"
add wave -format literal -radix unsigned /tb_clahe_mapping/cdf_rd_tile_idx
add wave -format literal -radix unsigned /tb_clahe_mapping/cdf_rd_bin_addr
add wave -format literal -radix unsigned /tb_clahe_mapping/cdf_rd_data

add wave -divider "Interpolation Control"
add wave -format literal -radix unsigned /tb_clahe_mapping/read_stage_out
add wave -format logic /tb_clahe_mapping/interp_active

add wave -divider "Output Signals"
add wave -format logic /tb_clahe_mapping/out_href
add wave -format logic /tb_clahe_mapping/out_vsync
add wave -format literal -radix unsigned /tb_clahe_mapping/out_y
add wave -format literal -radix unsigned /tb_clahe_mapping/out_u
add wave -format literal -radix unsigned /tb_clahe_mapping/out_v

add wave -divider "Internal Pipeline (8-stage)"
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/y_d1
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/y_d2
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/y_d3
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/y_d4
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/y_d5
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/y_d6
add wave -format logic /tb_clahe_mapping/u_dut/enable_d1
add wave -format logic /tb_clahe_mapping/u_dut/interp_d1

add wave -divider "Four-tile CDF Cache"
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/cdf_tl
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/cdf_tr
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/cdf_bl
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/cdf_br
add wave -format logic /tb_clahe_mapping/u_dut/cdf_valid_tl
add wave -format logic /tb_clahe_mapping/u_dut/cdf_valid_tr
add wave -format logic /tb_clahe_mapping/u_dut/cdf_valid_bl
add wave -format logic /tb_clahe_mapping/u_dut/cdf_valid_br

add wave -divider "Interpolation Weights"
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/wx_d1
add wave -format literal -radix unsigned /tb_clahe_mapping/u_dut/wy_d1

# 运行仿真
run -all

wave zoom full

puts "========================================" 
puts "  Mapping Module Simulation Complete"
puts "========================================"
puts "Verification Points:"
puts "1. Bypass mode: out_y = in_y (8-stage delay)"
puts "2. CLAHE mapping: out_y = cdf_lut[tile_idx][in_y]"
puts "3. Interpolation: 4-tile bilinear interpolation"
puts "4. U/V channels correctly delay matched (8 stages)"
puts "5. Sync signals correctly passed"
puts "========================================"


