# Simple CLAHE verification
cd sim

# Compile
vlog -work work ../clahe_*.v
vlog -work work ../tb/tb_clahe_top.v  
vlog -work work ../tb/bmp_for_videoStream_24bit.sv

# Run simulation with verification output
vsim -c work.tb_clahe_top -do "
    # Add verification signals to watch
    add wave -position insertpoint sim:/tb_clahe_top/u_dut/cdf_done
    add wave -position insertpoint sim:/tb_clahe_top/u_dut/frame_hist_done
    add wave -position insertpoint sim:/tb_clahe_top/u_dut/enable_clahe
    add wave -position insertpoint sim:/tb_clahe_top/total_frames
    
    # Run simulation
    run 50ms
    
    # Print verification summary
    echo \"=== CLAHE Verification Summary ===\"
    echo \"CDF Done: \" [examine -value sim:/tb_clahe_top/u_dut/cdf_done]
    echo \"Histogram Done: \" [examine -value sim:/tb_clahe_top/u_dut/frame_hist_done]
    echo \"CLAHE Enable: \" [examine -value sim:/tb_clahe_top/u_dut/enable_clahe]
    echo \"Total Frames: \" [examine -value sim:/tb_clahe_top/total_frames]
    echo \"=================================\"
    
    quit -f
"



