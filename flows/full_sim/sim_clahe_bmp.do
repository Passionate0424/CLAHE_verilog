# ==============================================================================
# CLAHE BMP仿真脚本 - 支持易灵思IP核
# 
# 功能说明：
#   - 编译CLAHE所有源代码
#   - 编译易灵思IP核（除法器、RAM）
#   - 编译testbench和BMP处理模块
#   - 运行BMP图像处理仿真
#
# 使用方法：
#   1. 确保bmp_in目录下有测试图像文件
#   2. 在ModelSim/Questa中运行: do sim_clahe_bmp.do
#   3. 仿真结果保存在bmp_test_results目录
#
# 作者: Passionate.Z
# 日期: 2025-11-01
# ==============================================================================

# 错误时退出
onerror {quit -f}

# 删除旧的工作库并创建新的
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# ==============================================================================
# 定义编译选项
# ==============================================================================
# SIM: 仿真模式标志
# SIM_MODE: 仿真模式类型
# EFX_SIM: 易灵思仿真标志
set DEFINE_OPTS "+define+SIM=1+SIM_MODE=1+EFX_SIM=1"

echo "============================================"
echo "  开始编译CLAHE源代码"
echo "============================================"

# ==============================================================================
# 编译CLAHE源代码（按依赖顺序）
# ==============================================================================

# 1. RAM模型（最底层）
echo "编译 RAM模型..."
vlog $DEFINE_OPTS CLAHE/clahe_true_dual_port_ram.v
vlog $DEFINE_OPTS CLAHE/clahe_simple_dual_ram_model.v

# 2. 坐标计数器（无依赖）
echo "编译 坐标计数器..."
vlog $DEFINE_OPTS CLAHE/clahe_coord_counter.v

# 3. IP核文件
echo "============================================"
echo "  编译易灵思IP核"
echo "============================================"

# 3.1 除法器IP核（用于CDF归一化）
echo "编译 除法器IP核..."
vlog $DEFINE_OPTS ip/clahe_cdf_divider/Testbench/clahe_cdf_divider.v

# 3.2 简单双端口RAM IP核（用于16块RAM_B）- 需要编译仿真原语
echo "编译 简单双端口RAM IP核及仿真原语..."
vlog -timescale=1ns/1ps $DEFINE_OPTS ip/clahe_simple_dual_ram/Testbench/efx_ram_5k.v
vlog -timescale=1ns/1ps $DEFINE_OPTS ip/clahe_simple_dual_ram/Testbench/efx_ram10.v
vlog -timescale=1ns/1ps $DEFINE_OPTS ip/clahe_simple_dual_ram/Testbench/efx_dpram10.v
vlog -timescale=1ns/1ps $DEFINE_OPTS ip/clahe_simple_dual_ram/Testbench/efx_dpram_5k.v
vlog $DEFINE_OPTS ip/clahe_simple_dual_ram/Testbench/clahe_simple_dual_ram.v

# 4. 直方图统计模块（依赖RAM）
echo "编译 直方图统计模块..."
vlog $DEFINE_OPTS CLAHE/clahe_histogram_stat.v

# 5. CDF计算模块（依赖除法器IP、RAM）
echo "编译 CDF计算模块..."
vlog $DEFINE_OPTS CLAHE/clahe_clipper_cdf.v

# 6. 像素映射模块（并行读取版本）
echo "编译 像素映射模块..."
vlog $DEFINE_OPTS CLAHE/clahe_mapping_parallel.v

# 7. 16块并行RAM架构（依赖RAM模型和IP核）
echo "编译 16块并行RAM架构..."
vlog $DEFINE_OPTS CLAHE/clahe_ram_16tiles_parallel.v

# 8. CLAHE顶层模块（依赖所有子模块）
echo "编译 CLAHE顶层模块..."
vlog $DEFINE_OPTS CLAHE/CLAHE_top.v

# ==============================================================================
# 编译Testbench文件
# ==============================================================================
echo "============================================"
echo "  编译Testbench文件"
echo "============================================"

# BMP处理模块（SystemVerilog）
echo "编译 BMP转视频流模块..."
vlog -sv $DEFINE_OPTS tb/bmp_to_videoStream.sv

