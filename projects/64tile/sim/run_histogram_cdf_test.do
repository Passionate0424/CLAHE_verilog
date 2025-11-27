# ============================================================================
# CLAHE Histogram和CDF模块完整测试脚本
#
# 功能描述:
#   - 自动编译和运行仿真
#   - 加载波形观察脚本
#   - 运行指定时间的仿真
#   - 适合完整的调试流程
#
# 使用方法:
#   1. 在ModelSim中运行: do run_histogram_cdf_test.do
#   2. 脚本会自动完成编译、仿真、波形加载的全过程
#
# 作者: Passionate.Z
# 日期: 2025-01-17
# ============================================================================

# 清理工作空间
vdel -lib work -all

# 创建库
vlib work
vmap work work

# ============================================================================
# 编译源文件
# ============================================================================
echo "开始编译源文件..."

# 编译基础模块
vlog -work work ../clahe_coord_counter.v
vlog -work work ../clahe_histogram_stat.v
vlog -work work ../clahe_clipper_cdf.v
vlog -work work ../clahe_ram_64tiles_parallel.v
vlog -work work ../clahe_mapping_parallel.v
vlog -work work ../clahe_top.v
vlog -work work ../clahe_simple_dual_ram.v

# 编译测试平台
vlog -work work ../tb/tb_clahe_top.v
vlog -work work ../tb/bmp_for_videoStream_24bit.sv

echo "编译完成！"

# ============================================================================
# 启动仿真
# ============================================================================
echo "启动仿真..."

# 启动仿真（使用优化选项）
vsim -voptargs=+acc work.tb_clahe_top

# ============================================================================
# 加载波形观察脚本
# ============================================================================
echo "加载波形观察脚本..."

# 设置波形显示格式
config wave -signalnamewidth 200
config wave -timelineunits ns

# ============================================================================
# 1. 全局时钟和复位信号
# ============================================================================
add wave -divider "=== 全局控制信号 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/pclk \
    sim:/tb_clahe_top/rst_n

# ============================================================================
# 2. 输入视频信号
# ============================================================================
add wave -divider "=== 输入视频信号 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/in_vsync \
    sim:/tb_clahe_top/in_href \
    sim:/tb_clahe_top/in_y

# ============================================================================
# 3. 直方图统计模块信号
# ============================================================================
add wave -divider "=== 直方图统计模块 (hist_stat_inst) ==="

# 控制信号
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ping_pong_flag \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/clear_start \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/clear_done \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/frame_hist_done

# 坐标和tile信息
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/tile_idx \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ram_rd_tile_idx \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ram_wr_tile_idx

# RAM接口信号
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ram_wr_addr_a \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ram_wr_data_a \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ram_wr_en_a \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ram_rd_addr_b \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/ram_rd_data_b

# 内部信号（使用实际存在的信号名称）
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/clear_busy \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/clear_addr

# 流水线信号
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/pixel_d1 \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/pixel_d2 \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/pixel_d3 \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/tile_idx_d1 \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/tile_idx_d2 \
    sim:/tb_clahe_top/u_dut/hist_stat_inst/tile_idx_d3

# ============================================================================
# 4. CDF计算模块信号
# ============================================================================
add wave -divider "=== CDF计算模块 (clipper_cdf_inst) ==="

# 控制信号
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/frame_hist_done \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/clip_limit \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/ping_pong_flag \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_done \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/processing

# 直方图读取接口
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_tile_idx \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_bin_addr \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data_a \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data_b

# CDF写入接口
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_tile_idx \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_bin_addr \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_data \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_en

# 内部状态机（使用实际存在的信号名称）
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/state \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/tile_cnt \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/bin_cnt

# Clip计算相关信号
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/excess_total \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/excess_per_bin

# CDF计算相关信号
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_min \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_max \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_range

# ============================================================================
# 5. RAM模块接口信号
# ============================================================================
add wave -divider "=== RAM模块接口信号 ==="

# 直方图统计RAM接口
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/hist_rd_tile_idx \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/hist_wr_tile_idx \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/hist_wr_addr \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/hist_wr_data \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/hist_wr_en \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/hist_rd_addr \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/hist_rd_data

# CDF RAM接口
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/cdf_tile_idx \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/cdf_addr \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/cdf_wr_data \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/cdf_wr_en \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/cdf_rd_en \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/cdf_rd_data

# 乒乓控制
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/ping_pong_flag \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/clear_start \
    sim:/tb_clahe_top/u_dut/ram_64tiles_inst/clear_done

# ============================================================================
# 6. 顶层控制信号
# ============================================================================
add wave -divider "=== 顶层控制信号 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/ping_pong_flag \
    sim:/tb_clahe_top/u_dut/hist_clear_start \
    sim:/tb_clahe_top/u_dut/hist_clear_done \
    sim:/tb_clahe_top/u_dut/frame_hist_done \
    sim:/tb_clahe_top/u_dut/cdf_processing \
    sim:/tb_clahe_top/u_dut/cdf_done

# ============================================================================
# 7. 输出信号
# ============================================================================
add wave -divider "=== 输出信号 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/out_vsync \
    sim:/tb_clahe_top/out_href \
    sim:/tb_clahe_top/out_y

# ============================================================================
# 8. 设置波形显示属性
# ============================================================================

# 设置信号显示格式
configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# 设置时间轴
configure wave -gridperiod 1000ns
configure wave -griddelta 100ns

# 设置波形显示范围
configure wave -timelineunits ns
configure wave -timeline 0

# 显示波形窗口
view wave

echo "波形观察脚本已加载完成！"
echo "修复内容："
echo "- 使用正确的信号名称"
echo "- 移除了不存在的信号（如state、clear_cnt）"
echo "- 添加了实际存在的内部信号"
echo "- 按功能分组显示波形"

# ============================================================================
# 运行仿真
# ============================================================================
echo "开始运行仿真..."

# 运行仿真（可以根据需要调整时间）
# 运行50ms，大约包含1-2帧的处理
run 50ms

# 或者运行更长时间进行完整测试
# run 200ms

echo "仿真完成！"

# ============================================================================
# 输出提示信息
# ============================================================================
echo "=========================================="
echo "CLAHE Histogram和CDF模块测试完成"
echo "=========================================="
echo "测试内容："
echo "1. 直方图统计模块功能验证"
echo "2. CDF计算模块功能验证"
echo "3. RAM读写时序验证"
echo "4. 乒乓操作验证"
echo "5. 完整处理流程验证"
echo "=========================================="
echo "波形观察要点："
echo "- 观察直方图统计的流水线处理"
echo "- 观察CDF计算的状态机转换"
echo "- 观察RAM读写的数据流"
echo "- 观察乒乓操作的时序"
echo "- 观察关键控制信号的时序关系"
echo "=========================================="
echo "如需观察更详细的Tile数据，请运行："
echo "do observe_tile_data_waves.do"
echo "=========================================="
