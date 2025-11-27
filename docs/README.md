# CLAHE 项目统一文档

本文件集中记录 `CLAHE` 仓库的目录结构、版本差异、仿真流程与常用脚本位置，取代 `projects/16tile` 与 `projects/64tile` 目录下的零散 Markdown。

## 1. 仓库结构

```text
CLAHE/
├── README*.md               # 语言入口
├── docs/README.md           # 本文件
├── projects/
│   ├── 16tile/              # 4×4/16 tile 教学实现
│   └── 64tile/              # 8×8/64 tile 主线实现
├── flows/
│   └── full_sim/            # 跨 EDA 整帧 BMP 仿真流程
└── assets/                  # 顶层共享样例（如有）
```

所有源代码、脚本与示例图像分别位于各项目的 `rtl/`、`tb/`、`sim/`、`scripts/`、`assets/` 子目录；临时日志与波形按需生成后即清理，不再提交。

## 2. 深入阅读

- **RTL 模块详解**：参见 `docs/RTL_OVERVIEW.md`，涵盖 `clahe_coord_counter`、`clahe_histogram_stat`、`clahe_clipper_cdf`、`clahe_mapping_parallel` 以及 RAM 体系的算法与实现差异。
- **脚本参考**：各项目 `scripts/` 中的 `.do/.tcl/.py` 已在注释中标明适用场景，可结合本文档的流程章节一起使用。

## 3. 共性开发流程

1. **安装仿真器**：支持 ModelSim/Questa、Synopsys VCS、Icarus Verilog。
2. **准备 Python 3**：用于 `scripts/verify_cdf_golden.py` 等黄金模型脚本。
3. **选择项目**：`projects/16tile`（学习/验证）或 `projects/64tile`（完整特性）。
4. **阅读源码**：`rtl/` 目录下的 `clahe_*.v` 模块按照统计 → 裁剪 → CDF → 映射 → 顶层顺序查看。
5. **运行仿真**：

   ```bash
   cd projects/<variant>/sim
   vsim -do run_all.do
   ```

   其他 `.do/.tcl` 脚本集中在 `projects/<variant>/scripts/`。
6. **查看结果**：`assets/images/`、`bmp_test_results/` 中保留最终输入/输出样例；波形、日志与 wlft/work 缓存默认不入库，如需调试请在本地生成。

## 4. 16tile 版本（projects/16tile）

- **定位**：教学与回归验证，tile 数量较少、资源占用低。
- **模块阅读顺序**：`rtl/clahe_coord_counter.v` → `rtl/clahe_histogram_stat.v` → `rtl/clahe_clipper_cdf.v` → `rtl/clahe_mapping_parallel.v` → `rtl/clahe_top.v`。
- **常用脚本**：
  - `scripts/run_conflict_test.tcl`：冲突场景回归。
  - `scripts/quick_test.tcl`：轻量级 sanity check。
  - `scripts/verify_output.py`：与黄金模型对比。
- **测试资源**：
  - `assets/images/`、`bmp_test_results/`：输入输出 BMP。
  - `tb/`：包含 `tb_clahe_top_bmp.v` 等完整 testbench。
  - 仿真日志/波形请按需生成后自行保留在本地。

## 5. 64tile 版本（projects/64tile）

- **定位**：面向 1280×720@30 fps 的 8×8 tile 主线实现，包含并行 RAM、双线性插值与全量验证。
- **模块阅读顺序**：同上；`rtl/clahe_ram_64tiles_parallel.v`、`rtl/clahe_simple_dual_ram_model.v` 给出 RAM 架构。
- **常用脚本**：
  - `scripts/run_top_simulation_with_ip.do`：集成 IP 的顶层仿真。
  - `scripts/debug_right_edge_misalign.do`：边界问题调试。
  - `scripts/verify_cdf_golden.py`：CDF 结果校验。
- **测试资源**：
  - `assets/images/`：`interp_input/output*.bmp`、对比 PNG。
  - `bmp_test_results/`：批量输入输出记录。
  - 其余波形/日志按需在本地生成后删除，避免污染主分支。

## 6. 整帧仿真流程（flows/full_sim）

- **用途**：以 BMP 流驱动两个项目的 RTL，兼容 ModelSim/Questa、VCS、Icarus。
- **脚本**：
  - `sim_clahe_bmp.do`：ModelSim 驱动。
  - `sim_clahe_vcs.sh`、`sim_clahe_iverilog.sh`：命令行批仿脚本。
- **输入输出**：
  - `bmp_in/`：原始测试图。
  - `bmp_test_results/`：仿真结果。
  - `sim_log*.txt`：运行日志。

## 7. 数据与清理

- `assets/images/`：示例图像，可用于 README/演示。
- `assets/data/`：`cdf_input_data.txt`、`test_input.hex` 等表格/激励。
- `bmp_test_results/`：完整帧输入/输出集合，仅保留最终可共享版本。
- 波形、日志、wlft*/work 等缓存一律视为本地产物，调试完成后请删除或加入 `.gitignore` 中的临时规则，不要提交到仓库。

## 8. 提交与贡献

- 所有文档更新集中在 `docs/README.md`。
- 若修改 RTL/脚本，请同步在提交信息中说明影响的项目（16tile 或 64tile）。
- 建议在 `projects/64tile` 上开发新特性，并运行 `sim/run_all.do` + `flows/full_sim` 全流程验证。

如需英文说明，可基于此文件再衍生英文版；若需要更多章节，请直接在 `docs/` 目录新增 Markdown 并在本文件中引用。
