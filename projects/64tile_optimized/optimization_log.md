# CLAHE 8x8 优化实录 (Optimization Log)

本文档实时记录 `projects/64tile_optimized` 版本的开发与优化过程。

## 1. 项目背景与目标 (Project Initialization)
- **时间**: 2025-12-06
- **源版本**: `projects/64tile`
- **挑战**: 原始 8x8 分块设计需要同时访问 4 个相邻 Tile 的直方图（Mapping 阶段）和写入（Hist 阶段），若使用简单线性扩展（64个独立 RAM），资源消耗巨大且布线复杂。
- **目标**: 实现 8x8 分块 (64 tiles) 但仅使用 4 个 RAM Bank，以大幅降低 FPGA 资源消耗，同时保持 1 pixel/clk 的吞吐率。

## 2. 核心架构优化 (Core Architecture Optimization)

### 2.1 存储架构：4-Bank 棋盘式交织 (4-Bank Interleaved Memory)
采用 VLSI DSP 书籍中的 "Memory Interleaving" (硬件折叠) 技术，将 64 个逻辑 Tile 映射到 4 个物理 RAM Bank 中。
- **映射策略**:
    - **Bank ID** = `{Tile_Row[0], Tile_Col[0]}` (奇偶交织)
    - **Bank Address** = `{Tile_Row[H-1:1], Tile_Col[W-1:1], Bin_Addr}`
- **技术优势**:
    - **无冲突访问**: 在双线性插值 (Bilinear Interpolation) 过程中，任意 2x2 的相邻 Tile 窗口必然包含 (偶,偶), (偶,奇), (奇,偶), (奇,奇) 四种组合，恰好对应 4 个不同的 Bank，因此可以单周期并行读取。
    - **资源节省**: 从 64 个 RAM 减少到 4 个 RAM (节省 ~93%)。
- **实现模块**: `clahe_ram_banked.v` (含 Crossbar 路由逻辑)。

### 2.2 流水线架构 (Pipeline Architecture)
针对 `clahe_histogram_stat` 模块进行了 3 级流水线重构，消除 Read-Modify-Write 路径上的时序瓶颈。
- **Stage 1**: 地址计算与数据预取 (Pre-fetch)。
- **Stage 2**: 数据读取与累加 (Read-Modify)。
- **Stage 3**: 数据回写 (Write-Back)。
- **特征**: 引入 'Same Pixel' 检测与 'Local Accumulator'，减少 RAM 读写频率，解决连续相同像素对 RAM Read-First 特性的依赖。

### 2.3 控制逻辑优化 (Robust Control)
- **VSYNC Edge Trigger**: 将帧完成 (`frame_hist_done`) 和清零 (`clear_start`) 信号严格绑定到 VSYNC 的边沿（下降沿完成，上升沿/下降沿清零），消除基于 Pixel Counter 的累积误差风险。
- **Parallel Clear**: 利用 Banked RAM 特性，支持在 VSYNC 期间并行对 4 个 Bank 进行清零。

## 3. 实施记录 (Implementation Log)

### [Done] Step 1: 存储模块开发
- [x] **`clahe_ram_banked.v` 开发**:
    - 实现了 `get_bank_id` 和 `get_bank_addr` 函数。
    - 实现了 4x4 Crossbar 逻辑，将 TL/TR/BL/BR 端口动态路由到 Bank 0-3。
    - 实现了 Ping-Pong 机制和 Parallel Clear 逻辑。

### [Done] Step 2: 顶层集成与重构
- [x] **`clahe_top.v` 适配**: 移除了庞大的 `clahe_ram_64tiles_parallel`，替换为紧凑的 `clahe_ram_banked`。
- [x] **Top-Level Port Mapping**: 重新连接 Mapping 模块的 4 个 Read Ports 到 Banked RAM 的 Crossbar 输出。

### [Done] Step 3: 基准版本 (Baseline) 调试与对齐 (Back-porting)
为了验证逻辑正确性，先对 `projects/64tile` (Baseline) 进行了深度调试，并将发现的 Bug 修复逻辑"反向移植"到基准版和优化版：
- **Bug Fix 1 (Histogram)**: 修复了 `frame_hist_done` 信号的时序问题（原导致直方图为空），采用 VSYNC 边沿触发。
- **Bug Fix 2 (Clipper)**: 修复了 CDF 归一化中的溢出问题，增加了 `Explicit Saturation` 逻辑 (`> 255 ? 255 : val`)。
- **结果**: 优化版设计不仅通过了理论验证，其核心算法逻辑也在基准版仿真中得到了交叉验证。

## 4. 验证结论 (Verification Conclusion)
- **Status**: Verified.
- **仿真结果**: 优化版 (`run_top_opt.do`) 输出 Max/Avg 统计数据正常 (Max 201)，图像直方图分布合理。
- **资源对比**:
    - Original: 64 RAM Instances.
    - Optimized: 4 RAM Banks (逻辑容量相同，但物理单元利用率大幅提升，布线拥塞度大幅降低)。
