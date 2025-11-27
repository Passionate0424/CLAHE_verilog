# ============================================================================
# CLAHE 64块RAM架构仿真脚本
#
# 功能描述:
#   - 编译64块RAM架构的所有模块
#   - 运行测试验证并行清零功能
#   - 验证性能提升效果
#
# 使用方法:
#   - 在ModelSim中执行: do run_64tiles.do
#   - 或者命令行: vsim -c -do "do run_64tiles.do; quit"
#
# 作者: Passionate.Z
# 日期: 2025-10-17
# ============================================================================

# 设置工作目录
cd E:/2025FPGA_GAME/workspace/CLAHE/sim

# 清理之前的工作
if {[file exists work]} {
    vdel -lib work -all
}

# 创建工作库
vlib work
vmap work work

# 编译所有模块
echo "Compiling CLAHE 64-tiles architecture..."

# 编译基础模块
vlog ../clahe_coord_counter.v
vlog ../clahe_ram_64tiles.v
vlog ../clahe_histogram_stat_64tiles.v
vlog ../clahe_top_64tiles.v

# 编译测试模块
vlog ../tb/tb_clahe_64tiles.v

echo "Compilation completed successfully!"

# 启动仿真
echo "Starting simulation..."
vsim -c work.tb_clahe_64tiles

# 运行测试
echo "Running tests..."
run -all

# 显示结果
echo "Test completed!"
echo "=========================================="
echo "CLAHE 64-tiles RAM architecture test results:"
echo "=========================================="

# 退出仿真
quit
