# 测试CLAHE验证功能
cd sim

# 编译
vlog -work work ../clahe_*.v
vlog -work work ../tb/tb_clahe_top.v
vlog -work work ../tb/bmp_for_videoStream_24bit.sv

# 仿真 - 运行1帧进行验证
vsim -c work.tb_clahe_top

# 运行仿真
run 30ms

# 退出
quit -f



