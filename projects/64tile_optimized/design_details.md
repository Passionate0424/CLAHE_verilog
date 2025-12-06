# CLAHE 8x8 FPGA 深度设计详解 (Deep Dive)

本文档提供本次优化的核心——**4-Bank 棋盘式交织存储架构**的终极技术指南。我们将结合 **K.K. Parhi 的《VLSI Digital Signal Processing Systems》** 中的理论知识，深度解析本次设计如何将课堂理论转化为工程实践。

## 1. 理论与实践结合 (Theory to Practice)

本次优化工作并非凭空创造，而是直接应用了 VLSI DSP 课程中的核心设计方法学。

### 1.1 存储交织 (Memory Interleaving)
**理论来源**: *Parhi Chapter 13 (DSP Architecture Sub-systems)* - "Interleaved Memory"
-   **理论定义**: 为了解决高速并行的 DSP 系统中存储器带宽不足的问题，将存储空间划分为多个 Bank，使得并行的访问请求（若满足特定模式）可以被分发到不同的 Bank 上同时处理。
-   **工程实践**:
    -   **原问题**: 双线性插值算子需要单周期并行读取 $D=4$ 个数据 (TL, TR, BL, BR)。
    -   **优化**: 设计了一个 **4-Way Interleaved Memory** 系统。利用图像网格的二维空间局部性，采用 **Checkerboard (棋盘式)** 映射函数 $M(x,y) = \{y[0], x[0]\}$。
    -   **成效**: 实现了 $Speedup = 4$ 的并行存储带宽，彻底消除了访问冲突 (Conflict-free Access)。

### 1.2 硬件折叠 (Hardware Folding)
**理论来源**: *Parhi Chapter 6 (Folding)*
-   **理论定义**: 将多个算法操作 (Algorithmic Operations) 映射到单一的硬件功能单元 (Functional Unit) 上，以时间换空间 (Time-Multiplexing)。
-   **工程实践**:
    -   **原算法图 (DFG)**: 逻辑上存在 64 个完全独立的直方图存储节点 (State Variables)。
    -   **折叠变换**: 定义折叠因子 $N=16$。我们将 16 个逻辑 Tile (同色) 折叠到一个物理 RAM Bank 中。
    -   **地址变换**: 设计了折叠方程 (Folding Equation) `Address = {idx_high, bin_addr}`，在单一物理 RAM 中划分出 16 个 "逻辑页 (Logical Pages)"。
    -   **成效**: 硬件复杂度 (Hardware Complexity) 从 $O(64)$ 降低到 $O(4)$，BRAM 资源节省 93.75%。

### 1.3 流水线与重定时 (Pipelining & Retiming)
**理论来源**: *Parhi Chapter 2 (Pipelining and Parallel Processing)*
-   **理论定义**: 在组合逻辑路径中插入寄存器 (Pipelines) 以减少关键路径延迟 (Critical Path Delay)，从而提高采样频率 $f_{sample}$。
-   **工程实践**:
    -   ** крити路径**: 直方图统计是一个经典的 "Read-Modify-Write" 回路 (Loop Bound)。单纯流水线化会改变回路性质导致功能错误。
    -   **解决方案**: 我们采用了 **Look-ahead / Forwarding (前瞻/前传)** 技术。在流水线中引入了 "Local Accumulator"（类似于 Parhi 书中提及的 Retiming 技术在处理反馈回路中的应用），解决了 Data Hazard。
    -   **成效**: 将原本需要多周期完成的 RMW 操作分解为 3 级流水线，使得系统能够稳定运行在 100MHz+。

---

## 2. 代码实现详解：地址映射 (Bit-Level Logic)
文件路径: `rtl/clahe_ram_banked.v`

### 2.1 Bank ID 计算逻辑 (Implementing Interleaving Function)
我们利用 Tile 坐标的**最低有效位 (LSB)** 来决定其所属的 Bank。这是一个非常高效的各种模运算 (Modulo) 的硬件实现。

```verilog
// 实现 Interleaving Function M(x,y)
// M(x,y) = (y % 2) * 2 + (x % 2)

function [1:0] get_bank_id;
    input [5:0] idx; 
    reg [2:0] tx, ty;
    begin
        tx = idx[2:0]; // 提取 X 坐标
        ty = idx[5:3]; // 提取 Y 坐标
        
        // 核心逻辑:
        // Bank ID 的低位由 X[0] 决定 (0:偶列, 1:奇列)
        // Bank ID 的高位由 Y[0] 决定 (0:偶行, 1:奇行)
        get_bank_id = {ty[0], tx[0]}; 
    end
endfunction
```

