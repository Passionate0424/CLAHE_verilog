# full_sim 目录说明

- `bmp_in/`：整帧输入 BMP 数据。
- `bmp_test_results/`：批量仿真输出结果。
- `CLAHE/`、`tb/`、`ip/`：完整顶层 RTL 与测试平台。
- `sim_clahe_*.do/.sh`：不同 EDA 的驱动脚本。
- `flist_clahe.f`：文件清单。
- **生成物**：日志、波形、wlft*/work 仅在本地生成，调试完毕请删除，不纳入仓库。
