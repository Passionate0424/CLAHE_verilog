#!/bin/bash
# ==============================================================================
# CLAHE BMP仿真脚本 - Icarus Verilog版本
# 
# 功能说明：
#   - 使用开源Icarus Verilog仿真器
#   - 适用于没有商业仿真器的环境
#   - 生成VCD波形文件
#
# 使用方法：
#   chmod +x sim_clahe_iverilog.sh
#   ./sim_clahe_iverilog.sh
#
# 依赖：
#   - iverilog (安装: sudo apt install iverilog)
#   - gtkwave (查看波形: sudo apt install gtkwave)
#
# ==============================================================================

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  CLAHE BMP仿真 - Icarus Verilog版本${NC}"
echo -e "${GREEN}============================================${NC}"

# 检查iverilog是否安装
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}错误: iverilog未找到${NC}"
    echo -e "${YELLOW}安装方法: sudo apt install iverilog gtkwave${NC}"
    exit 1
fi

# 清理旧文件
echo -e "${YELLOW}清理旧的仿真文件...${NC}"
rm -f clahe_sim.vvp *.vcd

# 编译设计
echo -e "${YELLOW}编译设计文件...${NC}"
iverilog -g2012 \
    -DSIM -DSIM_MODE -DEFX_SIM \
    -o clahe_sim.vvp \
    -y CLAHE \
    -y ip/clahe_cdf_divider \
    -y ip/clahe_simple_dual_ram \
    -y tb \
    CLAHE/clahe_true_dual_port_ram.v \
    CLAHE/clahe_simple_dual_ram_model.v \
    CLAHE/clahe_coord_counter.v \
    ip/clahe_cdf_divider/clahe_cdf_divider.v \
    ip/clahe_simple_dual_ram/clahe_simple_dual_ram.v \
    CLAHE/clahe_histogram_stat.v \
    CLAHE/clahe_clipper_cdf.v \
    CLAHE/clahe_mapping_parallel.v \
    CLAHE/clahe_ram_16tiles_parallel.v \
    CLAHE/CLAHE_top.v \
    tb/bmp_to_videoStream.sv \
    tb/bmp_for_videoStream_24bit.sv \
    tb/tb_clahe_top_bmp_multi.v \
    2>&1 | tee compile.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}编译失败，请检查 compile.log${NC}"
    exit 1
fi

echo -e "${GREEN}编译成功！${NC}"

# 运行仿真
echo -e "${YELLOW}运行仿真...${NC}"
echo -e "${YELLOW}注意：仿真时间较长，请耐心等待...${NC}"

vvp clahe_sim.vvp | tee sim.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}仿真运行失败，请检查 sim.log${NC}"
    exit 1
fi

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  仿真完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}输出文件：${NC}"
echo -e "  - 波形文件: tb_clahe_top_bmp_multi.vcd"
echo -e "  - 日志文件: sim.log"
echo -e "  - BMP输出: bmp_test_results/"
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}查看波形: gtkwave tb_clahe_top_bmp_multi.vcd &${NC}"




