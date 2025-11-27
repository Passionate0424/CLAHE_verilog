# CLAHE FPGA 项目说明

[English Guide](README_EN.md) | **当前语言：中文**

CLAHE（对比度受限自适应直方图均衡化）是一套面向实时视频增强的 FPGA 参考实现。本仓库收录了 **16 tile** 与 **64 tile** 两个版本的 RTL、testbench、仿真脚本、调试数据及完整的 Markdown 文档，便于学习、复现与二次开发。

## 项目概览

- **算法特性**：8×8 tile（64tile 版本）与 4×4/16 tile（16tile 版本）流水线架构，帧级乒乓统计+映射设计，支持 1280×720@30 fps。
- **实现状态**：RTL 及仿真已完成，配套脚本覆盖 ModelSim/Questa、VCS、Icarus Verilog，包含大量波形、日志与 BMP 样例。
- **文档体系**：每个版本下的 `docs/` 目录提供快速入门、架构说明、优化与变更记录，可作为项目交付或学习资料。

## 代码结构

```text
CLAHE/
├── README*.md                                 # 语言入口
├── projects/                                  # 各版本实现
│   ├── 16tile/                                # 16 tile 教学/验证版
│   └── 64tile/                                # 64 tile 主线版本
├── flows/
│   └── full_sim/                              # 跨 EDA 整帧仿真工程
└── assets/                                    # 顶层共享样例（如有）
```

> 提示：`projects/16tile/` 与 `projects/64tile/` 的 README 内容相似，重点在后者；若需对比演进，可阅读 `docs/ARCHITECTURE_UPDATE_NOTES.md`。

### 版本内部目录约定

- `rtl/`：所有 CLAHE RTL 模块，统一 `clahe_*.v` 命名。
- `tb/`：Testbench、额外 `.vcd/.view` 配置。
- `sim/`：仿真工程与 `modelsim.ini`。
- `scripts/`：`.do/.tcl/.py/.ps1` 辅助脚本。
- `assets/`：`images/`（最终输入/输出示例）与 `data/`（CDF/HEX/文本）。
- 其他零散报告统一收纳在 `docs/reports/`，图纸位于 `docs/assets/`。

## 快速开始

1. **安装依赖**
   - Mentor Graphics ModelSim/Questa 或其他支持的仿真器（`full_sim/sim_clahe_vcs.sh` / `sim_clahe_iverilog.sh`）。
   - Python 3（用于 `verify_cdf_golden.py` 等脚本）。
2. **选择版本**
   - 入门/教学：进入 `projects/16tile/`。
   - 完整功能：进入 `projects/64tile/`。
3. **阅读文档**
   - `docs/QUICKSTART.md`：5 分钟上手。
   - `docs/README.md`：架构与接口详细说明。
4. **运行仿真**

   ```bash
   cd projects/64tile/sim
   vsim -do run_all.do
   ```

   或使用 `flows/full_sim/sim_clahe_bmp.do` 进行整帧 BMP 输入测试。

## 文档导航

- `docs/README.md` & `docs/RTL_OVERVIEW.md`：主文档、快速入门、架构/实现更新记录、模块解析。
- `docs/reports/`：`CLAHE_BMP_IMAGE_DEBUG_REPORT.md`、`CLAHE_TIMING_FIXES_SUMMARY.md` 等专题报告。

## 仿真与测试

- `tb/`：覆盖核心模块与顶层的 testbench，附带参考波形 (`.vcd/.view`) 与 BMP 输出（位于各 `projects/*/tb/`）。
- `sim/`：ModelSim/Questa 的 `do`/`tcl` 脚本，支持批量回归（位于各 `projects/*/sim/`）。
- `flows/full_sim/`：面向整帧 BMP 数据的验证流，生成日志 `sim_log*.txt` 和输出图片。
- `verify_cdf_golden.py`：独立 Python 校验脚本，可与硬件结果对比。

## 数据与日志

- `assets/images/`、`bmp_test_results/`：保留最终输入/输出样本，便于复现。
- 日志、波形与 wlft/work 等缓存仅在本地生成调试，确认后请删除，不纳入版本控制。

## 贡献建议

- 若计划提交 Pull Request，请在 `projects/64tile/` 版本上进行，并同步更新 `docs/ARCHITECTURE_UPDATE_NOTES.md`。
- 新增脚本或数据集时，将说明文件置于对应目录（例如 `sim/README.md` 或 `docs/NEW_FEATURE.md`），保持结构清晰。

祝你在 CLAHE FPGA 项目中玩得开心！🚀