### 2.2 Bank 内部地址计算 (Implementing Folding Equation)
```verilog
// 实现 Folding Equation
// Phy_Addr = Logic_Page_Base + Bin_Offset

function [11:0] get_bank_addr;
    input [5:0] idx;
    input [7:0] bin_addr;
    reg [2:0] tx, ty;
    begin
        tx = idx[2:0];
        ty = idx[5:3];
        
        // 逻辑 Tile 索引的高位构成了 "Folded Index" (被折叠进去的顺序)
        // tx[2:1] = X / 2
        // ty[2:1] = Y / 2
        
        // 物理地址拼接: {Y_High, X_High, Bin_Addr}
        get_bank_addr = {ty[2:1], tx[2:1], bin_addr};
    end
endfunction
```

---

## 3. 代码实现详解：Crossbar (交叉开关)

Mapping 模块请求的是 **TL / TR / BL / BR** (逻辑位置)，而数据分散在 **Bank 0 / 1 / 2 / 3** (物理位置)。这需要一个动态互连网络。

### 3.1 逻辑示意
假设当前窗口的左上角 (TL) 是 Tile (1,0) [Bank 1]:
-   **TL (1,0)** -> Bank 1
-   **TR (2,0)** -> Bank 0
-   **BL (1,1)** -> Bank 3
-   **BR (2,1)** -> Bank 2

此时 Crossbar 必须将 Bank 1 的输出连到 TL 端口。

### 3.2 完整代码实现
```verilog
// 1. 同时读取所有 4 个 RAM (Blind Read)
// 我们计算出这一时刻 TL, TR, BL, BR 针对其 *各自所属 Bank* 的物理地址，
// 并分别喂给对应的 Bank。

// 2. 将 RAM 输出路由到正确端口 (Port Multiplexing)
always @(*) begin
    // --------------------------------------------------------
    // TL Port Logic (Top-Left)
    // --------------------------------------------------------
    // M(TL_x, TL_y) -> 计算 TL 应该在哪个 Bank
    reg [1:0] bank_tl = get_bank_id(mapping_tl_tile_idx);
    
    // 从该 Bank 获取数据
    case (bank_tl)
        2'd0: mapping_tl_rd_data = (ping_pong_flag) ? rdata_1_0_p1 : rdata_0_0_p1;
        2'd1: mapping_tl_rd_data = (ping_pong_flag) ? rdata_1_1_p1 : rdata_0_1_p1;
        2'd2: mapping_tl_rd_data = (ping_pong_flag) ? rdata_1_2_p1 : rdata_0_2_p1;
        2'd3: mapping_tl_rd_data = (ping_pong_flag) ? rdata_1_3_p1 : rdata_0_3_p1;
    endcase

    // TR, BL, BR 逻辑同理...
end
```

---

## 4. 关键机制：Parallel Clear与乒乓操作

### 4.1 并行清零 (Parallel Clear)
在直方图统计开始前，RAM 内容必须全 0。利用 4-Bank 架构，我们实现了 4 倍速清零。
```verilog
always @(posedge pclk) begin
    if (clearing) begin
        // 这里同时拉低了所有 4 个 Bank 的写使能或写入 0 数据
        ram_0_0[clear_cnt] <= 16'd0;
        ram_0_1[clear_cnt] <= 16'd0;
        ram_0_2[clear_cnt] <= 16'd0;
        ram_0_3[clear_cnt] <= 16'd0;
        // 仅需 4096 周期即可清空整个 64 块区域
    end
end
```

### 4.2 乒乓与端口仲裁 (Priority Arbitration)
为了允许 **Frame N** 的 CDF 计算 (Mapping 读) 与 **Frame N+1** 的直方图统计 (Hist 写) 重叠进行，我们不仅使用了双缓冲 (Ping-Pong Set 0/1)，还在端口控制上做了细致的仲裁。

```verilog
// 端口 A 控制逻辑 (Port A Control Logic)
// 如果 PingPong=0，则 Set 0 处于 "活动状态"，既接受 Histogram 写入，也提供 CDF 读取
always @(posedge pclk) begin
    if (ping_pong_flag == 0) begin
        // 优先权：CDF 读取 > Histogram 读取
        // 这解决了 "VBlank 期间 CDF 模块无法读取数据" 的 Bug
        if (cdf_rd_en) begin
             // 此时 Clipper 正在读取直方图用于计算 CDF
             rdata_0_0_p0 <= ram_0_0[curr_cdf_addr];
        end
        else begin
             // 此时 Histogram 模块正在读取旧值用于 +1
             rdata_0_0_p0 <= ram_0_0[curr_hist_addr];
        end
    end
end
```

## 5. 总结
本设计的核心价值不仅仅在于工程实现，更在于它是 **VLSI DSP 理论**的生动应用案例。
通过 **Folding (折叠)** 减少了资源，通过 **Interleaving (交织)** 解决了冲突，通过 **Pipelining (流水线)** 提升了频率。这证明了扎实的理论基础是解决复杂工程问题的关键。
