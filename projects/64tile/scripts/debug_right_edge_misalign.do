# ==============================================================================
# ModelSim DO脚本：调试右侧边缘错位问题
# ==============================================================================

onerror {resume}

# 删除之前的波形
delete wave *

# 1. 顶层信号
add wave -divider "=== 顶层 ==="
add wave /tb_clahe_top/pclk
add wave /tb_clahe_top/in_href
add wave /tb_clahe_top/out_href

# 2. 坐标计数器
add wave -divider "=== 坐标 ==="
add wave -radix unsigned /tb_clahe_top/u_dut/coord_counter_inst/x_cnt
add wave -radix unsigned /tb_clahe_top/u_dut/coord_counter_inst/y_cnt
add wave -radix unsigned /tb_clahe_top/u_dut/coord_counter_inst/tile_x
add wave -radix unsigned /tb_clahe_top/u_dut/coord_counter_inst/tile_idx
add wave -radix unsigned /tb_clahe_top/u_dut/coord_counter_inst/local_x

# 3. Mapping输入
add wave -divider "=== Mapping输入 ==="
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/pixel_x
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/tile_idx
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/local_x_in
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/in_y

# 4. 四Tile索引
add wave -divider "=== 四Tile索引 ==="
add wave -radix decimal /tb_clahe_top/u_dut/mapping_inst/dx
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/tile_idx_tl
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/tile_idx_tr
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/tile_idx_bl
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/tile_idx_br

# 5. 插值权重
add wave -divider "=== 权重 ==="
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/wx
add wave -radix unsigned /tb_clahe_top/u_dut/mapping_inst/wy

# 6. CDF采样值（最重要！）
add wave -divider "=== CDF值 ==="
add wave -radix unsigned -color yellow /tb_clahe_top/u_dut/mapping_inst/cdf_tl_d2
add wave -radix unsigned -color yellow /tb_clahe_top/u_dut/mapping_inst/cdf_tr_d2
add wave -radix unsigned -color yellow /tb_clahe_top/u_dut/mapping_inst/cdf_bl_d2
add wave -radix unsigned -color yellow /tb_clahe_top/u_dut/mapping_inst/cdf_br_d2

# 7. 插值结果
add wave -divider "=== 插值 ==="
add wave -radix unsigned -color cyan /tb_clahe_top/u_dut/mapping_inst/interp_top
add wave -radix unsigned -color cyan /tb_clahe_top/u_dut/mapping_inst/interp_bottom
add wave -radix hex -color magenta /tb_clahe_top/u_dut/mapping_inst/final_interp

# 8. 输出
add wave -divider "=== 输出 ==="
add wave -radix unsigned -color red /tb_clahe_top/out_y
add wave /tb_clahe_top/out_href

# 9. 输出坐标
add wave -divider "=== 输出坐标 ==="
add wave -radix unsigned /tb_clahe_top/out_sx
add wave -radix unsigned /tb_clahe_top/out_sy

# 配置
configure wave -namecolwidth 300
configure wave -valuecolwidth 80
configure wave -signalnamewidth 1

echo "========================================"
echo "波形已加载！接下来："
echo "1. run 50ms"
echo "2. wave zoom full"
echo "3. 找out_sy=300的位置"
echo "4. 观察黄色CDF值是否异常"
echo "========================================"

update
