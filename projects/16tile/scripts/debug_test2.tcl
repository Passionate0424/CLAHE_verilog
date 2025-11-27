# ============================================================================
# ModelSim Debug Script for Test 2
# Purpose: Investigate why test2 has no CDF output
# ============================================================================

# 清理并重新编译
if {[file exists work]} {
    vdel -all
}
vlib work

# 编译源文件
vlog clahe_clipper_cdf.v
vlog tb/tb_clahe_clipper_cdf.v

# 启动仿真
vsim -voptargs=+acc tb_clahe_clipper_cdf

# 添加关键信号到波形
add wave -divider {Test Control}
add wave -radix unsigned /tb_clahe_clipper_cdf/test_count
add wave /tb_clahe_clipper_cdf/frame_hist_done
add wave /tb_clahe_clipper_cdf/ping_pong_flag

add wave -divider {DUT Status}
add wave /tb_clahe_clipper_cdf/u_dut/state
add wave /tb_clahe_clipper_cdf/u_dut/processing
add wave /tb_clahe_clipper_cdf/u_dut/cdf_done
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/tile_cnt
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/bin_cnt

add wave -divider {Histogram Read}
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_rd_tile_idx
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_rd_bin_addr
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_rd_data
add wave -radix unsigned /tb_clahe_clipper_cdf/hist_rd_data_a
add wave -radix unsigned /tb_clahe_clipper_cdf/hist_rd_data_b

add wave -divider {CDF Write Interface}
add wave /tb_clahe_clipper_cdf/u_dut/cdf_wr_en
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_wr_tile_idx
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_wr_bin_addr
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_wr_data

add wave -divider {Clip/CDF Calculation}
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/clip_limit
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/excess_total
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_min
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_max
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_range
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_temp

