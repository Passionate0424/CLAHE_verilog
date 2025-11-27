# ============================================================================
# 完整的编译、运行和波形观察脚本
# ============================================================================

# 清理之前的编译结果
if {[file exists work]} {
    vdel -all -lib work
}

# 创建工作库
vlib work
vmap work work

# 编译设计文件
puts "=========================================="
puts "编译CLAHE设计文件..."
puts "=========================================="

vlog -sv -work work clahe_coord_counter.v
vlog -sv -work work clahe_histogram_stat.v
vlog -sv -work work clahe_true_dual_port_ram.v
vlog -sv -work work clahe_simple_dual_ram_model.v
vlog -sv -work work clahe_ram_16tiles_parallel.v
vlog -sv -work work clahe_clipper_cdf.v
vlog -sv -work work clahe_mapping_parallel.v
vlog -sv -work work clahe_top.v

# 编译测试文件
puts "=========================================="
puts "编译测试文件 (tb_clahe_top_bmp_multi - BMP版本)..."
puts "=========================================="

vlog -sv -work work tb/bmp_to_videoStream.sv
vlog -sv -work work tb/bmp_for_videoStream_24bit.sv
vlog -sv -work work tb/tb_clahe_top_bmp_multi.v

# 启动仿真（使用 vopt 保持调试可见性）
puts "=========================================="
puts "启动仿真 (tb_clahe_top_bmp_multi - BMP版本)..."
puts "=========================================="

# 先优化设计，保留调试信息
vopt +acc work.tb_clahe_top_bmp_multi -o tb_clahe_top_bmp_multi_opt

# 启动优化后的设计
vsim work.tb_clahe_top_bmp_multi_opt \
    -GENABLE_CLAHE=1 \
    -GENABLE_INTERP=1 \
    -GCLIP_THRESHOLD=600 \
    -GNUM_FRAMES=1

# 添加波形信号
puts "=========================================="
puts "添加波形信号..."
puts "=========================================="

# 添加时钟和复位
add wave -noupdate -divider "Clock and Reset"
add wave -noupdate /tb_clahe_top_bmp_multi/pclk
add wave -noupdate /tb_clahe_top_bmp_multi/rst_n

# 添加帧控制
add wave -noupdate -divider "BMP Control"
add wave -noupdate /tb_clahe_top_bmp_multi/bmp_begin
add wave -noupdate /tb_clahe_top_bmp_multi/bmp_in_done
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/frame_count

# 添加输入控制信号
add wave -noupdate -divider "Input Control"
add wave -noupdate /tb_clahe_top_bmp_multi/in_href
add wave -noupdate /tb_clahe_top_bmp_multi/in_vsync
add wave -noupdate /tb_clahe_top_bmp_multi/clahe_enable
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/clip_threshold

# 添加输入/输出YUV数据
add wave -noupdate -divider "YUV Data"
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/in_y
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/out_y
add wave -noupdate /tb_clahe_top_bmp_multi/out_href
add wave -noupdate /tb_clahe_top_bmp_multi/out_vsync

# 添加CDF处理状态信号（关键！）- 从DUT内部访问
add wave -noupdate -divider "CDF Processing Status - KEY"
add wave -noupdate -color "Orange" /tb_clahe_top_bmp_multi/u_dut/cdf_processing
add wave -noupdate -color "Green" /tb_clahe_top_bmp_multi/u_dut/cdf_done
add wave -noupdate /tb_clahe_top_bmp_multi/u_dut/ping_pong_flag
add wave -noupdate /tb_clahe_top_bmp_multi/u_dut/frame_hist_done

# 添加坐标计数器 - 用于诊断
add wave -noupdate -divider "Coordinate Counter"
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/u_dut/coord_counter_inst/x_cnt
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/u_dut/coord_counter_inst/y_cnt

# 配置波形显示
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# 运行仿真
puts "=========================================="
puts "运行仿真 (tb_clahe_top - 正常版本)..."
puts "=========================================="
puts "关键观察点："
puts "  1. processing - 应该在每帧结束后变为1"
puts "  2. cdf_ready - 应该在CDF处理完成后变为1"
puts "  3. ping_pong_flag - 应该在帧之间切换"
puts "  4. 对比: in_y vs out_y"
puts "=========================================="

# 运行前几帧（不要运行全部）
run 50ms

# 缩放波形
wave zoom full

puts "=========================================="
puts "仿真完成！请在波形窗口中观察关键信号。"
puts "=========================================="

