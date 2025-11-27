#!/bin/bash
# ==============================================================================
# CLAHE BMP仿真脚本 - VCS版本
# 
# 功能说明：
#   - 使用VCS仿真器编译和运行CLAHE仿真
#   - 支持易灵思IP核
#   - 生成波形文件
#
# 使用方法：
#   chmod +x sim_clahe_vcs.sh
#   ./sim_clahe_vcs.sh
#
# ==============================================================================

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  CLAHE BMP仿真 - VCS版本${NC}"
echo -e "${GREEN}============================================${NC}"

# 检查VCS是否安装
if ! command -v vcs &> /dev/null; then
    echo -e "${RED}错误: VCS未找到，请确保VCS已正确安装并配置环境变量${NC}"
    exit 1
fi

# 清理旧文件
echo -e "${YELLOW}清理旧的仿真文件...${NC}"
rm -rf csrc simv* ucli.key *.log *.vpd DVEfiles work

# 编译设计
echo -e "${YELLOW}编译设计文件...${NC}"
vcs -full64 \
    -sverilog \
    +v2k \
    -timescale=1ns/100ps \
    +define+SIM \
    +define+SIM_MODE \
    +define+EFX_SIM \
    -debug_access+all \
    -lca \
    -kdb \
    +vcs+fsdbon \
    +vcs+dumparrays \
    -f flist_clahe.f \
    -l compile.log

if [ $? -ne 0 ]; then
    echo -e "${RED}编译失败，请检查 compile.log${NC}"
    exit 1
fi

echo -e "${GREEN}编译成功！${NC}"

# 运行仿真
echo -e "${YELLOW}运行仿真...${NC}"
echo -e "${YELLOW}注意：仿真时间较长，请耐心等待...${NC}"

./simv +vcs+finish+500000000 -l sim.log

if [ $? -ne 0 ]; then
    echo -e "${RED}仿真运行失败，请检查 sim.log${NC}"
    exit 1
fi

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  仿真完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}输出文件：${NC}"
echo -e "  - 波形文件: simv.vpd"
echo -e "  - 日志文件: sim.log"
echo -e "  - BMP输出: bmp_test_results/"
echo -e "${GREEN}============================================${NC}"
echo -e "${YELLOW}查看波形: dve -vpd simv.vpd &${NC}"




