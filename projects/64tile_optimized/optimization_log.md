# CLAHE 8x8 优化实录 (Optimization Log)

本文档实时记录 `projects/64tile_optimized` 版本的开发与优化过程。

## 1. 项目初始化 (Project Initialization)
- **时间**: 2025-12-06
- **源版本**: `projects/64tile`
- **目标**: 实现 8x8 分块 (64 tiles) 但仅使用 4 个 RAM Bank，以大幅降低 FPGA 资源消耗。

## 2. 核心架构变更 (Core Architecture Changes)
### 2.1 存储架构 (Memory Architecture)
- **原设计**: 64 Tiles -> 64 RAMs (Linear Scaling)
- **新设计**: 64 Tiles -> 4 RAM Banks (Hardware Folding N=16)
- **技术点**: 采用 VLSI DSP "Memory Interleaving" 技术，使用棋盘式映射解决并行读取冲突。

## 3. 实施记录 (Implementation Log)

### [Done] Step 1: 存储模块实现
- [x] 创建 `clahe_ram_banked.v`: 实现 4-Bank 物理存储逻辑与 Crossbar 路由 (2025-12-06 已完成)。

### [Done] Step 2: 顶层集成
- [x] 修改 `clahe_top.v`: 替换旧的 RAM 模块，实例化 `clahe_ram_banked` (2025-12-06 已完成)。

### [Done] Step 3: 子模块适配
- [x] `clahe_coord_counter.v`: 经验证已适配 160x90 分辨率与 6-bit index (无需修改)。
- [x] `clahe_histogram_stat.v` & `clahe_mapping_parallel.v`: 经验证接口已支持 6-bit Tile Index (无需修改)。

### [Todo] Step 4: 验证
- [ ] 运行 `tb_clahe_top.v` 验证基本功能。
- [ ] 确认资源使用量（预期 BRAM 减少）。
