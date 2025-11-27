# 16tile 仿真目录说明

- `bmp_in/`：测试 BMP 输入（供 `scripts/python` 转换流程调用）。
- `clahe_simple_dual_ram/`：仿真专用 RAM/IP 资源。
- `sim_outputs/`：如需临时导出，可在本地生成（仓库仅保留 `assets/images/` + `bmp_test_results/` 的最终样例）。
- `*.do / *.tcl`：ModelSim 驱动脚本，入口依旧为 `run_all.do`。
- `*.py`：辅助分析脚本（像素统计、PingPong 检查等）。
- `modelsim.ini`：本地仿真配置（未入库，按需复制）。
- **生成物**：波形、日志、wlft/work 等请在本地调试后及时删除，不纳入 Git。
