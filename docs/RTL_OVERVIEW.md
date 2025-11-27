# RTL 模块详解（16tile & 64tile 通用）

本说明覆盖 `projects/16tile/rtl/` 与 `projects/64tile/rtl/` 中的主干模块，车辆说明其算法原理、实现思路以及两种 tile 规模的差异，方便在统一文档体系下检索。

## 1. 模块总览

| 功能 | 16tile 文件 | 64tile 文件 | 说明 |
| --- | --- | --- | --- |
| 坐标计数/Tile 定位 | `clahe_coord_counter.v` | `clahe_coord_counter.v` | 统计像素坐标，输出 tile 与局部坐标 |
| 直方图统计 | `clahe_histogram_stat_v2.v` / `clahe_histogram_stat.v` | `clahe_histogram_stat.v` | 3 级流水线统计 + 冲突保护 |
| Clip + CDF | `clahe_clipper_cdf.v` | `clahe_clipper_cdf.v` | 帧间对直方图裁剪并生成 CDF LUT |
| 像素映射 | `clahe_mapping_parallel.v` | `clahe_mapping_parallel.v` | 并行读取 CDF，支持双线性插值 |
| RAM 框架 | `clahe_ram_16tiles_parallel.v` 等 | `clahe_ram_64tiles_parallel.v` 等 | 伪双端口 RAM 及仿真模型 |

> 注：16tile 工程保留了部分实验版文件（如 `_v2` / `_copy`），编译时仅实例化主版本；64tile 工程为最终流片参考实现。

---

## 2. `clahe_coord_counter.v` —— 像素坐标与 tile 索引

### 算法原理（坐标计数）

1. 依据输入同步信号 `in_href`/`in_vsync` 对 `x_cnt`、`y_cnt` 进行扫描计数。
2. 使用 `WIDTH/TILE_H_NUM`、`HEIGHT/TILE_V_NUM` 的整除关系快速定位 `tile_x`、`tile_y`，并计算 `tile_idx = tile_y * TILE_H_NUM + tile_x`。
3. 同时输出 `local_x/local_y`，供直方图统计与插值模块复用。

### 关键实现

- 以两个 always 块分别处理横/纵扫描与 tile/局部坐标，保证组合路径简单。
- 在 64tile 版本中 `tile_idx` 为 6bit，16tile 则为 4bit；通过参数化保持单一 RTL。
- 行结束、帧结束采用同步复位，避免跨时钟域。

### 16tile & 64tile 差异

| 项目 | 16tile | 64tile |
| --- | --- | --- |
| TILE_H_NUM / TILE_V_NUM | 4 × 4 | 8 × 8 |
| TILE 尺寸 | 320 × 180 | 160 × 90 |
| `tile_idx` 宽度 | 4 bit | 6 bit |
| 其他 | 参数保持一致 | 同上 |

---

## 3. `clahe_histogram_stat*.v` —— 直方图统计

### 流程概述（统计级联）

1. **Stage 1**：对输入像素和值进行打拍，同时记录 `tile_idx` 与前一像素是否重复。
2. **Stage 2**：从伪双端口 RAM 读取当前 bin 计数，并应用冲突/旁路逻辑以解决 `AA` 与 `ABA`（相邻/间隔重复）场景。
3. **Stage 3**：写回更新后的计数，同时发出清零/帧完成信号。

### 关键机制

- **Ping-Pong 架构**：`ping_pong_flag` 控制写入与 CDF 读取使用不同的 RAM 区域，保证统计与映射并行。
- **清零策略**：在 `vsync` 下降沿置 `clear_start`，由外部清零状态机执行全 bin 重置。
- **冲突处理**：
  - 相邻重复（AA）：一次写入 `+2`，减少冲突。
  - 间隔重复（ABA）：旁路上次写回的数据，避免脏读。
- **帧完成检测**：像素计数达到 `WIDTH × HEIGHT` 后拉高 `frame_hist_done`。

### 16tile 特殊文件

- `clahe_histogram_stat_v2.v`：针对 tile 缩减后的紧凑实现，读写地址更窄。
- `clahe_simple_dual_ram_model.v`：仿真时的 RAM 模型，便于波形观察。

---

## 4. `clahe_clipper_cdf.v` —— 对比度裁剪 + CDF 生成

