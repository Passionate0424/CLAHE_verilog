# ============================================================================
# CLAHE BMP多帧测试仿真脚本
# 使用实际BMP图像进行连续多帧测试
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
puts "编译测试文件..."
puts "=========================================="

vlog -sv -work work tb/bmp_to_videoStream.sv
vlog -sv -work work tb/bmp_for_videoStream_24bit.sv
vlog -sv -work work tb/tb_clahe_top_bmp_multi.v

# 启动仿真
puts "=========================================="
puts "启动仿真..."
puts "=========================================="

vsim -voptargs=+acc work.tb_clahe_top_bmp_multi \
    -GENABLE_CLAHE=1 \
    -GENABLE_INTERP=1 \
    -GCLIP_THRESHOLD=200 \
    -GNUM_FRAMES=3

# 添加波形信号
puts "=========================================="
puts "添加波形信号..."
puts "=========================================="

# 添加时钟和复位
add wave -noupdate -divider "时钟与复位"
add wave -noupdate /tb_clahe_top_bmp_multi/pclk
add wave -noupdate /tb_clahe_top_bmp_multi/rst_n

# 添加BMP输入信号
add wave -noupdate -divider "BMP输入控制"
add wave -noupdate /tb_clahe_top_bmp_multi/bmp_begin
add wave -noupdate /tb_clahe_top_bmp_multi/bmp_in_done
add wave -noupdate /tb_clahe_top_bmp_multi/frame_count

# 添加BMP RGB数据
add wave -noupdate -divider "BMP RGB数据"
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/bmp_in_data
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/bmp_in_data(2)
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/bmp_in_data(1)
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/bmp_in_data(0)
add wave -noupdate /tb_clahe_top_bmp_multi/bmp_in_valid

# 添加CLAHE输入信号（YUV）
add wave -noupdate -divider "CLAHE输入（YUV）"
add wave -noupdate /tb_clahe_top_bmp_multi/in_href
add wave -noupdate /tb_clahe_top_bmp_multi/in_vsync
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/in_y
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/in_u
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/in_v

# 添加CLAHE输出信号（YUV）
add wave -noupdate -divider "CLAHE输出（YUV）"
add wave -noupdate /tb_clahe_top_bmp_multi/out_href
add wave -noupdate /tb_clahe_top_bmp_multi/out_vsync
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/out_y
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/out_u
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/out_v

# 添加CLAHE控制信号
add wave -noupdate -divider "CLAHE控制"
add wave -noupdate /tb_clahe_top_bmp_multi/clahe_enable
add wave -noupdate /tb_clahe_top_bmp_multi/interp_enable
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/clip_threshold

# 添加CLAHE内部状态
add wave -noupdate -divider "CLAHE内部状态"
add wave -noupdate /tb_clahe_top_bmp_multi/processing
add wave -noupdate /tb_clahe_top_bmp_multi/cdf_ready
add wave -noupdate /tb_clahe_top_bmp_multi/ping_pong_flag

# 添加输出RGB数据
add wave -noupdate -divider "输出RGB数据"
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/bmp_out_r
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/bmp_out_g
add wave -noupdate -radix unsigned /tb_clahe_top_bmp_multi/bmp_out_b

# 配置波形窗口
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
puts "运行仿真 (GUI模式，带波形记录)..."
puts "=========================================="

run -all

# 缩放波形以适应窗口
wave zoom full

puts "=========================================="
puts "仿真完成！波形已记录。"
puts "=========================================="
puts "提示：使用 'view wave' 查看波形窗口"
puts ""

# quit -f
