# English CLAHE Verification Test
cd sim

# Clean and compile
vlog -work work ../clahe_*.v
vlog -work work ../tb/tb_clahe_top.v  
vlog -work work ../tb/bmp_for_videoStream_24bit.sv

# Run simulation
vsim -c work.tb_clahe_top -do "run 50ms; quit -f"



