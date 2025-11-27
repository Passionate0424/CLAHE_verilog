# ==================================================================
# ModelSim Simulation Script - CLAHE Top-level Module
# 64-tile Parallel RAM Architecture with Ping-Pong Buffer
#
# Usage:
#   cd tb
#   vsim -do run_clahe_top.do
#
# Or from main directory:
#   vsim -do tb/run_clahe_top.do
# ==================================================================

# Clear and create output directory for BMP images
if {[file exists sim_outputs]} {
    # Try to delete individual files first (safer approach)
    set files [glob -nocomplain sim_outputs/*]
    foreach file $files {
        if {[file exists $file]} {
            if {[catch {file delete -force $file} err]} {
                puts "Warning: Could not delete $file: $err"
            }
        }
    }
    # Try to remove directory if empty
    if {[catch {file delete -force sim_outputs} err]} {
        puts "Warning: Could not delete directory sim_outputs: $err"
        puts "Directory may contain files in use. Continuing with existing directory."
    } else {
        puts "Cleared existing output directory: sim_outputs/"
    }
}
# Ensure directory exists
if {![file exists sim_outputs]} {
    file mkdir sim_outputs
    puts "Created fresh output directory: sim_outputs/"
} else {
    puts "Using existing output directory: sim_outputs/"
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
# Compile Source Files (64-tile RAM architecture)
# ==================================================================
puts ""
puts "========================================"
puts "  Compiling CLAHE Source Files"
puts "========================================"

# Basic modules
vlog -work work ../clahe_coord_counter.v

# RAM modules (using parallel version)
vlog -work work ../clahe_simple_dual_ram.v
vlog -work work ../clahe_ram_64tiles_parallel.v

# Histogram statistics
vlog -work work ../clahe_histogram_stat.v

# CDF processing
vlog -work work ../clahe_clipper_cdf.v

# Mapping module (using parallel version)
vlog -work work ../clahe_mapping_parallel.v

# Top module
vlog -work work ../clahe_top.v

# BMP module (SystemVerilog)
vlog -sv -work work ../tb/bmp_for_videoStream_24bit.sv

# Testbench
vlog -work work ../tb/tb_clahe_top.v

puts "✓ All files compiled successfully"
puts ""

# ==================================================================
# Start Simulation
# ==================================================================
puts "========================================"
puts "  Starting Simulation"
puts "========================================"
vsim -voptargs=+acc work.tb_clahe_top

# ==================================================================
# Add Waveforms - Organized by Functionality
# ==================================================================

# Top-level Control
add wave -divider "========== Clock & Reset =========="
add wave -format logic /tb_clahe_top/pclk
add wave -format logic /tb_clahe_top/rst_n
add wave -divider "========== Control Signals =========="
add wave -format logic /tb_clahe_top/clahe_enable
add wave -format logic /tb_clahe_top/interp_enable
add wave -format literal -radix unsigned /tb_clahe_top/clip_threshold

# Input YUV Stream
add wave -divider "========== Input YUV Stream =========="
add wave -format logic /tb_clahe_top/in_href
add wave -format logic /tb_clahe_top/in_vsync
add wave -format literal -radix unsigned /tb_clahe_top/in_y
add wave -format literal -radix unsigned /tb_clahe_top/in_u
add wave -format literal -radix unsigned /tb_clahe_top/in_v

# Output YUV Stream
add wave -divider "========== Output YUV Stream =========="
add wave -format logic /tb_clahe_top/out_href
add wave -format logic /tb_clahe_top/out_vsync
add wave -format literal -radix unsigned /tb_clahe_top/out_y
add wave -format literal -radix unsigned /tb_clahe_top/out_u
add wave -format literal -radix unsigned /tb_clahe_top/out_v

# Internal State Machine
add wave -divider "========== DUT Internal State =========="
add wave -format logic /tb_clahe_top/u_dut/ping_pong_flag
add wave -format logic /tb_clahe_top/u_dut/frame_hist_done
add wave -format logic /tb_clahe_top/u_dut/cdf_processing
add wave -format logic /tb_clahe_top/u_dut/cdf_done

# Coordinate & Tile Information
add wave -divider "========== Coordinates & Tiles =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/coord_counter_inst/x_cnt
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/coord_counter_inst/y_cnt
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/tile_x
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/tile_y
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/tile_idx

# Histogram Statistics
add wave -divider "========== Histogram Statistics - Write =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/hist_wr_tile_idx
add wave -format literal -radix hex /tb_clahe_top/u_dut/hist_wr_addr
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/hist_wr_data
add wave -format logic /tb_clahe_top/u_dut/hist_wr_en

add wave -divider "========== Histogram Statistics - Read =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/hist_rd_tile_idx
add wave -format literal -radix hex /tb_clahe_top/u_dut/hist_rd_addr
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/hist_rd_data

# CDF Processing - 详细信号跟踪
add wave -divider "========== CDF Processing - State Machine =========="
add wave -format literal /tb_clahe_top/u_dut/clipper_cdf_inst/state
add wave -format literal /tb_clahe_top/u_dut/clipper_cdf_inst/next_state
add wave -format logic /tb_clahe_top/u_dut/clipper_cdf_inst/processing
add wave -format logic /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_done
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/tile_cnt
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/bin_cnt

add wave -divider "========== CDF - Control Inputs =========="
add wave -format logic /tb_clahe_top/u_dut/clipper_cdf_inst/frame_hist_done
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/clip_limit
add wave -format logic /tb_clahe_top/u_dut/clipper_cdf_inst/ping_pong_flag

add wave -divider "========== CDF - Histogram Read Interface =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_tile_idx
add wave -format literal -radix hex /tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_bin_addr
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data_a
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data_b
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data

add wave -divider "========== CDF - Clip Processing =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/excess_total
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/excess_per_bin
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_buf\[0\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_buf\[1\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_buf\[127\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_buf\[255\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_clipped\[0\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_clipped\[127\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/hist_clipped\[255\]

add wave -divider "========== CDF - Calculation =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_temp
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_min
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_max
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_range
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf\[0\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf\[1\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf\[64\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf\[127\]
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf\[255\]

add wave -divider "========== CDF - Write to LUT RAM =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_tile_idx
add wave -format literal -radix hex /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_bin_addr
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_data
add wave -format logic /tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_en

add wave -divider "========== CDF - Top-level Interface =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/cdf_tile_idx
add wave -format literal -radix hex /tb_clahe_top/u_dut/cdf_addr
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/cdf_wr_data
add wave -format logic /tb_clahe_top/u_dut/cdf_wr_en
add wave -format logic /tb_clahe_top/u_dut/cdf_rd_en
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/cdf_rd_data

# Pixel Mapping
add wave -divider "========== Pixel Mapping =========="
# Map module key signals
add wave -format logic /tb_clahe_top/u_dut/mapping_inst/clahe_enable
add wave -format logic /tb_clahe_top/u_dut/mapping_inst/interp_enable
add wave -format logic /tb_clahe_top/u_dut/mapping_inst/cdf_ready
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/in_y
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/out_y
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/tile_idx
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/pixel_x
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/pixel_y

# 四块tile索引
add wave -divider "========== Tile Indices (4 blocks) =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_tl_tile_idx
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_tr_tile_idx
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_bl_tile_idx
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_br_tile_idx
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_addr

# CDF读取数据（接口信号）
add wave -divider "========== CDF Read Data (Interface) =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_tl_rd_data
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_tr_rd_data
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_bl_rd_data
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_br_rd_data

# CDF流水线寄存器（延迟1周期后）
add wave -divider "========== CDF Pipeline Registers (d2) =========="
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_tl_d2
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_tr_d2
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_bl_d2
add wave -format literal -radix unsigned /tb_clahe_top/u_dut/mapping_inst/cdf_br_d2

# RAM输出对比（检查哪个RAM有数据）
add wave -divider "========== RAM Output (A vs B) =========="
add wave -format literal -radix hex /tb_clahe_top/u_dut/ram_64tiles_inst/ram_a_dout_b(0)
add wave -format literal -radix hex /tb_clahe_top/u_dut/ram_64tiles_inst/ram_b_dout_b(0)
add wave -format literal -radix hex /tb_clahe_top/u_dut/ram_64tiles_inst/ram_a_dout_b(1)
add wave -format literal -radix hex /tb_clahe_top/u_dut/ram_64tiles_inst/ram_b_dout_b(1)

# 关键控制信号
add wave -divider "========== Interpolation Control =========="
add wave -format logic /tb_clahe_top/u_dut/mapping_inst/need_interp
add wave -format logic /tb_clahe_top/u_dut/enable_clahe
add wave -format logic /tb_clahe_top/u_dut/enable_interp
add wave -format logic /tb_clahe_top/u_dut/mapping_inst/enable_d1
add wave -format logic /tb_clahe_top/u_dut/mapping_inst/interp_d1

# BMP Saving Status
add wave -divider "========== BMP File Saving =========="
add wave -format logic /tb_clahe_top/bmp_in_ready
add wave -format logic /tb_clahe_top/bmp_out_ready
add wave -format logic /tb_clahe_top/bmp_in_frame_sync_n
add wave -format logic /tb_clahe_top/bmp_out_frame_sync_n

# Test Variables
add wave -divider "========== Test Status =========="
add wave -format literal -radix unsigned /tb_clahe_top/frame
add wave -format literal -radix unsigned /tb_clahe_top/total_frames

# ==================================================================
# Configure Wave Window
# ==================================================================
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# ==================================================================
# Run Simulation
# ==================================================================
puts ""
puts "========================================"
puts "  Running Simulation"
puts "========================================"
puts "This will process multiple test frames."
puts "Expected runtime: ~5-10 minutes"
puts "Output images: sim_outputs/"
puts ""
puts "Test Sequence:"
puts "  Frame 0:  Bypass (building CDF)"
puts "  Frame 1:  CLAHE enabled (Y=60)"
puts "  Frame 2:  Low contrast"
puts "  Frame 3:  Gradient"
puts "  Frame 4:  Interpolation test"
puts "  Frame 5:  Different clip threshold"
puts "  Frame 6:  CLAHE disabled"
puts "  Frame 7:  CLAHE re-enabled"
puts "  Frame 8:  Very dark image"
puts "  Frame 9:  Very bright image"
puts "  Frame 10-20: Additional tests"
puts ""

# Run the simulation
run -all

# Zoom to fit
wave zoom full

# ==================================================================
# Simulation Complete Message
# ==================================================================
puts ""
puts "========================================" 
puts "  Simulation Complete!"
puts "========================================"
puts ""
puts "Results:"
puts "  • Check console for frame statistics"
puts "  • BMP files saved to: sim_outputs/"
puts "    - frame_input*.bmp  (input images)"
puts "    - frame_output*.bmp (CLAHE processed)"
puts "  • Review waveforms for detailed analysis"
puts ""
puts "Key Verification Points:"
puts "  ✓ Ping-pong flag toggles each frame"
puts "  ✓ CDF processing completes in frame gap"
puts "  ✓ First frame is bypass mode"
puts "  ✓ CLAHE enhancement starts from frame 1"
puts "  ✓ No black pixels (Y=0) in output"
puts "  ✓ Output Y values show enhancement"
puts ""
puts "Waveform organized by:"
puts "  • Clock & Control"
puts "  • Input/Output streams"
puts "  • Internal state machine"
puts "  • Coordinate & tile tracking"
puts "  • Histogram statistics"
puts "  • CDF processing"
puts "  • Pixel mapping (key signals)"
puts "  • BMP saving status"
puts "========================================"
puts ""

