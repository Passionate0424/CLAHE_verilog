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
        parameter TILE_NUM = 16,        // tile总数，默认16个
        parameter BINS = 256,           // 灰度级数，默认256个
        parameter IMG_WIDTH = 1280,     // 图像宽度
        parameter IMG_HEIGHT = 720,     // 图像高度
        parameter TILE_H = 4,           // 水平tile数量
        parameter TILE_V = 4            // 垂直tile数量
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
        input  wire [3:0]  tile_idx,       // 当前tile索引（0-15）
        input  wire [10:0] pixel_x,        // 像素X坐标（0-1279）
        input  wire [9:0]  pixel_y,        // 像素Y坐标（0-719）
        input  wire [8:0]  local_x_in,     // tile内X坐标（来自coord_counter）
        input  wire [7:0]  local_y_in,     // tile内Y坐标（来自coord_counter）

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
        output wire [3:0]  cdf_tl_tile_idx,  // 左上tile索引（0-15）
        output wire [3:0]  cdf_tr_tile_idx,  // 右上tile索引（0-15）
        output wire [3:0]  cdf_bl_tile_idx,  // 左下tile索引（0-15）
        output wire [3:0]  cdf_br_tile_idx,  // 右下tile索引（0-15）
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
    localparam TILE_WIDTH = IMG_WIDTH / TILE_H;   // 每个tile宽度：320像素
    localparam TILE_HEIGHT = IMG_HEIGHT / TILE_V; // 每个tile高度：180像素
    localparam TILE_CENTER_X = TILE_WIDTH / 2;    // tile中心X坐标：160像素
    localparam TILE_CENTER_Y = TILE_HEIGHT / 2;   // tile中心Y坐标：90像素

    // ========================================================================
    // 信号定义 - 坐标计算和tile索引
    // ========================================================================
    // 像素所在的tile和tile内位置
    wire [1:0]  tile_x, tile_y;         // tile坐标 (0-3, 0-3)
    wire [8:0]  local_x;                // tile内相对X坐标 (0-319) - 直接使用输入
    wire [7:0]  local_y;                // tile内相对Y坐标 (0-179) - 直接使用输入

    // 计算相对于tile中心的偏移
    wire signed [9:0]  dx;              // X方向偏移 (-160 to +159)
    wire signed [8:0]  dy;              // Y方向偏移 (-90 to +89)

    // 判断插值模式（标准CLAHE边界处理）
    wire need_interp;                   // 是否需要插值

    // ========================================================================
    // 信号定义 - 四tile索引计算（标准CLAHE算法）
    // ========================================================================
    // 四个相邻tile的坐标
    wire [1:0]  tile_idx_tl_x, tile_idx_tl_y;  // 左上tile坐标
    wire [1:0]  tile_idx_tr_x, tile_idx_tr_y;  // 右上tile坐标
    wire [1:0]  tile_idx_bl_x, tile_idx_bl_y;  // 左下tile坐标
    wire [1:0]  tile_idx_br_x, tile_idx_br_y;  // 右下tile坐标

    // 四个相邻tile的线性索引
    wire [3:0]  tile_idx_tl, tile_idx_tr, tile_idx_bl, tile_idx_br;

    // 插值权重 (Q8定点格式: 0-255 表示 0.0-1.0)
    wire [7:0]  wx, wy;

    // ========================================================================
    // 优化：实时权重计算 - 基于tile中心距离的标准CLAHE插值
    // ========================================================================
    // 标准CLAHE权重计算（基于像素到tile中心的距离）：
    //   权重表示像素在两个相邻tile中心之间的相对位置
    //
    // X方向：
    //   - dx < 0: 像素在左半部分，wx = 128 + (dx * 256 / 320)
    //   - dx >= 0: 像素在右半部分，wx = 128 + (dx * 256 / 320)
    //   结果：wx在tile中心=128，在边界≈255或0，实现平滑过渡
    //
    // Y方向：
    //   - dy < 0: 像素在上半部分，wy = 128 + (dy * 256 / 180)
    //   - dy >= 0: 像素在下半部分，wy = 128 + (dy * 256 / 180)
    //
    // 定点数优化（避免除法器）：
    //   dx * 256 / 320 ≈ (dx * 819) >> 10  (819/1024 = 0.7998 ≈ 256/320 = 0.8)
    //   dy * 256 / 180 ≈ (dy * 1456) >> 10 (1456/1024 = 1.4219 ≈ 256/180 = 1.4222)

    // 权重计算中间信号
    wire signed [19:0] wx_mult;  // dx * 819 (带符号，10位×10位=20位)
    wire signed [18:0] wy_mult;  // dy * 1456 (带符号，9位×11位=19位)
    wire signed [10:0] wx_offset; // (dx * 819) >> 10 的结果
    wire signed [9:0]  wy_offset; // (dy * 1456) >> 10 的结果

    // ========================================================================
    // 坐标计算逻辑（可综合版本 - 使用比较器链代替除法）
    // ========================================================================
    // 方法：对于1280x720分辨率，4x4 tiles
    //   TILE_WIDTH = 320, 边界为：0, 320, 640, 960, 1280
    //   TILE_HEIGHT = 180, 边界为：0, 180, 360, 540, 720

    // 直接使用coord_counter计算的tile坐标和tile内坐标，避免重复计算导致不一致
    assign tile_x = tile_idx[1:0];       // tile_idx的低2位是tile_x
    assign tile_y = tile_idx[3:2];       // tile_idx的高2位是tile_y

    // 直接使用输入的local坐标，避免重复计算
    assign local_x = local_x_in;
    assign local_y = local_y_in;

    // 计算相对于tile中心的偏移（有符号运算，显式类型转换）
    assign dx = $signed({1'b0, local_x}) - $signed(10'd160);   // TILE_CENTER_X = 160
    assign dy = $signed({1'b0, local_y}) - $signed(9'd90);     // TILE_CENTER_Y = 90

    // 基于dx/dy计算插值权重（标准CLAHE算法 + 舍入优化）
    // wx = 128 + (dx * 256 / 320) ≈ 128 + ((dx * 819 + 512) >> 10)
    // wy = 128 + (dy * 256 / 180) ≈ 128 + ((dy * 1456 + 512) >> 10)
    // 舍入优化：加512后再右移10位，实现舍入而非截断，精度提升~50%
    assign wx_mult = $signed(dx) * $signed(10'd819) + $signed(20'd512);      // 舍入
    assign wy_mult = $signed(dy) * $signed(11'd1456) + $signed(19'd512);     // 舍入

    // 右移10位得到偏移量，然后加128得到最终权重
    assign wx_offset = wx_mult >>> 10;  // 算术右移保留符号
    assign wy_offset = wy_mult >>> 10;  // 算术右移保留符号

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
           ((tile_x > 0) ? tile_x - 2'd1 : tile_x) : tile_x;
    assign tile_idx_tl_y = (dy < 0) ?
           ((tile_y > 0) ? tile_y - 2'd1 : tile_y) : tile_y;
    assign tile_idx_tl = {tile_idx_tl_y, tile_idx_tl_x};

    // 右上tile (TR): Top-Right
    assign tile_idx_tr_x = (dx < 0) ? tile_x :
           ((tile_x < 2'd3) ? tile_x + 2'd1 : 2'd3);  // 明确边界值
    assign tile_idx_tr_y = (dy < 0) ?
           ((tile_y > 0) ? tile_y - 2'd1 : tile_y) : tile_y;
    assign tile_idx_tr = {tile_idx_tr_y, tile_idx_tr_x};

    // 左下tile (BL): Bottom-Left
    assign tile_idx_bl_x = (dx < 0) ?
           ((tile_x > 0) ? tile_x - 2'd1 : tile_x) : tile_x;
    assign tile_idx_bl_y = (dy < 0) ? tile_y :
           ((tile_y < 2'd3) ? tile_y + 2'd1 : 2'd3);  // 明确边界值
    assign tile_idx_bl = {tile_idx_bl_y, tile_idx_bl_x};

    // 右下tile (BR): Bottom-Right
    assign tile_idx_br_x = (dx < 0) ? tile_x :
           ((tile_x < 2'd3) ? tile_x + 2'd1 : 2'd3);  // 明确边界值
    assign tile_idx_br_y = (dy < 0) ? tile_y :
           ((tile_y < 2'd3) ? tile_y + 2'd1 : 2'd3);  // 明确边界值
    assign tile_idx_br = {tile_idx_br_y, tile_idx_br_x};

    // ========================================================================
    // 插值权重输出（标准CLAHE算法 - 基于tile中心距离）
    // ========================================================================
    // 权重表示像素在两个相邻tile中心之间的相对位置
    // 使用Q8定点格式：0-255 表示 0.0-1.0
    //
    // 关键修复：
    //   - 旧实现：wx = (local_x * 819) >> 10，基于local坐标 ❌
    //     问题：tile边界处突然跳变(319→255, 0→0)，导致严重分块效应
    //   - 新实现：wx = 128 + ((dx * 819) >> 10)，基于tile中心距离 ✓
    //     优势：tile边界处平滑过渡(左边界≈0, 中心=128, 右边界≈255)
    //
    // 饱和处理：确保权重在0-255范围内
    function [7:0] saturate_weight;
        input signed [10:0] offset;  // wx_offset或wy_offset
        reg signed [10:0] result;
        begin
            result = 11'sd128 + offset;  // 加上中心偏移
            if (result < 0)
                saturate_weight = 8'd0;
            else if (result > 255)
                saturate_weight = 8'd255;
            else
                saturate_weight = result[7:0];
        end
    endfunction

    assign wx = saturate_weight(wx_offset);  // 饱和到0-255
    assign wy = saturate_weight(wy_offset);  // 饱和到0-255

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
