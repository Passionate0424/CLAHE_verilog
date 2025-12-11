// ============================================================================
// Copyright (c) 2025 Passionate0424
// 
// GitHub: https://github.com/Passionate0424/CLAHE_verilog
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ============================================================================

// ============================================================================
// CLAHE 像素映射模块（并行读取版本）
//
// 功能描述:
//   - 使用CDF查找表对输入像素进行实时映射增强
//   - 支持单tile映射和标准四tile双线性插值两种模式
//   - 支持5级流水线处理，实现1像素/周期的处理吞吐率
//   - 提供可选的bypass模式（CLAHE禁用时直通输出）
//   - 自动延迟匹配U/V色度通道，保持数据同步
//   - 四块并行读取：单周期读取四个相邻块的CDF数据
//
// 标准CLAHE插值算法:
//   1. 计算像素相对于tile中心的偏移量(dx, dy)
//   2. 根据偏移量动态选择4个相邻tile进行插值
//   3. 使用双线性插值公式计算最终映射值
//   4. 边界处理：图像边缘tile不进行插值
//
// 处理流程 (5级流水线，并行读取四块):
//   - Stage 1: 计算tile索引和四块索引，发起并行读取
//   - Stage 2: 接收四个CDF数据（TL, TR, BL, BR）
//   - Stage 3: 双线性插值 - 横向插值（X方向）
//   - Stage 4: 双线性插值 - 纵向插值（Y方向）
//   - Stage 5: 最终输出
//
// 关键特性:
//   - 标准算法：符合OpenCV CLAHE实现
//   - 全图插值：消除所有tile边界块效应
//   - 边界保护：图像边缘tile安全处理
//   - 并行读取：单周期读取四块CDF数据
//   - 高吞吐：1像素/周期处理能力
//   - 简化流水线：从9级减少到5级
//
// 作者: Passionate.Z
// 日期: 2025-01-17
// ============================================================================