add wave -divider {CDF Array (first 16 bins for detailed view)}
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[0\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[1\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[2\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[3\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[4\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[5\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[6\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[7\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[8\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[9\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[10\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[254\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[255\]

add wave -divider {Histogram Clipped (first 8 bins)}
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[0\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[1\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[2\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[3\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[4\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[5\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[6\]
add wave -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[7\]

add wave -divider {Normalized Output Calculation Details}
add wave -radix unsigned -label {Output=(cdf[i]-cdf_min)*255/range} /tb_clahe_clipper_cdf/u_dut/cdf_wr_data
add wave -radix hex -label {cdf_value} /tb_clahe_clipper_cdf/u_dut/cdf\[0\]
add wave -radix hex -label {cdf_min} /tb_clahe_clipper_cdf/u_dut/cdf_min
add wave -radix hex -label {cdf_range} /tb_clahe_clipper_cdf/u_dut/cdf_range

add wave -divider {State Machine Flags}
add wave -label {State} /tb_clahe_clipper_cdf/u_dut/state
add wave -radix unsigned -label {BinCount} /tb_clahe_clipper_cdf/u_dut/bin_cnt

add wave -divider {RAM Data (tile 0 and 1)}
add wave -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[0]
add wave -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[1]
add wave -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[2]
add wave -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[256]
add wave -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[320]

# 配置波形显示
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# 运行到test 1结束
puts "Running to test 1 completion..."
run 1000us

# 运行到test 2结束
puts "Running through test 2..."
run 2000us

puts ""
puts "========================================"
puts "Debug Information Summary"
puts "========================================"
puts ""

# 检查test_count
set test_id [examine -radix unsigned /tb_clahe_clipper_cdf/test_count]
puts "Current test_count: $test_id"

# 检查CDF计算的关键值（tile 0）
puts ""
puts "CDF Calculation Debug (Tile 0):"
puts "========================================"

# 检查clipped直方图的前8个值
puts "hist_clipped values:"
for {set i 0} {$i < 8} {incr i} {
    set val [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/hist_clipped\[$i\]]
    puts "  hist_clipped\[$i\] = $val"
}

puts ""
puts "CDF array values:"
for {set i 0} {$i < 8} {incr i} {
    set val [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[$i\]]
    puts "  cdf\[$i\] = $val"
}

puts ""
puts "CDF normalization parameters:"
set cdf_min [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_min]
set cdf_max [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_max]
set cdf_range [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_range]
set cdf_temp [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf_temp]
puts "  cdf_min   = $cdf_min"
puts "  cdf_max   = $cdf_max"
puts "  cdf_range = $cdf_range"
puts "  cdf_temp  = $cdf_temp"

puts ""
puts "First CDF output calculation:"
if {$cdf_range > 0} {
    set cdf0 [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[0\]]
    set cdf1 [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[1\]]
    set cdf2 [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/cdf\[2\]]
    
    puts "  Formula: normalized = (cdf\[i\] - cdf_min) * 255 / cdf_range"
    puts ""
    puts "  For bin 0:"
    puts "    = ($cdf0 - $cdf_min) * 255 / $cdf_range"
    set numerator0 [expr {($cdf0 - $cdf_min) * 255}]
    puts "    = $numerator0 / $cdf_range"
    set result0 [expr {$numerator0 / $cdf_range}]
    puts "    = $result0"
    
    puts ""
    puts "  For bin 1:"
    puts "    = ($cdf1 - $cdf_min) * 255 / $cdf_range"
    set numerator1 [expr {($cdf1 - $cdf_min) * 255}]
    puts "    = $numerator1 / $cdf_range"
    set result1 [expr {$numerator1 / $cdf_range}]
    puts "    = $result1"
    
    puts ""
    puts "  For bin 2:"
    puts "    = ($cdf2 - $cdf_min) * 255 / $cdf_range"
    set numerator2 [expr {($cdf2 - $cdf_min) * 255}]
    puts "    = $numerator2 / $cdf_range"
    set result2 [expr {$numerator2 / $cdf_range}]
    puts "    = $result2"
    
    puts ""
    puts "  EXPECTED vs ACTUAL:"
    puts "    Bin 0: Expected=0,  Calculated=$result0"
    puts "    Bin 1: Expected=1,  Calculated=$result1"
    puts "    Bin 2: Expected=2,  Calculated=$result2"
    puts ""
    puts "  From testbench output, actual values are:"
    puts "    Bin 0: 40  (WRONG!)"
    puts "    Bin 1: 0   (Should be 1)"
    puts "    Bin 2: 1   (Should be 2)"
    puts ""
    puts "  >> This suggests a BIN ADDRESSING ERROR <<"
    puts "  >> The output is shifted/misaligned! <<"
}
puts "========================================"
puts ""

# 检查cdf_wr_en是否有效过
puts ""
puts "Checking if cdf_wr_en was ever active during test 2..."
puts "Please manually inspect the waveform between bookmarks:"
puts "  - Test2_Start"
puts "  - Test2_End"
puts ""

# 显示当前状态
set state [examine /tb_clahe_clipper_cdf/u_dut/state]
set tile [examine -radix unsigned /tb_clahe_clipper_cdf/u_dut/tile_cnt]
set processing [examine /tb_clahe_clipper_cdf/u_dut/processing]
set cdf_done [examine /tb_clahe_clipper_cdf/u_dut/cdf_done]

puts "Current DUT State:"
puts "  State      : $state"
puts "  Tile Count : $tile"
puts "  Processing : $processing"
puts "  CDF Done   : $cdf_done"
puts ""

# 检查tile 1的直方图数据
puts "Checking hist_ram_a for tile 1..."
set tile1_bin64 [examine -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[320]]
set tile1_bin128 [examine -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[384]]
puts "  Tile 1, Bin 64  : $tile1_bin64 (expected 1000)"
puts "  Tile 1, Bin 128 : $tile1_bin128 (expected 800)"
puts ""

# 检查tile 0的直方图数据（应该是0）
set tile0_bin0 [examine -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[0]]
set tile0_bin64 [examine -radix unsigned /tb_clahe_clipper_cdf/hist_ram_a[64]]
puts "Checking hist_ram_a for tile 0 (should be all zeros)..."
puts "  Tile 0, Bin 0   : $tile0_bin0 (expected 0)"
puts "  Tile 0, Bin 64  : $tile0_bin64 (expected 0)"
puts ""

puts "========================================"
puts "Please check the waveform viewer for:"
puts "1. Whether cdf_wr_en goes high during test 2"
puts "2. Which tiles are being processed (tile_cnt)"
puts "3. The state machine transitions"
puts "4. cdf_range value (if it's 0, write might be skipped)"
puts "========================================"
puts ""

# 缩放到test 2区域
wave zoom range 1000us 3000us

puts "Waveform zoomed to Test 2 region"
puts "Use GUI to inspect signals in detail"
puts ""
puts "========================================"
puts "WAVE ANALYSIS GUIDE"
puts "========================================"
puts ""
puts "Key Time Points to Check:"
puts "1. When state enters CALC_CDF (4'h4)"
puts "   - Watch cdf\[0-10\] being calculated"
puts "   - Watch cdf_temp incrementing"
puts "   - Watch cdf_min/max being updated"
puts ""
puts "2. When state enters WRITE_LUT (4'h5)"
puts "   - FIRST CYCLE: bin_cnt should be 0"
puts "   - Check cdf_wr_bin_addr = 0"
puts "   - Check cdf_wr_data value"
puts "   - Compare cdf\[0\] with cdf_min"
puts ""
puts "3. Look for the BUG:"
puts "   - If bin 0 outputs 40 instead of 0"
puts "   - Check if cdf\[bin_cnt\] is reading wrong index"
puts "   - Check if bin_cnt starts from wrong value"
puts "   - Check timing of cdf_wr_en vs bin_cnt"
puts ""
puts "Expected Pattern (Test 1):"
puts "  hist_clipped\[0-255\] should all be 56"
puts "  cdf\[0\]  = 56"
puts "  cdf\[1\]  = 112"
puts "  cdf\[2\]  = 168"
puts "  cdf_min  = 56"
puts "  cdf_max  = 14336"
puts "  cdf_range= 14280"
puts ""
puts "  normalized\[0\] = (56-56)*255/14280   = 0"
puts "  normalized\[1\] = (112-56)*255/14280  = 1"
puts "  normalized\[2\] = (168-56)*255/14280  = 2"
puts ""
puts "But actual output is: 40, 0, 1, 2..."
puts "This means something is OFFSET BY 1!"
puts "========================================"

