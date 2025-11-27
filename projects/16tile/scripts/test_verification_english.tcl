# English version verification test
cd sim

# Compile
vlog -work work ../clahe_*.v
vlog -work work ../tb/tb_clahe_top.v
vlog -work work ../tb/bmp_for_videoStream_24bit.sv

# Run simulation with English output
vsim -c work.tb_clahe_top

# Run for 2 frames
run 30ms

# Exit
quit -f



