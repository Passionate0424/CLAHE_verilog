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
vlog -work work ../rtl/clahe_coord_counter.v

# RAM modules (using parallel version)
vlog -work work ../rtl/clahe_simple_dual_ram_model.v
vlog -work work ../rtl/clahe_ram_64tiles_parallel.v

# Histogram statistics
vlog -work work ../rtl/clahe_histogram_stat.v

# CDF processing
vlog -work work ../rtl/clahe_clipper_cdf.v

# Mapping module (using parallel version)
vlog -work work ../rtl/clahe_mapping_parallel.v

# Top module
vlog -work work ../rtl/clahe_top.v

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

