# ============================================================================
# ModelSim Simulation Script - CLAHE Standard Bilinear Interpolation Module (v2)
#
# Function: Compile and simulate clahe_bilinear_interp_v2 module
# Usage: vsim -do run_bilinear_interp_v2.do
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
vlog -sv $RTL_PATH/clahe_bilinear_interp_v2.v

if {[string match "*Error:*" [vlog -sv $RTL_PATH/clahe_bilinear_interp_v2.v]]} {
    echo "RTL compilation failed"
    quit -f
}

# Compile Testbench
echo "Compiling Testbench..."
vlog -sv $TB_PATH/tb_clahe_bilinear_interp_v2.v

if {[string match "*Error:*" [vlog -sv $TB_PATH/tb_clahe_bilinear_interp_v2.v]]} {
    echo "Testbench compilation failed"
    quit -f
}

# Start simulation
echo "Starting simulation..."
vsim -voptargs=+acc work.tb_clahe_bilinear_interp_v2

# Add waveforms
echo "Adding waveform signals..."

# Clock and Reset
add wave -divider "Clock & Reset"
add wave -color "Yellow" /tb_clahe_bilinear_interp_v2/pclk
add wave -color "Red" /tb_clahe_bilinear_interp_v2/rst_n

# Control Signals
add wave -divider "Control"
add wave /tb_clahe_bilinear_interp_v2/interp_enable
add wave /tb_clahe_bilinear_interp_v2/cdf_ready
add wave /tb_clahe_bilinear_interp_v2/in_vsync
add wave /tb_clahe_bilinear_interp_v2/in_href
add wave /tb_clahe_bilinear_interp_v2/in_data_en

# Input Coordinates and Pixels
add wave -divider "Input Coordinates"
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/x_coord
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/y_coord
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/in_y
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/in_u
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/in_v

# Internal Signals - Stage 1
add wave -divider "Internal - Stage 1"
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_x
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_y
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/local_x
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/local_y

# Internal Signals - Stage 2 (tile selection and weights)
add wave -divider "Internal - Stage 2 (Tile Selection)"
add wave -radix decimal /tb_clahe_bilinear_interp_v2/u_dut/dx
add wave -radix decimal /tb_clahe_bilinear_interp_v2/u_dut/dy
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_tl_x
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_tl_y
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_tr_x
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_tr_y
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_bl_x
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_bl_y
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_br_x
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_br_y

# Weights
add wave -divider "Internal - Weights"
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/wx_d2
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/wy_d2

# Tile Indices
add wave -divider "Internal - Tile Indices"
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_tl
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_tr
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_bl
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/tile_idx_br

# CDF Read
add wave -divider "CDF LUT Read"
add wave -radix hex /tb_clahe_bilinear_interp_v2/cdf_rd_addr_tl
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/cdf_rd_data_tl
add wave -radix hex /tb_clahe_bilinear_interp_v2/cdf_rd_addr_tr
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/cdf_rd_data_tr
add wave -radix hex /tb_clahe_bilinear_interp_v2/cdf_rd_addr_bl
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/cdf_rd_data_bl
add wave -radix hex /tb_clahe_bilinear_interp_v2/cdf_rd_addr_br
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/cdf_rd_data_br

# Internal Signals - Stage 3 (horizontal interpolation)
add wave -divider "Internal - Stage 3 (Horizontal Interp)"
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/mapped_tl
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/mapped_tr
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/mapped_bl
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/mapped_br
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/interp_top
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/interp_bottom

# Internal Signals - Stage 4 (vertical interpolation)
add wave -divider "Internal - Stage 4 (Vertical Interp)"
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/u_dut/final_interp

# Output Signals
add wave -divider "Output"
add wave /tb_clahe_bilinear_interp_v2/out_href
add wave /tb_clahe_bilinear_interp_v2/out_vsync
add wave /tb_clahe_bilinear_interp_v2/out_data_en
add wave -radix unsigned -color "Green" /tb_clahe_bilinear_interp_v2/out_y
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/out_u
add wave -radix unsigned /tb_clahe_bilinear_interp_v2/out_v

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
echo "  1. Full-image interpolation: all pixels calculate weights"
echo "  2. Tile selection: dynamically select 4 tiles based on dx/dy"
echo "  3. Boundary protection: image edge tiles don't overflow"
echo "  4. Weight calculation: based on offset from tile center"
echo "  5. Interpolation result: continuous and smooth"