module clahe_mapping_parallel #(
        parameter TILE_NUM = 64,        // tile总数，默认64个
        parameter BINS = 256,           // 灰度级数，默认256个
        parameter IMG_WIDTH = 1280,     // 图像宽度
        parameter IMG_HEIGHT = 720,     // 图像高度
        parameter TILE_H = 8,           // 水平tile数量
        parameter TILE_V = 8            // 垂直tile数量
    )(
        // ====================================================================
        // 时钟和复位信号
        // ====================================================================
        input  wire        pclk,           // 像素时钟
        input  wire        rst_n,         // 复位信号，低电平有效

        // ====================================================================
        // 输入同步信号
        // ====================================================================
        input  wire        in_href,        // 行有效信号
        input  wire        in_vsync,       // 场同步信号

        // ====================================================================
        // 输入像素数据
        // ====================================================================
        input  wire [7:0]  in_y,           // 输入Y亮度值（8位）
        input  wire [7:0]  in_u,           // U色度值（直通，8位）
        input  wire [7:0]  in_v,           // V色度值（直通，8位）
        input  wire [5:0]  tile_idx,       // 当前tile索引（0-63）
        input  wire [10:0] pixel_x,        // 像素X坐标（0-1279）
        input  wire [9:0]  pixel_y,        // 像素Y坐标（0-719）
        input  wire [7:0]  local_x_in,     // tile内X坐标（来自coord_counter）
        input  wire [6:0]  local_y_in,     // tile内Y坐标（来自coord_counter）

        // ====================================================================
        // 控制信号
        // ====================================================================
        input  wire        clahe_enable,   // CLAHE使能信号
        input  wire        interp_enable,  // 插值使能信号
        input  wire        cdf_ready,      // CDF准备就绪信号

        // ====================================================================
        // 四块并行CDF LUT RAM读接口
        // ====================================================================
        // 四个相邻块的并行读取
        output wire [5:0]  cdf_tl_tile_idx,  // 左上tile索引（0-63）
        output wire [5:0]  cdf_tr_tile_idx,  // 右上tile索引（0-63）
        output wire [5:0]  cdf_bl_tile_idx,  // 左下tile索引（0-63）
        output wire [5:0]  cdf_br_tile_idx,  // 右下tile索引（0-63）
        output wire [7:0]  cdf_rd_bin_addr,  // 读bin地址（0-255）
        input  wire [7:0]  cdf_tl_rd_data,  // 左上块映射值（8bit）
        input  wire [7:0]  cdf_tr_rd_data,  // 右上块映射值（8bit）
        input  wire [7:0]  cdf_bl_rd_data,  // 左下块映射值（8bit）
        input  wire [7:0]  cdf_br_rd_data,  // 右下块映射值（8bit）

        // ====================================================================
        // 输出同步信号和数据
        // ====================================================================
        output reg         out_href,       // 输出行有效信号
        output reg         out_vsync,     // 输出场同步信号
        output reg  [7:0]  out_y,         // 映射后的Y值（8位）
        output reg  [7:0]  out_u,         // 延迟匹配的U值（8位）
        output reg  [7:0]  out_v          // 延迟匹配的V值（8位）
    );

    // ========================================================================
    // 参数计算
    // ========================================================================
    localparam TILE_WIDTH = IMG_WIDTH / TILE_H;   // 每个tile宽度：160像素
    localparam TILE_HEIGHT = IMG_HEIGHT / TILE_V; // 每个tile高度：90像素
    localparam TILE_CENTER_X = TILE_WIDTH / 2;    // tile中心X坐标：80像素
    localparam TILE_CENTER_Y = TILE_HEIGHT / 2;   // tile中心Y坐标：45像素

    // ========================================================================
    // 优化：权重查找表 - 替代除法器，提升时序性能
    // ========================================================================
    // wx查找表：local_x (0-159) -> wx (0-255)
    // 公式：wx = (local_x * 256) / 160
    reg [7:0] wx_lut [0:159];

    // wy查找表：local_y (0-89) -> wy (0-255)
    // 公式：wy = (local_y * 256) / 90
    reg [7:0] wy_lut [0:89];

    // 初始化查找表（综合工具会将其转换为ROM）
    integer lut_i;
    initial begin
        // 初始化wx查找表
        for (lut_i = 0; lut_i < 160; lut_i = lut_i + 1) begin
            wx_lut[lut_i] = (lut_i * 256) / 160;
        end

        // 初始化wy查找表
        for (lut_i = 0; lut_i < 90; lut_i = lut_i + 1) begin
            wy_lut[lut_i] = (lut_i * 256) / 90;
        end
    end

    // ========================================================================
    // 信号定义 - 坐标计算和tile索引
    // ========================================================================
    // 像素所在的tile和tile内位置
    wire [2:0]  tile_x, tile_y;         // tile坐标 (0-7, 0-7)
    wire [7:0]  local_x;                // tile内相对X坐标 (0-159) - 直接使用输入
    wire [6:0]  local_y;                // tile内相对Y坐标 (0-89) - 直接使用输入

    // 计算相对于tile中心的偏移
    wire signed [8:0]  dx;              // X方向偏移 (-80 to +79)
    wire signed [7:0]  dy;              // Y方向偏移 (-45 to +44)

    // 判断插值模式（标准CLAHE边界处理）
    wire need_interp;                   // 是否需要插值

    // ========================================================================
    // 信号定义 - 四tile索引计算（标准CLAHE算法）
    // ========================================================================
    // 四个相邻tile的坐标
    wire [2:0]  tile_idx_tl_x, tile_idx_tl_y;  // 左上tile坐标
    wire [2:0]  tile_idx_tr_x, tile_idx_tr_y;  // 右上tile坐标
    wire [2:0]  tile_idx_bl_x, tile_idx_bl_y;  // 左下tile坐标
    wire [2:0]  tile_idx_br_x, tile_idx_br_y;  // 右下tile坐标

    // 四个相邻tile的线性索引
    wire [5:0]  tile_idx_tl, tile_idx_tr, tile_idx_bl, tile_idx_br;

    // 插值权重 (Q8定点格式: 0-255 表示 0.0-1.0)
    wire [7:0]  wx, wy;

    // ========================================================================
    // 坐标计算逻辑（可综合版本 - 使用比较器链代替除法）
    // ========================================================================
    // 方法：对于1280x720分辨率，8x8 tiles
    //   TILE_WIDTH = 160, 边界为：0, 160, 320, 480, 640, 800, 960, 1120, 1280
    //   TILE_HEIGHT = 90, 边界为：0, 90, 180, 270, 360, 450, 540, 630, 720

    // 直接使用coord_counter计算的tile坐标和tile内坐标，避免重复计算导致不一致
    assign tile_x = tile_idx[2:0];       // tile_idx的低3位是tile_x
    assign tile_y = tile_idx[5:3];       // tile_idx的高3位是tile_y

    // 直接使用输入的local坐标，避免重复计算
    assign local_x = local_x_in;
    assign local_y = local_y_in;

    // 计算相对于tile中心的偏移（有符号运算，显式类型转换）
    assign dx = $signed({1'b0, local_x}) - $signed(9'd80);   // TILE_CENTER_X = 80
    assign dy = $signed({1'b0, local_y}) - $signed(8'd45);   // TILE_CENTER_Y = 45

    // ========================================================================
    // 插值模式判断（标准CLAHE边界处理）
    // ========================================================================
    // 标准CLAHE算法的插值规则：
    //   1. 内部像素：有4个不同的邻近tile → 双线性插值
    //   2. 边缘像素：有2个不同的邻近tile → 线性插值
    //   3. 角落像素：只有1个tile → 直接映射（无插值）
    //
    // 简化实现：我们总是尝试进行双线性插值
    //   - 对于边缘/角落像素，四tile索引计算会自动复制tile
    //   - 例如：corner像素的4个tile都是同一个 → 插值结果等于直接映射
    //   - 例如：边缘像素的4个tile中有2个相同 → 插值结果等于线性插值
    //
    // 因此：只要插值使能，就进行插值计算（边界自动处理）
    assign need_interp = interp_enable;

    // ========================================================================
    // 四tile索引计算（标准CLAHE算法 + 边界保护）
    // ========================================================================
    // 根据像素相对于tile中心的位置，动态选择4个相邻tile
    //
    // 选择规则：
    //   dx < 0: 像素在tile左半部分，选择左边tile
    //   dx >= 0: 像素在tile右半部分，选择右边tile
    //   dy < 0: 像素在tile上半部分，选择上边tile
    //   dy >= 0: 像素在tile下半部分，选择下边tile
    //
    // 边界保护：确保tile索引不越界

    // 左上tile (TL): Top-Left
    assign tile_idx_tl_x = (dx < 0) ?
           ((tile_x > 0) ? tile_x - 3'd1 : tile_x) : tile_x;
    assign tile_idx_tl_y = (dy < 0) ?
           ((tile_y > 0) ? tile_y - 3'd1 : tile_y) : tile_y;
    assign tile_idx_tl = {tile_idx_tl_y, tile_idx_tl_x};

    // 右上tile (TR): Top-Right
    assign tile_idx_tr_x = (dx < 0) ? tile_x :
           ((tile_x < 3'd7) ? tile_x + 3'd1 : 3'd7);  // 明确边界值
    assign tile_idx_tr_y = (dy < 0) ?
           ((tile_y > 0) ? tile_y - 3'd1 : tile_y) : tile_y;
    assign tile_idx_tr = {tile_idx_tr_y, tile_idx_tr_x};

    // 左下tile (BL): Bottom-Left
    assign tile_idx_bl_x = (dx < 0) ?
           ((tile_x > 0) ? tile_x - 3'd1 : tile_x) : tile_x;
    assign tile_idx_bl_y = (dy < 0) ? tile_y :
           ((tile_y < 3'd7) ? tile_y + 3'd1 : 3'd7);  // 明确边界值
    assign tile_idx_bl = {tile_idx_bl_y, tile_idx_bl_x};

    // 右下tile (BR): Bottom-Right
    assign tile_idx_br_x = (dx < 0) ? tile_x :
           ((tile_x < 3'd7) ? tile_x + 3'd1 : 3'd7);  // 明确边界值
    assign tile_idx_br_y = (dy < 0) ? tile_y :
           ((tile_y < 3'd7) ? tile_y + 3'd1 : 3'd7);  // 明确边界值
    assign tile_idx_br = {tile_idx_br_y, tile_idx_br_x};

    // ========================================================================
    // 插值权重计算（优化版 - 使用查找表替代除法器）
    // ========================================================================
    // 权重表示像素距离两个相邻tile中心的相对距离
    // 使用Q8定点格式：0-255 表示 0.0-1.0
    //
    // 优化说明：
    //   - 原实现：wx = (local_x * 8) / 5，需要除法器，时序瓶颈
    //   - 新实现：wx = wx_lut[local_x]，查找表ROM，单周期访问
    //   - 预期收益：消除关键路径上的除法器，提升Fmax约20-30%
    //
    // 权重公式：
    //   wx = (local_x * 256) / TILE_WIDTH = (local_x * 256) / 160
    //   wy = (local_y * 256) / TILE_HEIGHT = (local_y * 256) / 90

    // 修复：插值权重必须相对于由于"Tile中心"定义的Grid Node
    // 原实现 (local_x) 是相对于Tile边缘，导致相位偏移
    // 新实现：
    //   - 左半部分 (local < center): 位于 [LeftCenter, ThisCenter] 之间 -> idx = local + center
    //   - 右半部分 (local >= center): 位于 [ThisCenter, RightCenter] 之间 -> idx = local - center
    wire [7:0] wx_idx_fix;
    wire [7:0] wy_idx_fix;

    assign wx_idx_fix = (local_x < TILE_CENTER_X) ? (local_x + TILE_CENTER_X) : (local_x - TILE_CENTER_X);
    assign wy_idx_fix = (local_y < TILE_CENTER_Y) ? (local_y + TILE_CENTER_Y) : (local_y - TILE_CENTER_Y);

    assign wx = wx_lut[wx_idx_fix];
    assign wy = wy_lut[wy_idx_fix];

    // ========================================================================
    // 输出接口连接
    // ========================================================================
    // 四块并行读取接口
    assign cdf_tl_tile_idx = need_interp ? tile_idx_tl : tile_idx;
    assign cdf_tr_tile_idx = need_interp ? tile_idx_tr : tile_idx;
    assign cdf_bl_tile_idx = need_interp ? tile_idx_bl : tile_idx;
    assign cdf_br_tile_idx = need_interp ? tile_idx_br : tile_idx;
    assign cdf_rd_bin_addr = in_y;  // 像素灰度值作为bin地址

    // ========================================================================
    // 流水线信号定义
    // ========================================================================

    // ---- Stage 1 延迟寄存器 ----
    reg [7:0]  y_d1, u_d1, v_d1;        // 像素YUV数据
    reg        href_d1, vsync_d1;       // 同步信号
    reg        enable_d1, interp_d1;    // 控制信号
    reg [7:0]  wx_d1, wy_d1;            // 插值权重

    // ---- Stage 2 延迟寄存器 ----
    reg [7:0]  y_d2, u_d2, v_d2;
    reg        href_d2, vsync_d2;
    reg        enable_d2, interp_d2;
    reg [7:0]  wx_d2, wy_d2;
    reg [7:0]  cdf_tl_d2, cdf_tr_d2, cdf_bl_d2, cdf_br_d2;  // 四个CDF值

    // ---- Stage 3 延迟寄存器和插值第一步（横向插值）----
    reg [7:0]  y_d3, u_d3, v_d3;
    reg        href_d3, vsync_d3;
    reg        enable_d3, interp_d3;
    reg [7:0]  wx_d3, wy_d3;            // 权重延迟到Stage 3
    reg [15:0] interp_top;              // 横向插值结果（上边）
    reg [15:0] interp_bottom;           // 横向插值结果（下边）

    // ---- Stage 4 延迟寄存器和插值第二步（纵向插值）----
    reg [7:0]  y_d4, u_d4, v_d4;
    reg        href_d4, vsync_d4;
    reg        enable_d4;
    reg [23:0] final_interp;            // 纵向插值最终结果

    // ========================================================================
    // Stage 1: 像素进入流水线，发起并行读取
    // ========================================================================
    // 功能：
    //   1. 延迟输入数据和控制信号
    //   2. 四块索引和bin地址已经通过组合逻辑输出到RAM
    //   3. 下一周期将接收四个CDF数据
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位延迟数据
            y_d1 <= 8'd0;
            u_d1 <= 8'd0;
            v_d1 <= 8'd0;
            href_d1 <= 1'b0;
            vsync_d1 <= 1'b0;
            enable_d1 <= 1'b0;
            interp_d1 <= 1'b0;
            wx_d1 <= 8'd0;
            wy_d1 <= 8'd0;
        end
        else begin
            // ---- 数据延迟 ----
            y_d1 <= in_y;
            u_d1 <= in_u;
            v_d1 <= in_v;
            href_d1 <= in_href;
            vsync_d1 <= in_vsync;
            enable_d1 <= clahe_enable;  // 去掉cdf_ready判断，始终尝试使用CDF
            interp_d1 <= need_interp;
            wx_d1 <= wx;
            wy_d1 <= wy;
        end
    end

    // ========================================================================
    // Stage 2: 接收四个CDF数据
    // ========================================================================
    // 功能：
    //   1. 接收四个相邻块的CDF数据（TL, TR, BL, BR）
    //   2. 延迟像素数据和控制信号
    //   3. 为下一阶段的插值计算准备数据
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            // ---- 复位所有延迟寄存器 ----
            y_d2 <= 8'd0;
            u_d2 <= 8'd0;
            v_d2 <= 8'd0;
            href_d2 <= 1'b0;
            vsync_d2 <= 1'b0;
            enable_d2 <= 1'b0;
            interp_d2 <= 1'b0;
            wx_d2 <= 8'd0;
            wy_d2 <= 8'd0;

            // ---- 复位CDF数据寄存器 ----
            cdf_tl_d2 <= 8'd0;
            cdf_tr_d2 <= 8'd0;
            cdf_bl_d2 <= 8'd0;
            cdf_br_d2 <= 8'd0;
        end
        else begin
            // ---- 数据延迟 ----
            y_d2 <= y_d1;
            u_d2 <= u_d1;
            v_d2 <= v_d1;
            href_d2 <= href_d1;
            vsync_d2 <= vsync_d1;
            enable_d2 <= enable_d1;
            interp_d2 <= interp_d1;
            wx_d2 <= wx_d1;
            wy_d2 <= wy_d1;

            // ---- 接收四个CDF数据 ----
            cdf_tl_d2 <= cdf_tl_rd_data;
            cdf_tr_d2 <= cdf_tr_rd_data;
            cdf_bl_d2 <= cdf_bl_rd_data;
            cdf_br_d2 <= cdf_br_rd_data;
        end
    end

    // ========================================================================
    // Stage 3: 双线性插值计算 - 横向插值
    // ========================================================================
    // 功能：
    //   1. 使用4个tile的CDF数据进行双线性插值
    //   2. 横向插值：计算上边和下边的插值结果
    //   3. 延迟像素数据和控制信号
    //
    // 插值公式：
    //   interp_top = (256-wx) * cdf_tl + wx * cdf_tr
    //   interp_bottom = (256-wx) * cdf_bl + wx * cdf_br
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位延迟数据
            y_d3 <= 8'd0;
            u_d3 <= 8'd0;
            v_d3 <= 8'd0;
            href_d3 <= 1'b0;
            vsync_d3 <= 1'b0;
            enable_d3 <= 1'b0;
            interp_d3 <= 1'b0;
            wx_d3 <= 8'd0;
            wy_d3 <= 8'd0;

            // 复位横向插值结果
            interp_top <= 16'd0;
            interp_bottom <= 16'd0;
        end
        else begin
            // ---- 数据延迟 ----
            y_d3 <= y_d2;
            u_d3 <= u_d2;
            v_d3 <= v_d2;
            href_d3 <= href_d2;
            vsync_d3 <= vsync_d2;
            enable_d3 <= enable_d2;
            interp_d3 <= interp_d2;
            wx_d3 <= wx_d2;
            wy_d3 <= wy_d2;

            // ---- 横向插值计算（X方向）----
            // 使用Stage 2传递的CDF数据
            if (interp_d2) begin
                // 上边插值：interp_top = (256-wx)*cdf_tl + wx*cdf_tr
                interp_top <= ((16'd256 - {8'd0, wx_d2}) * {8'd0, cdf_tl_d2} +
                               {8'd0, wx_d2} * {8'd0, cdf_tr_d2});

                // 下边插值：interp_bottom = (256-wx)*cdf_bl + wx*cdf_br
                interp_bottom <= ((16'd256 - {8'd0, wx_d2}) * {8'd0, cdf_bl_d2} +
                                  {8'd0, wx_d2} * {8'd0, cdf_br_d2});
            end
            else begin
                // 非插值模式：使用TL数据（单tile模式）
                interp_top <= {8'd0, cdf_tl_d2};
                interp_bottom <= {8'd0, cdf_tl_d2};
            end
        end
    end

    // ========================================================================
    // Stage 4: 纵向插值和像素映射
    // ========================================================================
    // 功能：
    //   1. 使用Stage 3的横向插值结果进行纵向插值
    //   2. 计算最终插值值并归一化
    //   3. 如果非插值模式，则使用单tile CDF或bypass
    //
    // 纵向插值公式（Q8定点格式）：
    //   final_interp = (256-wy) * interp_top + wy * interp_bottom
    //   mapped_y = final_interp >> 16
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位延迟数据
            y_d4 <= 8'd0;
            u_d4 <= 8'd0;
            v_d4 <= 8'd0;
            href_d4 <= 1'b0;
            vsync_d4 <= 1'b0;
            enable_d4 <= 1'b0;

            // 复位插值计算
            final_interp <= 24'd0;
        end
        else begin
            // ---- 数据延迟 ----
            y_d4 <= y_d3;
            u_d4 <= u_d3;
            v_d4 <= v_d3;
            href_d4 <= href_d3;
            vsync_d4 <= vsync_d3;
            enable_d4 <= enable_d3;

            // ---- 像素映射计算 ----
            if (enable_d3) begin
                if (interp_d3) begin
                    // === 插值模式：纵向插值 ===
                    // final = (256-wy) * interp_top + wy * interp_bottom
                    final_interp <= ((24'd256 - {16'd0, wy_d3}) * {8'd0, interp_top} +
                                     {16'd0, wy_d3} * {8'd0, interp_bottom});
                end
                else begin
                    // === 单tile模式：直接使用interp_top（它在非插值模式下就是cdf_tl） ===
                    final_interp <= {interp_top[7:0], 16'd0};  // 取低8位，左移16位
                end
            end
            else begin
                // === Bypass模式：CLAHE禁用，输出原始像素 ===
                final_interp <= {y_d3, 16'd0};  // 左移16位
            end
        end
    end

    // ========================================================================
    // Stage 5: 最终输出
    // ========================================================================
    // 功能：
    //   1. 输出映射后的Y分量
    //   2. 输出延迟匹配的U/V分量（保持色度信息）
    //   3. 输出延迟匹配的同步信号
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            out_y <= 8'd0;
            out_u <= 8'd0;
            out_v <= 8'd0;
            out_href <= 1'b0;
            out_vsync <= 1'b0;
        end
        else begin
            out_y <= final_interp[23:16];  // 输出映射后的Y分量（取高8位）
            out_u <= u_d4;                 // 输出延迟匹配的U分量
            out_v <= v_d4;                 // 输出延迟匹配的V分量
            out_href <= href_d4;           // 输出延迟匹配的href信号
            out_vsync <= vsync_d4;         // 输出延迟匹配的vsync信号
        end
    end

endmodule
