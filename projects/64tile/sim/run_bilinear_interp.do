# ============================================================================
# ModelSim Simulation Script - CLAHE Bilinear Interpolation Module
#
# Function: Compile and simulate clahe_bilinear_interp module
# Usage: vsim -do run_bilinear_interp.do
#
# Author: Passionate.Z
# Date: 2025-10-15
# ============================================================================

# Exit previous simulation
quit -sim

# Create work library
vlib work
vmap work work

# Set paths
set RTL_PATH "../"
set TB_PATH "../tb"

# Compile RTL files
echo "Compiling RTL files..."
vlog -sv $RTL_PATH/clahe_bilinear_interp.v

if {[string match "*Error:*" [vlog -sv $RTL_PATH/clahe_bilinear_interp.v]]} {
    echo "RTL compilation failed"
    quit -f
}

# Compile Testbench
echo "Compiling Testbench..."
vlog -sv $TB_PATH/tb_clahe_bilinear_interp.v

if {[string match "*Error:*" [vlog -sv $TB_PATH/tb_clahe_bilinear_interp.v]]} {
    echo "Testbench compilation failed"
    quit -f
}

# Start simulation
echo "Starting simulation..."
vsim -voptargs=+acc work.tb_clahe_bilinear_interp

# Add waveforms
echo "Adding waveform signals..."

# Clock and Reset
add wave -divider "Clock & Reset"
add wave -color "Yellow" /tb_clahe_bilinear_interp/pclk
add wave -color "Red" /tb_clahe_bilinear_interp/rst_n

# Control Signals
add wave -divider "Control"
add wave /tb_clahe_bilinear_interp/interp_enable
add wave /tb_clahe_bilinear_interp/in_vsync
add wave /tb_clahe_bilinear_interp/in_href

# Input Coordinates
add wave -divider "Input Coordinates"
add wave -radix unsigned /tb_clahe_bilinear_interp/tile_x
add wave -radix unsigned /tb_clahe_bilinear_interp/tile_y
add wave -radix unsigned /tb_clahe_bilinear_interp/tile_idx
add wave -radix unsigned /tb_clahe_bilinear_interp/local_x
add wave -radix unsigned /tb_clahe_bilinear_interp/local_y

# Input Pixels
add wave -divider "Input Pixels"
add wave -radix unsigned /tb_clahe_bilinear_interp/in_y
add wave -radix unsigned /tb_clahe_bilinear_interp/in_u
add wave -radix unsigned /tb_clahe_bilinear_interp/in_v
add wave -radix unsigned /tb_clahe_bilinear_interp/pixel_value

# Internal Signals - Border Detection
add wave -divider "Internal - Border Detection"
add wave /tb_clahe_bilinear_interp/u_dut/is_left_border
add wave /tb_clahe_bilinear_interp/u_dut/is_right_border
add wave /tb_clahe_bilinear_interp/u_dut/is_top_border
add wave /tb_clahe_bilinear_interp/u_dut/is_bottom_border
add wave /tb_clahe_bilinear_interp/u_dut/need_interp

# Internal Signals - Tile Indices
add wave -divider "Internal - Tile Indices"
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/tile_idx_tl
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/tile_idx_tr
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/tile_idx_bl
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/tile_idx_br

# CDF Read
add wave -divider "CDF LUT Read"
add wave -radix hex /tb_clahe_bilinear_interp/cdf_rd_addr_tl
add wave -radix unsigned /tb_clahe_bilinear_interp/cdf_rd_data_tl
add wave -radix hex /tb_clahe_bilinear_interp/cdf_rd_addr_tr
add wave -radix unsigned /tb_clahe_bilinear_interp/cdf_rd_data_tr
add wave -radix hex /tb_clahe_bilinear_interp/cdf_rd_addr_bl
add wave -radix unsigned /tb_clahe_bilinear_interp/cdf_rd_data_bl
add wave -radix hex /tb_clahe_bilinear_interp/cdf_rd_addr_br
add wave -radix unsigned /tb_clahe_bilinear_interp/cdf_rd_data_br

# Internal Signals - Mapped Values
add wave -divider "Internal - Mapped Values"
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/mapped_tl
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/mapped_tr
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/mapped_bl
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/mapped_br

# Internal Signals - Weights
add wave -divider "Internal - Weights"
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/weight_x
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/weight_y

# Internal Signals - Interpolation
add wave -divider "Internal - Interpolation"
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/interp_temp0
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/interp_temp1
add wave -radix unsigned /tb_clahe_bilinear_interp/u_dut/final_interp

# Output Signals
add wave -divider "Output"
add wave /tb_clahe_bilinear_interp/out_href
add wave /tb_clahe_bilinear_interp/out_vsync
add wave -radix unsigned -color "Green" /tb_clahe_bilinear_interp/out_y
add wave -radix unsigned /tb_clahe_bilinear_interp/out_u
add wave -radix unsigned /tb_clahe_bilinear_interp/out_v

# Configure waveform window
configure wave -namecolwidth 350
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Run simulation
echo "Running simulation..."
run -all

# Zoom waveform
wave zoom full

echo "Simulation Complete!"
echo "Check waveforms to verify:"
echo "  1. Center region: need_interp=0, out_y=in_y"
echo "  2. Border region: need_interp=1, out_y is interpolated"
echo "  3. Interpolation result between 4 mapped values"
echo "  4. U/V channels correctly delay matched"

