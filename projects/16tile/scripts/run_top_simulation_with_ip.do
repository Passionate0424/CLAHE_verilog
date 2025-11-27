# ============================================================================
# CLAHE 顶层仿真脚本 - 使用Efinix BRAM IP核
#
# 功能描述:
#   - 编译所有Efinix BRAM IP核支持文件
#   - 编译CLAHE设计文件
#   - 运行顶层仿真
#
# 使用方法:
#   vsim -do run_top_simulation_with_ip.do
#
# 作者: Passionate.Z
# 日期: 2025-10-25
# ============================================================================

# 创建工作库
vlib work

# ========================================================================
# 1. 编译Efinix BRAM IP核支持文件
# ========================================================================
echo "编译Efinix BRAM IP核支持文件..."

vlog -sv -timescale=1ns/1ps sim/clahe_simple_dual_ram/efx_ram_5k.v
vlog -sv -timescale=1ns/1ps sim/clahe_simple_dual_ram/efx_ram10.v
vlog -sv -timescale=1ns/1ps sim/clahe_simple_dual_ram/efx_dpram10.v
vlog -sv -timescale=1ns/1ps sim/clahe_simple_dual_ram/efx_dpram_5k.v

# ========================================================================
# 2. 编译Efinix BRAM IP核
# ========================================================================
echo "编译Efinix BRAM IP核..."

vlog -sv +define+SIMULATION sim/clahe_simple_dual_ram/clahe_simple_dual_ram.v

# ========================================================================
# 3. 编译CLAHE设计文件
# ========================================================================
echo "编译CLAHE设计文件..."

vlog -sv +define+SIMULATION clahe_coord_counter.v
vlog -sv +define+SIMULATION clahe_histogram_stat.v
vlog -sv +define+SIMULATION clahe_clipper_cdf.v
vlog -sv +define+SIMULATION clahe_mapping_parallel.v
vlog -sv +define+SIMULATION clahe_ram_64tiles_parallel.v
vlog -sv +define+SIMULATION clahe_top.v

# ========================================================================
# 4. 编译顶层Testbench
# ========================================================================
echo "编译顶层Testbench..."

vlog -sv +define+SIMULATION tb/bmp_for_videoStream_24bit.sv
vlog -sv +define+SIMULATION tb/tb_clahe_top.v

# ========================================================================
# 5. 启动仿真
# ========================================================================
echo "启动仿真..."

# 使用ns时间精度（比ps快100倍），使用优化模式但保持访问性
vsim -t ns +notimingchecks -voptargs="+acc" +nowarnTFMPC work.tb_clahe_top

# 添加波形
# add wave -position insertpoint sim:/tb_clahe_top/*

# 运行仿真
echo "运行仿真..."
run -all

echo "仿真完成！"

# 自动退出
quit -f