### 处理流程（帧间阶段）

1. **触发**：等待 `frame_hist_done`，在帧间隙处理上一帧直方图。
2. **状态机**：
   - `READ_HIST`：扫描 256 个 bins 进入片内缓存。
   - `CLIP_SCAN` / `CLIP_REDIST`：执行 clip 限幅与溢出再分配。
   - `CALC_CDF`：累加统计值，同时进行归一化。
   - `WRITE_LUT`：将 0~255 的映射值写回 CDF LUT RAM。
   - `NEXT_TILE`：换下一个 tile，直至 64 块完成。
3. **Clip 计算**：`clip_limit = (tile_pixels / BINS) × clip_factor`，溢出量均分至所有 bins。
4. **CDF 归一化**：`cdf_norm = (cdf[i] × 255) / tile_pixels`，保障输出灰度范围一致。

### 实现亮点

- **双口读取**：A/B 口并行读取，以加快 256 bin 扫描。
- **流水与缓存**：读取后先缓存到阵列，再进行 clip，以减少 RAM 访问。
- **吞吐分析**：64 tile × 400 周期 ≈ 0.34ms@74MHz，远低于帧间隔。

---

## 5. `clahe_mapping_parallel.v` —— 像素映射与双线性插值

### 流水线流程（映射阶段）

1. **Tile 选择**：基于 `tile_idx` 与局部坐标决定 4 个邻近 tile（TL/TR/BL/BR），边界只读单 tile。
2. **CDF 读取**：一次性触发四个 LUT RAM，同时考虑 ping-pong 区域（`cdf_ready`）。
3. **流水线**：
   - Stage1：计算 `dx/dy`、四个 tile 索引。
   - Stage2：获取 4 个 CDF 值。
   - Stage3：横向插值 `top = lerp(TL, TR, dx)`，`bottom = lerp(BL, BR, dx)`。
   - Stage4：纵向插值得到最终亮度。
   - Stage5：与 U/V 通道对齐后输出。
4. **模式切换**：`interp_enable`=0 时退化为单 tile 查表；`clahe_enable`=0 时走 bypass。

### 实现要点

- **插值精度**：使用 8bit 输入、扩展到 16bit 计算再截断，确保平滑过渡。
- **延迟匹配**：对 U/V 通道加入 FIFO 以与 Y 通道输出同步。
- **异常处理**：`y_offset=0` 或 `x_offset=0` 时自动降级到 1 维插值。

---

## 6. RAM 体系

### 主存

- `clahe_ram_16tiles_parallel.v` / `clahe_ram_64tiles_parallel.v`：包装多块 BRAM，提供
  - A 口写（直方图统计） / B 口读（CDF 计算）
  - tile 维度寻址（tile_idx + bin）
  - Ping-pong bank 切换

### 真双口模型

- `clahe_ram_true_dual.v`、`clahe_true_dual_port_ram.v`：面向综合的真双口 RAM。
- `clahe_simple_dual_ram_model.v`：仿真模型，提供 `READ_FIRST` 行为，便于验证冲突逻辑。

### LUT RAM

- `clahe_ram_64tiles_parallel.v` 还用于存储 CDF LUT，映射阶段通过 tile×bin 地址读取。

---

## 7. 版本差异提示

| 维度 | 16tile | 64tile |
| --- | --- | --- |
| Tile 数 | 16 | 64 |
| Tile 大小 | 320×180 | 160×90 |
| RAM 需求 | 16×256×16bit | 128×256×16bit（伪双端口） |
| 直方图状态机 | `_v2` 版本以较小地址线优化 | 主分支版本，代码注释更完整 |
| 插值 | 默认开启（减少块效应） | 默认开启，支持并行读取四块 |

---

## 8. 参考建议

- 阅读顺序：`clahe_coord_counter` → `clahe_histogram_stat` → `clahe_clipper_cdf` → RAM → `clahe_mapping_parallel`。
- 建议使用 `projects/<variant>/tb/` 下的 testbench 对应模块逐一验证。
- 若需要扩展至其他分辨率，可先调整 `coord_counter` 与 Tile 参数，再逐层更新 RAM 深度与 clip_limit 计算。

如需英文说明，可在 `docs/` 目录中基于本文件翻译扩展。
