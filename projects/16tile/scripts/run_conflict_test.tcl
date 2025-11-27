# ============================================================================
# 直方图统计冲突处理测试脚本
# ============================================================================

# 清理之前的编译结果
quit -sim
vdel -all -lib work

# 创建工作库
vlib work

# 编译源文件
echo "编译源文件..."
vlog clahe_histogram_stat_v2.v

# 编译testbench
echo "编译testbench..."
vlog tb/tb_histogram_conflict_test.v

# 启动仿真
echo "启动仿真..."
vsim work.tb_histogram_conflict_test

# 添加波形
add wave -divider "输入信号"
add wave -radix unsigned /tb_histogram_conflict_test/in_y
add wave /tb_histogram_conflict_test/in_href
add wave -radix unsigned /tb_histogram_conflict_test/tile_idx

add wave -divider "流水线Stage 1"
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/pixel_s1
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/tile_s1
add wave /tb_histogram_conflict_test/u_hist_stat/valid_s1
add wave /tb_histogram_conflict_test/u_hist_stat/same_as_prev

add wave -divider "流水线Stage 2"
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/pixel_s2
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/tile_s2
add wave /tb_histogram_conflict_test/u_hist_stat/valid_s2
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/increment_s2

add wave -divider "流水线Stage 3"
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/pixel_s3
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/tile_s3
add wave /tb_histogram_conflict_test/u_hist_stat/valid_s3
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/ram_wr_data_s3

add wave -divider "旁路逻辑"
add wave /tb_histogram_conflict_test/u_hist_stat/conflict
add wave /tb_histogram_conflict_test/u_hist_stat/bypass_valid
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/bypass_data
add wave -radix unsigned /tb_histogram_conflict_test/u_hist_stat/selected_data

add wave -divider "RAM接口"
add wave -radix unsigned /tb_histogram_conflict_test/ram_rd_addr_b
add wave -radix unsigned /tb_histogram_conflict_test/ram_rd_data_b
add wave /tb_histogram_conflict_test/ram_wr_en_a
add wave -radix unsigned /tb_histogram_conflict_test/ram_wr_addr_a
add wave -radix unsigned /tb_histogram_conflict_test/ram_wr_data_a

add wave -divider "RAM模型"
add wave -radix unsigned /tb_histogram_conflict_test/ram_model(50)
add wave -radix unsigned /tb_histogram_conflict_test/ram_model(60)
add wave -radix unsigned /tb_histogram_conflict_test/ram_model(80)
add wave -radix unsigned /tb_histogram_conflict_test/ram_model(90)
add wave -radix unsigned /tb_histogram_conflict_test/ram_model(100)
add wave -radix unsigned /tb_histogram_conflict_test/ram_model(120)
add wave -radix unsigned /tb_histogram_conflict_test/ram_model(130)

# 运行仿真
echo "运行仿真..."
run -all

# 自动调整波形显示
wave zoom full

echo "仿真完成！"
echo "查看控制台输出查看测试结果"
echo "查看波形窗口查看详细时序"