echo "编译 视频流转BMP模块..."
vlog -sv $DEFINE_OPTS tb/bmp_for_videoStream_24bit.sv

# 主testbench（Verilog）
echo "编译 主Testbench..."
vlog $DEFINE_OPTS tb/tb_clahe_top_bmp_multi.v

# ==============================================================================
# 启动仿真
# ==============================================================================
echo "============================================"
echo "  启动仿真"
echo "============================================"

# 仿真参数说明：
#   -t ns: 时间单位为纳秒
#   -voptargs=+acc: 优化选项，允许访问所有信号
#   -L work: 使用work库
vsim -t ns -voptargs=+acc work.tb_clahe_top_bmp_multi

# ==============================================================================
# 添加波形信号
# ==============================================================================
echo "添加波形信号..."

# 顶层信号
add wave -divider "顶层时钟和复位"
add wave -format logic /tb_clahe_top_bmp_multi/pclk
add wave -format logic /tb_clahe_top_bmp_multi/rst_n

# 输入信号
add wave -divider "输入信号"
add wave -format logic /tb_clahe_top_bmp_multi/in_href
add wave -format logic /tb_clahe_top_bmp_multi/in_vsync
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/in_y
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/in_u
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/in_v

# 输出信号
add wave -divider "输出信号"
add wave -format logic /tb_clahe_top_bmp_multi/out_href
add wave -format logic /tb_clahe_top_bmp_multi/out_vsync
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/out_y
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/out_u
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/out_v

# 控制信号
add wave -divider "控制信号"
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/clip_threshold
add wave -format logic /tb_clahe_top_bmp_multi/clahe_enable
add wave -format logic /tb_clahe_top_bmp_multi/interp_enable

# CLAHE内部状态
add wave -divider "CLAHE内部状态"
add wave -format logic /tb_clahe_top_bmp_multi/processing
add wave -format logic /tb_clahe_top_bmp_multi/cdf_ready
add wave -format logic /tb_clahe_top_bmp_multi/ping_pong_flag

# BMP读取状态
add wave -divider "BMP读取"
add wave -format logic /tb_clahe_top_bmp_multi/bmp_begin
add wave -format logic /tb_clahe_top_bmp_multi/bmp_in_done
add wave -format logic /tb_clahe_top_bmp_multi/bmp_in_valid
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/bmp_in_data

# 坐标计数器
add wave -divider "坐标计数器"
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/pixel_x
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/pixel_y
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/tile_idx

# 直方图写入信号
add wave -divider "直方图写入信号"
add wave -format logic /tb_clahe_top_bmp_multi/u_dut/hist_wr_en
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/hist_wr_data
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/u_dut/hist_wr_addr
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/hist_wr_tile_idx

# CDF从直方图读取信号
add wave -divider "CDF读取直方图"
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/clipper_cdf_inst/hist_rd_tile_idx
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/u_dut/clipper_cdf_inst/hist_rd_bin_addr
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/clipper_cdf_inst/hist_rd_data_a
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/clipper_cdf_inst/hist_rd_data_b

# CDF写入信号
add wave -divider "CDF写入信号"
add wave -format logic /tb_clahe_top_bmp_multi/u_dut/cdf_done
add wave -format logic /tb_clahe_top_bmp_multi/u_dut/cdf_wr_en
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/u_dut/cdf_wr_data
add wave -format literal -radix hex /tb_clahe_top_bmp_multi/u_dut/cdf_wr_addr
add wave -format literal -radix unsigned /tb_clahe_top_bmp_multi/u_dut/cdf_wr_tile_idx

# ==============================================================================
# 运行仿真
# ==============================================================================
echo "============================================"
echo "  开始运行仿真"
echo "============================================"
echo "注意：仿真时间较长，请耐心等待..."
echo ""

# 运行仿真直到结束（$stop）
run -all

echo ""
echo "============================================"
echo "  仿真完成"
echo "============================================"
echo "输出文件保存在: bmp_test_results/"
echo "  - 输入图像:  bmp_test_results/input/"
echo "  - 输出图像:  bmp_test_results/output/"
echo "============================================"

