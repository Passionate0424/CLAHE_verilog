# ==============================================================================
# CLAHE 仿真文件列表
# 
# 功能说明：
#   - 列出所有需要编译的源文件（按依赖顺序）
#   - 可用于各种仿真器（ModelSim, VCS, Xcelium等）
#   - 支持易灵思IP核仿真
#
# 使用方法：
#   ModelSim: vlog -f flist_clahe.f
#   VCS:      vcs -f flist_clahe.f
#   Xcelium:  xrun -f flist_clahe.f
#
# ==============================================================================

# 定义仿真宏
+define+SIM
+define+SIM_MODE
+define+EFX_SIM

# 时间尺度
-timescale=1ns/100ps

# ==============================================================================
# CLAHE核心源文件（按依赖顺序）
# ==============================================================================

# 1. RAM模型（最底层，无依赖）
CLAHE/clahe_true_dual_port_ram.v
CLAHE/clahe_simple_dual_ram_model.v

# 2. 坐标计数器（无依赖）
CLAHE/clahe_coord_counter.v

# 3. 易灵思IP核
ip/clahe_cdf_divider/clahe_cdf_divider.v
ip/clahe_simple_dual_ram/clahe_simple_dual_ram.v

# 4. 直方图统计模块（依赖RAM）
CLAHE/clahe_histogram_stat.v

# 5. CDF计算模块（依赖除法器IP、RAM）
CLAHE/clahe_clipper_cdf.v

# 6. 像素映射模块（依赖RAM）
CLAHE/clahe_mapping_parallel.v

# 7. 16块并行RAM架构（依赖RAM模型和IP核）
CLAHE/clahe_ram_16tiles_parallel.v

# 8. CLAHE顶层模块（依赖所有子模块）
CLAHE/CLAHE_top.v

# ==============================================================================
# Testbench文件
# ==============================================================================

# BMP处理模块（SystemVerilog）
-sv tb/bmp_to_videoStream.sv
-sv tb/bmp_for_videoStream_24bit.sv

# 主testbench
tb/tb_clahe_top_bmp_multi.v

# ==============================================================================
# 可选：波形转储
# ==============================================================================
# +define+DUMP_VCD
# +define+DUMP_FSDB




