# CLAHE 64-Tile Optimized Version

This directory contains the **Optimized 8x8 (64-tile)** implementation of CLAHE.

**Key Optimization:**
- **4-Bank Interleaved Memory**: Maps 64 logical tiles to 4 physical RAM banks using hardware folding and checkerboard interleaving.
- **Resource Efficiency**: Saves ~93% BRAM compared to linear implementation.
- **High Throughput**: Maintains 1 pixel/cycle performance.

See `optimization_log.md` for real-time development details. `docs/README.md`，此处不再维护独立文档。

## 快速索引

- 统一文档：`../../docs/README.md`
- 源码：`rtl/clahe_*.v`
- 仿真：`sim/run_all.do`
- 脚本：`scripts/`
- 插值/调试样例：`assets/`（保留的输入输出 BMP 与对比图）
- 其他仿真生成物：按需在本地生成/清理，不进入版本库

如需描述 64tile 特有内容，请在 `docs/README.md` 中补充章节。
