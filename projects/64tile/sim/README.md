# 64tile 仿真目录说明

- `clahe_simple_dual_ram/`：仿真专用 RAM/IP 资源。
- `sim_outputs/`：如需临时导出，可在本地生成（仓库仅保留 `assets/images/` / `bmp_test_results/`）。
- `*.do / *.tcl`：ModelSim/Questa 驱动脚本，默认入口 `run_all.do`。
- `*.py`：辅助调试脚本（CDF 校验、tile 一致性检查等）。
- `modelsim.ini`：仿真器本地配置（未纳入仓库）。
- **生成物**：波形、日志、wlft*/work 等请在本地调试后删除，避免进入 Git。
