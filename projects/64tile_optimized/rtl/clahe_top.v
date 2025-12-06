// ============================================================================
// CLAHE 顶层模块 - 并行读取优化版本（支持YUV三路数据）
//
// 功能描述:
//   - 集成64块独立RAM架构，实现64倍性能提升
//   - 支持YUV三路数据输入输出，确保数据对齐
//   - 保持原有的乒乓操作和流水线设计
//   - 完整的CLAHE处理流程，支持实时视频处理
//   - 新增四块并行读取功能，实现1像素/周期处理吞吐率
//   - 双线性插值功能，消除tile边界块效应
//
// 性能提升:
//   - 清零时间: 16,384周期 → 256周期 (64倍提升)
//   - 清零时间: 164μs → 2.56μs (100MHz时钟)
//   - 映射吞吐率: 1像素/4周期 → 1像素/周期 (4倍提升)
//   - 流水线级数: 9级 → 5级 (44%简化)
//   - 支持实时处理: 1280×720@30fps
//
// YUV数据处理:
//   - Y分量: 进行CLAHE增强处理（支持插值）
//   - U/V分量: 延迟匹配，保持与Y分量同步
//   - 数据对齐: 确保三路数据输出时序一致
//
// 处理模式:
//   1. 插值模式: enable_clahe=1, enable_interp=1，使用双线性插值，效果最佳
//   2. 单tile模式: enable_clahe=1, enable_interp=0，使用单tile映射，处理速度快
//   3. Bypass模式: enable_clahe=0，直接输出原始数据
//
// 并行读取优化:
//   - 四块并行读取: 单周期读取四个相邻tile的CDF数据
//   - 简化流水线: 从9级减少到5级
//   - 高吞吐率: 实现1像素/周期的处理能力
//
// 作者: Passionate.Z
// 日期: 2025-10-18
// ============================================================================

