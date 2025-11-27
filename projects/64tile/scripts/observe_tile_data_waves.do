# ============================================================================
# CLAHE Tile数据详细观察脚本
#
# 功能描述:
#   - 专门观察特定tile的直方图数据
#   - 观察CDF计算过程中的数据变化
#   - 包含直方图缓冲区和CDF计算中间结果
#   - 适合深入分析算法实现
#
# 使用方法:
#   1. 在ModelSim中运行: do observe_tile_data_waves.do
#   2. 可以修改tile_idx来观察不同tile的数据
#
# 作者: Passionate.Z
# 日期: 2025-01-17
# ============================================================================

# 设置波形显示格式
config wave -signalnamewidth 200

# ============================================================================
# 1. 基础信号
# ============================================================================
add wave -divider "=== 基础控制信号 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/pclk \
    sim:/tb_clahe_top/rst_n \
    sim:/tb_clahe_top/in_vsync \
    sim:/tb_clahe_top/in_href

# ============================================================================
# 2. 当前处理的Tile信息
# ============================================================================
add wave -divider "=== 当前Tile信息 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/tile_cnt \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_tile_idx \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_tile_idx

# ============================================================================
# 3. 直方图读取过程
# ============================================================================
add wave -divider "=== 直方图读取过程 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/state \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/bin_cnt \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_bin_addr \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data_a \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data_b \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_rd_data

# ============================================================================
# 4. 直方图缓冲区数据（关键观察点）
# ============================================================================
add wave -divider "=== 直方图缓冲区 (hist_buf) ==="
# 显示前32个bin的数据（0-31）
for {set i 0} {$i < 32} {incr i} {
    add wave -position insertpoint -radix unsigned \
        sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_buf\[$i\]
}

# 显示中间32个bin的数据（112-143）
add wave -divider "=== 直方图缓冲区中间部分 (112-143) ==="
for {set i 112} {$i < 144} {incr i} {
    add wave -position insertpoint -radix unsigned \
        sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_buf\[$i\]
}

# 显示最后32个bin的数据（224-255）
add wave -divider "=== 直方图缓冲区尾部 (224-255) ==="
for {set i 224} {$i < 256} {incr i} {
    add wave -position insertpoint -radix unsigned \
        sim:/tb_clahe_top/u_dut/clipper_cdf_inst/hist_buf\[$i\]
}

# ============================================================================
# 5. Clip计算过程
# ============================================================================
add wave -divider "=== Clip计算过程 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/clip_limit \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/excess_total \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/excess_per_bin \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/clip_cnt

# ============================================================================
# 6. CDF计算过程
# ============================================================================
add wave -divider "=== CDF计算过程 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_acc \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_norm \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_cnt

# ============================================================================
# 7. CDF写入过程
# ============================================================================
add wave -divider "=== CDF写入过程 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_bin_addr \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_data \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_wr_en

# ============================================================================
# 8. 乒乓控制
# ============================================================================
add wave -divider "=== 乒乓控制 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/ping_pong_flag \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/ping_pong_flag

# ============================================================================
# 9. 处理状态
# ============================================================================
add wave -divider "=== 处理状态 ==="
add wave -position insertpoint  \
    sim:/tb_clahe_top/u_dut/frame_hist_done \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/processing \
    sim:/tb_clahe_top/u_dut/clipper_cdf_inst/cdf_done

# ============================================================================
# 10. 设置显示属性
# ============================================================================
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

# 显示波形窗口
view wave

# 输出提示信息
echo "=========================================="
echo "Tile数据详细观察脚本已加载"
echo "=========================================="
echo "观察重点："
echo "1. 直方图缓冲区的数据变化"
echo "2. Clip计算过程中的数据重分配"
echo "3. CDF累积计算过程"
echo "4. 归一化后的映射值"
echo "5. 不同tile的处理时序"
echo "=========================================="
echo "提示：可以修改脚本中的tile范围来观察不同区域的数据"
echo "=========================================="