`timescale 1ns / 1ps

module clahe_top (
        // ====================================================================
        // 时钟和复位信号
        // ====================================================================
        input  wire        pclk,           // 像素时钟，通常为74MHz或100MHz
        input  wire        rst_n,          // 复位信号，低电平有效

        // ====================================================================
        // 输入数据接口 - 来自摄像头或图像传感器
        // ====================================================================
        input  wire [7:0]  in_y,           // 输入Y分量（亮度），8位灰度值
        input  wire [7:0]  in_u,           // 输入U分量（色度），8位色度值
        input  wire [7:0]  in_v,           // 输入V分量（色度），8位色度值
        input  wire        in_href,        // 行有效信号，高电平表示有效像素
        input  wire        in_vsync,       // 场同步信号，高电平表示有效帧

        // ====================================================================
        // 输出数据接口 - 送往显示器或编码器
        // ====================================================================
        output wire [7:0]  out_y,          // 输出Y分量（CLAHE增强后的亮度）
        output wire [7:0]  out_u,          // 输出U分量（延迟匹配的色度）
        output wire [7:0]  out_v,          // 输出V分量（延迟匹配的色度）
        output wire        out_href,       // 输出行有效信号（延迟匹配）
        output wire        out_vsync,      // 输出场同步信号（延迟匹配）

        // ====================================================================
        // 控制接口 - 来自CPU或控制逻辑
        // ====================================================================
        input  wire [7:0]  clip_threshold, // 对比度限制阈值 (0-255)，推荐值：3-5
        input  wire        enable_clahe,   // CLAHE使能信号，1=启用CLAHE处理
        input  wire        enable_interp,   // 插值使能信号，1=启用双线性插值

        // ====================================================================
        // 调试接口 - 用于仿真和调试
        // ====================================================================
        output wire        dbg_cdf_processing,
        output wire        dbg_cdf_done,
        output wire        dbg_ping_pong_flag
    );

    // ========================================================================
    // 图像和分块参数定义
    // ========================================================================
    localparam WIDTH = 1280;        // 图像宽度：1280像素（HD分辨率）
    localparam HEIGHT = 720;        // 图像高度：720像素（HD分辨率）
    localparam TILE_H = 8;          // 水平tile数量：8个（将图像分成8列）
    localparam TILE_V = 8;          // 垂直tile数量：8个（将图像分成8行）
    localparam TILE_NUM = 64;       // 总tile数量：8×8=64个（每个tile独立处理）
    localparam TILE_WIDTH = WIDTH / TILE_H;   // 每个tile宽度：160像素
    localparam TILE_HEIGHT = HEIGHT / TILE_V; // 每个tile高度：90像素

    // ========================================================================
    // 内部信号定义
    // ========================================================================

    // ========================================================================
    // 同步信号延迟寄存器
    // ========================================================================
    reg vsync_d1, vsync_d2;          // vsync边沿检测寄存器

    // ========================================================================
    // 坐标计算相关信号
    // ========================================================================
    // 坐标计数器输出：实时计算像素位置和tile索引
    wire [10:0] pixel_x;               // 全局像素X坐标 (0-1279)
    wire [9:0]  pixel_y;                // 全局像素Y坐标 (0-719)
    wire [2:0]  tile_x, tile_y;         // tile坐标 (0-7, 0-7)
    wire [5:0]  tile_idx;               // tile索引 (0-63)，用于选择对应的RAM
    wire [7:0]  local_x;                // tile内相对X坐标 (0-159)
    wire [6:0]  local_y;                // tile内相对Y坐标 (0-89)

    // ========================================================================
    // 乒乓控制相关信号
    // ========================================================================
    // 乒乓控制：帧级乒乓操作，实现统计和映射的并行处理
    reg         ping_pong_flag;      // 乒乓标志：0=统计RAM_A/映射RAM_B, 1=统计RAM_B/映射RAM_A
    wire        vsync_posedge, vsync_negedge; // 场同步边沿检测信号

    // ========================================================================
    // 直方图统计控制信号
    // ========================================================================
    // 直方图统计控制：64块RAM的并行清零控制
    wire        hist_clear_start;    // 清零开始信号，触发RAM清零操作
    wire        hist_clear_done;     // 清零完成信号，表示RAM清零完成
    wire        frame_hist_done;     // 帧直方图统计完成标志，触发CDF计算

    // ========================================================================
    // 直方图统计模块的RAM接口
    // ========================================================================
    wire [5:0]  hist_rd_tile_idx;    // 直方图统计读tile索引
    wire [5:0]  hist_wr_tile_idx;    // 直方图统计写tile索引
    wire [7:0]  hist_wr_addr;        // 直方图统计写地址
    wire [15:0] hist_wr_data;        // 直方图统计写数据
    wire        hist_wr_en;          // 直方图统计写使能
    wire [7:0]  hist_rd_addr;        // 直方图统计读地址
    wire [15:0] hist_rd_data;        // 直方图统计读数据

    // ========================================================================
    // CDF计算模块的RAM接口
    // ========================================================================
    // 修复：分开定义读和写的tile索引
    wire [5:0]  cdf_rd_tile_idx;     // CDF读tile索引（读直方图）
    wire [5:0]  cdf_wr_tile_idx;     // CDF写tile索引（写LUT）
    wire [7:0]  cdf_rd_addr;         // CDF读地址（读直方图）
    wire [7:0]  cdf_wr_addr;         // CDF写地址（写LUT）
    wire [7:0]  cdf_wr_data;         // CDF写数据（8bit）
    wire        cdf_wr_en;           // CDF写使能
    wire        cdf_rd_en;           // CDF读使能
    wire [15:0] cdf_rd_data;         // CDF读数据
    wire        cdf_done;            // CDF计算完成标志
    wire        cdf_processing;      // CDF处理中标志

    // CDF地址和tile索引多路复用：读时用rd，写时用wr
    wire [5:0]  cdf_tile_idx;
    wire [7:0]  cdf_addr;
    assign cdf_tile_idx = cdf_wr_en ? cdf_wr_tile_idx : cdf_rd_tile_idx;
    assign cdf_addr = cdf_wr_en ? cdf_wr_addr : cdf_rd_addr;

    // ========================================================================
    // 像素映射模块的RAM接口（并行读取版本 - 四块并行）
    // ========================================================================
    // 四块并行读取接口
    wire [5:0]  mapping_tl_tile_idx;    // 左上tile索引
    wire [5:0]  mapping_tr_tile_idx;    // 右上tile索引
    wire [5:0]  mapping_bl_tile_idx;    // 左下tile索引
    wire [5:0]  mapping_br_tile_idx;    // 右下tile索引
    wire [7:0]  mapping_addr;           // 映射地址（四块共用）
    wire [7:0]  mapping_tl_rd_data;     // 左上块读数据（8bit CDF LUT）
    wire [7:0]  mapping_tr_rd_data;     // 右上块读数据（8bit CDF LUT）
    wire [7:0]  mapping_bl_rd_data;     // 左下块读数据（8bit CDF LUT）
    wire [7:0]  mapping_br_rd_data;     // 右下块读数据（8bit CDF LUT）
    wire [7:0]  mapped_y;               // 映射后的Y分量
    wire [7:0]  mapped_u;               // 映射后的U分量
    wire [7:0]  mapped_v;               // 映射后的V分量
    wire        mapped_href;            // 映射后的行有效信号
    wire        mapped_vsync;           // 映射后的场同步信号

    // 注意：延迟匹配已集成到mapping模块中，无需额外的延迟逻辑

    // ========================================================================
    // 同步信号检测：检测vsync的上升沿和下降沿
    // ========================================================================
    // 功能：检测场同步信号的边沿，用于乒乓控制和帧完成检测
    // 原理：通过2级延迟寄存器检测vsync的变化
    // 输出：vsync_posedge（上升沿）、vsync_negedge（下降沿）
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d1 <= 1'b0;
            vsync_d2 <= 1'b0;
        end
        else begin
            vsync_d1 <= in_vsync;
            vsync_d2 <= vsync_d1;
        end
    end

    // 边沿检测：通过异或运算检测vsync的变化
    assign vsync_posedge = vsync_d1 && !vsync_d2;  // 上升沿：当前为1，前一个为0
    assign vsync_negedge = !vsync_d1 && vsync_d2;  // 下降沿：当前为0，前一个为1

    // ========================================================================
    // 乒乓控制：帧级乒乓操作实现统计和映射的并行处理
    // ========================================================================
    // 功能：控制64块RAM的乒乓操作，实现帧级并行处理
    // 原理：vsync上升沿切换乒乓标志，vsync下降沿触发Clip+CDF计算
    // 时序：帧0写RAM_A读RAM_B，帧1写RAM_B读RAM_A

    // ========================================================================
    // 乒乓控制逻辑（优化：在CDF计算完成时切换，消除闪烁）
    // ========================================================================
    // 优化说明：
    // 1. 问题根源：原来在新帧第一个href时切换，虽然理论有时间但存在时序风险
    // 2. 解决方案：在CDF计算完成（cdf_done脉冲）时立即切换乒乓标志
    // 3. 时序优势：
    //    - vsync↓ (帧N结束) → frame_hist_done脉冲 → 触发CDF计算
    //    - CDF计算 (约25,600周期 @100MHz，64个tile)
    //    - CDF完成 → cdf_done脉冲 → **立即切换ping_pong** ✓
    //    - [帧间隙剩余时间 ~19.7ms]
    //    - vsync↑ (帧N+1开始)
    //    - 第一个href↑ → 映射开始读取RAM（CDF已完成，乒乓已切换，完全就绪）
    // 4. histogram和cdf衔接：
    //    - histogram在vsync↓立即输出frame_hist_done
    //    - cdf模块监听frame_hist_done，立即开始处理
    //    - 无额外延迟，衔接最紧密

    // 检测cdf_done上升沿（用于乒乓切换）
    reg cdf_done_d1;
    wire cdf_done_posedge;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            cdf_done_d1 <= 1'b0;
        end
        else begin
            cdf_done_d1 <= cdf_done;
        end
    end

    assign cdf_done_posedge = cdf_done && !cdf_done_d1;  // cdf_done上升沿

    // 乒乓切换：在CDF完成时切换
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            ping_pong_flag <= 1'b0;
        end
        else if (cdf_done_posedge) begin
            // 优化：在CDF完成时立即切换ping_pong
            // 此时CDF LUT已经完全写入RAM，可以安全切换
            // 下一帧映射将使用新的CDF LUT，消除闪烁
            ping_pong_flag <= !ping_pong_flag;
        end
    end

    // ========================================================================
    // 清零控制逻辑
    // ========================================================================
    // 说明：清零信号由直方图统计模块生成（在vsync下降沿，即帧结束时）
    // hist_clear_start是histogram_stat模块的输出，不需要在此赋值

    // ========================================================================
    // 坐标计数器
    // ========================================================================
    clahe_coord_counter coord_counter_inst (
                            .pclk(pclk),
                            .rst_n(rst_n),
                            .in_href(in_href),
                            .in_vsync(in_vsync),
                            .x_cnt(pixel_x),
                            .y_cnt(pixel_y),
                            .tile_x(tile_x),
                            .tile_y(tile_y),
                            .tile_idx(tile_idx),
                            .local_x(local_x),
                            .local_y(local_y)
                        );

    // ========================================================================
    // 直方图统计模块
    // ========================================================================
    clahe_histogram_stat hist_stat_inst (
                             .pclk(pclk),
                             .rst_n(rst_n),
                             .in_y(in_y),
                             .in_href(in_href),
                             .in_vsync(in_vsync),
                             .tile_idx(tile_idx),
                             .ping_pong_flag(ping_pong_flag),
                             .clear_start(hist_clear_start),
                             .clear_done(hist_clear_done),
                             .ram_rd_tile_idx(hist_rd_tile_idx),
                             .ram_wr_tile_idx(hist_wr_tile_idx),
                             .ram_wr_addr_a(hist_wr_addr),
                             .ram_wr_data_a(hist_wr_data),
                             .ram_wr_en_a(hist_wr_en),
                             .ram_rd_addr_b(hist_rd_addr),
                             .ram_rd_data_b(hist_rd_data),
                             .frame_hist_done(frame_hist_done)
                         );

    // ========================================================================
    // 4-Bank Interleaved Memory (Replaces 64-Tile RAM)
    // ========================================================================
    // Key Optimization: Maps 64 logical tiles to 4 physical RAM banks using
    // checkerboard interleaving. Saves ~93% BRAM compared to 64 linear RAMs.

    localparam TILE_H_BITS = 3;
    localparam TILE_V_BITS = 3;
    localparam TILE_NUM_BITS = 6;

    clahe_ram_banked #(
                         .TILE_H_BITS(TILE_H_BITS),
                         .TILE_V_BITS(TILE_V_BITS),
                         .TILE_NUM_BITS(TILE_NUM_BITS),
                         .BINS(256)
                     ) ram_banked_inst (
                         .pclk(pclk),
                         .rst_n(rst_n),
                         .ping_pong_flag(ping_pong_flag),
                         .clear_start(hist_clear_start),
                         .clear_done(hist_clear_done),

                         // Histogram Statistic Interface
                         .hist_rd_tile_idx(hist_rd_tile_idx),
                         .hist_wr_tile_idx(hist_wr_tile_idx),
                         .hist_wr_addr(hist_wr_addr),
                         .hist_wr_data(hist_wr_data),
                         .hist_wr_en(hist_wr_en),
                         .hist_rd_addr(hist_rd_addr),
                         .hist_rd_data(hist_rd_data),

                         // CDF Calculation Interface
                         .cdf_tile_idx(cdf_tile_idx),
                         .cdf_addr(cdf_addr),
                         .cdf_wr_data(cdf_wr_data),
                         .cdf_wr_en(cdf_wr_en),
                         .cdf_rd_en(cdf_rd_en),
                         .cdf_rd_data(cdf_rd_data),

                         // Mapping Interface (4-Bank Parallel Read)
                         // Note: The RAM module's internal crossbar handles routing based on TL Bank ID
                         .mapping_tl_tile_idx(mapping_tl_tile_idx),
                         .mapping_tr_tile_idx(mapping_tr_tile_idx),
                         .mapping_bl_tile_idx(mapping_bl_tile_idx),
                         .mapping_br_tile_idx(mapping_br_tile_idx),
                         .mapping_addr(mapping_addr),
                         .mapping_tl_rd_data(mapping_tl_rd_data),
                         .mapping_tr_rd_data(mapping_tr_rd_data),
                         .mapping_bl_rd_data(mapping_bl_rd_data),
                         .mapping_br_rd_data(mapping_br_rd_data)
                     );

    // ========================================================================
    // CDF计算模块
    // ========================================================================
    // CDF读使能：当CDF模块在处理时启用读取
    assign cdf_rd_en = cdf_processing;

    clahe_clipper_cdf #(
                          .TILE_NUM(TILE_NUM),
                          .BINS(256),
                          .TILE_PIXELS(TILE_WIDTH * TILE_HEIGHT)
                      ) clipper_cdf_inst (
                          .pclk(pclk),
                          .rst_n(rst_n),
                          .frame_hist_done(frame_hist_done),
                          .clip_limit({8'd0, clip_threshold}),
                          .ping_pong_flag(ping_pong_flag),
                          .hist_rd_tile_idx(cdf_rd_tile_idx),
                          .hist_rd_bin_addr(cdf_rd_addr),
                          .hist_rd_data_a(cdf_rd_data),
                          .hist_rd_data_b(cdf_rd_data),
                          .cdf_wr_tile_idx(cdf_wr_tile_idx),
                          .cdf_wr_bin_addr(cdf_wr_addr),
                          .cdf_wr_data(cdf_wr_data),
                          .cdf_wr_en(cdf_wr_en),
                          .cdf_done(cdf_done),
                          .processing(cdf_processing)
                      );

    // ========================================================================
    // 像素映射模块（并行读取版本） - 四块并行读取CDF LUT
    // ========================================================================
    clahe_mapping_parallel #(
                               .TILE_NUM(TILE_NUM),
                               .BINS(256),
                               .IMG_WIDTH(WIDTH),
                               .IMG_HEIGHT(HEIGHT),
                               .TILE_H(TILE_H),
                               .TILE_V(TILE_V)
                           ) mapping_inst (
                               .pclk(pclk),
                               .rst_n(rst_n),
                               .in_y(in_y),                    // 输入Y分量（原始数据）
                               .in_u(in_u),                    // 输入U分量（原始数据）
                               .in_v(in_v),                    // 输入V分量（原始数据）
                               .in_href(in_href),              // 输入行有效信号
                               .in_vsync(in_vsync),           // 输入场同步信号
                               .tile_idx(tile_idx),            // 输入tile索引（来自coord_counter）
                               .pixel_x(pixel_x),              // 输入像素X坐标（来自coord_counter）
                               .pixel_y(pixel_y),              // 输入像素Y坐标（来自coord_counter）
                               .local_x_in(local_x),           // 输入tile内X坐标（来自coord_counter）
                               .local_y_in(local_y),           // 输入tile内Y坐标（来自coord_counter）
                               .clahe_enable(enable_clahe),    // CLAHE使能信号
                               .interp_enable(enable_interp),  // 插值使能信号
                               .cdf_ready(cdf_done),          // CDF准备就绪信号

                               // 四块并行CDF LUT读接口
                               .cdf_tl_tile_idx(mapping_tl_tile_idx),     // 左上tile索引
                               .cdf_tr_tile_idx(mapping_tr_tile_idx),     // 右上tile索引
                               .cdf_bl_tile_idx(mapping_bl_tile_idx),     // 左下tile索引
                               .cdf_br_tile_idx(mapping_br_tile_idx),     // 右下tile索引
                               .cdf_rd_bin_addr(mapping_addr),            // 读bin地址
                               .cdf_tl_rd_data(mapping_tl_rd_data),       // 左上块读数据
                               .cdf_tr_rd_data(mapping_tr_rd_data),       // 右上块读数据
                               .cdf_bl_rd_data(mapping_bl_rd_data),       // 左下块读数据
                               .cdf_br_rd_data(mapping_br_rd_data),       // 右下块读数据

                               .out_y(mapped_y),              // 输出映射后的Y分量
                               .out_u(mapped_u),              // 输出映射后的U分量
                               .out_v(mapped_v),              // 输出映射后的V分量
                               .out_href(mapped_href),        // 输出映射后的行有效信号
                               .out_vsync(mapped_vsync)       // 输出映射后的场同步信号
                           );

    // ========================================================================
    // 注意：插值功能已集成到mapping模块中，无需独立的插值模块
    // ========================================================================

    // ========================================================================
    // RAM接口架构说明（并行读取版本）
    // ========================================================================
    // 本设计使用128块伪双端口RAM实现乒乓操作：
    //   - 64块RAM_A：当ping_pong_flag=0时用于统计，ping_pong_flag=1时用于映射
    //   - 64块RAM_B：当ping_pong_flag=1时用于统计，ping_pong_flag=0时用于映射
    //
    // 各模块的RAM访问：
    //   1. histogram_stat：写入当前统计RAM组（Port A写 + Port B读）
    //   2. clipper_cdf：读写当前统计RAM组（Port B读直方图 + Port A写CDF LUT）
    //   3. mapping_parallel：并行读取另一组RAM的CDF LUT（Port B四块并行只读）
    //
    // 并行读取特性：
    //   - 四块并行读取：mapping模块同时读取4个相邻tile的CDF数据
    //   - 单周期读取：一个时钟周期内完成四块数据读取
    //   - 高吞吐率：实现1像素/周期的处理能力
    //
    // 端口仲裁已在clahe_ram_64tiles_parallel模块内部实现，无需顶层仲裁逻辑

    // ========================================================================
    // 输出控制 - 集成插值功能的映射模块
    // ========================================================================
    // 输出选择逻辑：
    // 1. CLAHE使能时：使用映射模块输出（支持插值模式）
    // 2. CLAHE禁用时：直接bypass输入
    // 注意：插值功能已集成到mapping模块中，通过interp_enable控制

    // Y分量输出选择
    assign out_y = enable_clahe ? mapped_y : in_y;

    // U/V分量输出选择
    assign out_u = enable_clahe ? mapped_u : in_u;
    assign out_v = enable_clahe ? mapped_v : in_v;

    // 同步信号输出选择
    assign out_href = enable_clahe ? mapped_href : in_href;
    assign out_vsync = enable_clahe ? mapped_vsync : in_vsync;

    // ========================================================================
    // 调试信号
    // ========================================================================
    // 这些信号可以用于调试和验证
    wire [10:0] debug_pixel_x = pixel_x;
    wire [9:0]  debug_pixel_y = pixel_y;
    wire [5:0]  debug_tile_idx = tile_idx;
    wire [7:0]  debug_local_x = local_x;
    wire [7:0]  debug_local_y = local_y;
    wire        debug_ping_pong = ping_pong_flag;
    wire        debug_clear_busy = !hist_clear_done;
    wire        debug_frame_done = frame_hist_done;
    wire        debug_clahe_enable = enable_clahe;
    wire        debug_interp_enable = enable_interp;
    wire        debug_cdf_ready = cdf_done;

    // Aliases for Testbench compatibility
    assign dbg_cdf_processing = cdf_processing;
    assign dbg_cdf_done = cdf_done;
    assign dbg_ping_pong_flag = ping_pong_flag;

endmodule

