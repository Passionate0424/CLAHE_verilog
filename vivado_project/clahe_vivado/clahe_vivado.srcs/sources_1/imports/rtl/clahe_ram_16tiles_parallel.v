// ============================================================================
// CLAHE 16块并行读取RAM架构 - 支持四块并行读取
//
// 功能描述:
//   - 32块伪双端口RAM（16块RAM_A + 16块RAM_B），每块对应一个tile
//   - 每块RAM: 256深度 × 16bit宽度 (256个灰度级)
//   - 支持同时读写操作，解决时序冲突问题
//   - 支持并行清零，清零时间256周期
//   - 乒乓操作：16块RAM_A和16块RAM_B
//   - 支持四块并行读取，用于映射模块
//
// 并行读取特点:
//   - 4个独立读端口：TL, TR, BL, BR
//   - 每个端口可独立访问任意tile
//   - 单周期读取四个相邻块的CDF数据
//   - 消除串行读取的时序复杂性
//
// 性能特点:
//   - 映射处理：4周期 → 1周期 (4倍提升)
//   - 流水线级数：9级 → 5级 (简化44%)
//   - 处理吞吐率：1像素/4周期 → 1像素/周期
//
// 作者: Passionate.Z
// 日期: 2025-10-25
// ============================================================================

`timescale 1ns / 1ps

module clahe_ram_16tiles_parallel (
        input  wire        pclk,
        input  wire        rst_n,

        // 乒乓控制
        input  wire        ping_pong_flag,  // 0=统计RAM_A/映射RAM_B, 1=统计RAM_B/映射RAM_A

        // 清零控制
        input  wire        clear_start,     // 清零开始信号
        output wire        clear_done,      // 清零完成信号

        // ====================================================================
        // 直方图统计接口（使用当前统计RAM组）
        // ====================================================================
        input  wire [3:0]  hist_rd_tile_idx, // 读tile索引 (0-15)
        input  wire [3:0]  hist_wr_tile_idx, // 写tile索引 (0-15)
        input  wire [7:0]  hist_wr_addr,    // 写地址 (0-255)
        input  wire [15:0] hist_wr_data,    // 写数据（16bit直方图计数）
        input  wire        hist_wr_en,      // 写使能
        input  wire [7:0]  hist_rd_addr,    // 读地址 (0-255)
        output wire [15:0] hist_rd_data,    // 读数据（16bit直方图计数）

        // ====================================================================
        // CDF计算接口（使用当前统计RAM组）
        // ====================================================================
        input  wire [3:0]  cdf_tile_idx,    // tile索引 (0-15)
        input  wire [7:0]  cdf_addr,        // 地址 (0-255)
        input  wire [7:0]  cdf_wr_data,     // 写数据（8bit CDF LUT）
        input  wire        cdf_wr_en,       // 写使能
        input  wire        cdf_rd_en,       // 读使能（用于读直方图）
        output wire [15:0] cdf_rd_data,     // 读数据（16bit直方图或8bit CDF LUT）

        // ====================================================================
        // 四块并行映射接口（使用另一组RAM - 上一帧的CDF LUT）
        // ====================================================================
        // 四个相邻块的并行读取
        input  wire [3:0]  mapping_tl_tile_idx, // 左上tile索引 (0-15)
        input  wire [3:0]  mapping_tr_tile_idx, // 右上tile索引 (0-15)
        input  wire [3:0]  mapping_bl_tile_idx, // 左下tile索引 (0-15)
        input  wire [3:0]  mapping_br_tile_idx, // 右下tile索引 (0-15)
        input  wire [7:0]  mapping_addr,        // 地址 (0-255) - 四个块使用相同地址
        output wire [7:0]  mapping_tl_rd_data,  // 左上块读数据（8bit CDF LUT）
        output wire [7:0]  mapping_tr_rd_data,  // 右上块读数据（8bit CDF LUT）
        output wire [7:0]  mapping_bl_rd_data,  // 左下块读数据（8bit CDF LUT）
        output wire [7:0]  mapping_br_rd_data   // 右下块读数据（8bit CDF LUT）
    );

    // ========================================================================
    // 参数定义
    // ========================================================================
    localparam TILE_NUM = 16;
    localparam BINS = 256;
    localparam ADDR_WIDTH = 8;

    // ========================================================================
    // 清零控制逻辑
    // ========================================================================
    // 清零策略：清零下一帧要使用的RAM组
    // - ping_pong_flag=0时，当前帧统计RAM_A，下一帧统计RAM_B，清零RAM_B
    // - ping_pong_flag=1时，当前帧统计RAM_B，下一帧统计RAM_A，清零RAM_A
    // - 复位后：清零两组RAM（通过两轮清零）
    reg        clear_busy;
    reg [7:0]  clear_addr;
    reg        init_clear_done;  // 标记初始化清零是否完成

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            clear_busy <= 1'b1;  // 修复：复位后自动开始清零
            clear_addr <= 8'd0;
            init_clear_done <= 1'b0;
        end
        else if (clear_start && !clear_busy) begin  // 修复：只在不busy时响应新的清零请求
            clear_busy <= 1'b1;
            clear_addr <= 8'd0;
        end
        else if (clear_busy) begin
            if (clear_addr < BINS - 1) begin
                clear_addr <= clear_addr + 8'd1;
            end
            else begin
                // 初始化时需要清零两组RAM
                if (!init_clear_done) begin
                    // 第一轮清零完成，自动开始第二轮
                    init_clear_done <= 1'b1;
                    clear_addr <= 8'd0;  // 重新开始第二轮清零
                    // clear_busy保持为1，继续清零
                end
                else begin
                    // 第二轮清零完成，或者正常清零完成
                    clear_busy <= 1'b0;
                end
            end
        end
    end

    assign clear_done = !clear_busy;

    // ========================================================================
    // RAM_A组（16块伪双端口RAM）- 当ping_pong_flag=0时用于统计
    // ========================================================================
    wire [15:0] ram_a_dout_b [0:15];    // Port B读数据
    wire        ram_a_we_a [0:15];      // Port A写使能
    wire [7:0]  ram_a_addr_a [0:15];    // Port A地址
    wire [15:0] ram_a_din_a [0:15];     // Port A写数据
    wire [7:0]  ram_a_addr_b [0:15];    // Port B地址

    // ========================================================================
    // RAM_B组（16块伪双端口RAM）- 当ping_pong_flag=1时用于统计
    // ========================================================================
    wire [15:0] ram_b_dout_b [0:15];    // Port B读数据
    wire        ram_b_we_a [0:15];      // Port A写使能
    wire [7:0]  ram_b_addr_a [0:15];    // Port A地址
    wire [15:0] ram_b_din_a [0:15];     // Port A写数据
    wire [7:0]  ram_b_addr_b [0:15];    // Port B地址

    // ========================================================================
    // 生成16块RAM_A
    // ========================================================================
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_ram_a
            // ================================================================
            // Port A写控制逻辑（清零、直方图统计写入、CDF LUT写入）
            // ================================================================
            // 优先级：清零 > CDF写入 > 统计写入
            // 清零策略：ping_pong_flag=1时清零RAM_A（为下一帧统计准备）
            // 初始化时（init_clear_done=0）同时清零RAM_A和RAM_B

            assign ram_a_we_a[i] =
                   (clear_busy && (ping_pong_flag || !init_clear_done)) ? 1'b1 :  // 清零（初始化或正常清零）
                   (cdf_wr_en && !ping_pong_flag && cdf_tile_idx == i) ? 1'b1 :   // CDF写入
                   (hist_wr_en && !ping_pong_flag && hist_wr_tile_idx == i) ? 1'b1 : 1'b0; // 统计写入

            assign ram_a_addr_a[i] =
                   (clear_busy && (ping_pong_flag || !init_clear_done)) ? clear_addr :  // 清零地址
                   (cdf_wr_en && !ping_pong_flag && cdf_tile_idx == i) ? cdf_addr :     // CDF地址
                   (hist_wr_en && !ping_pong_flag && hist_wr_tile_idx == i) ? hist_wr_addr : 8'd0; // 统计地址

            assign ram_a_din_a[i] =
                   (clear_busy && (ping_pong_flag || !init_clear_done)) ? 16'd0 :       // 清零数据
                   (cdf_wr_en && !ping_pong_flag && cdf_tile_idx == i) ? {8'd0, cdf_wr_data} : // CDF数据
                   (hist_wr_en && !ping_pong_flag && hist_wr_tile_idx == i) ? hist_wr_data : 16'd0; // 统计数据

            // ================================================================
            // Port B读控制逻辑（直方图统计读取、CDF读取、映射读取）
            // ================================================================
            // ping_pong_flag=0时：统计读取 + CDF读取
            // ping_pong_flag=1时：映射读取（四块并行）

            assign ram_a_addr_b[i] =
                   (!ping_pong_flag && hist_rd_tile_idx == i) ? hist_rd_addr :  // 统计读取
                   (!ping_pong_flag && cdf_rd_en && cdf_tile_idx == i) ? cdf_addr : // CDF读取
                   (ping_pong_flag && (mapping_tl_tile_idx == i || mapping_tr_tile_idx == i ||
                                       mapping_bl_tile_idx == i || mapping_br_tile_idx == i)) ? mapping_addr : 8'd0; // 映射读取

            // ================================================================
            // 使用RAM行为模型
            // ================================================================
            clahe_simple_dual_ram_model #(
                                            .DATA_WIDTH(16),
                                            .ADDR_WIDTH(8),
                                            .DEPTH(256)
                                        ) ram_a_inst (
                                            .clk_a(pclk),
                                            .we_a(ram_a_we_a[i]),
                                            .addr_a(ram_a_addr_a[i]),
                                            .din_a(ram_a_din_a[i]),
                                            .clk_b(pclk),
                                            .addr_b(ram_a_addr_b[i]),
                                            .dout_b(ram_a_dout_b[i])
                                        );
        end
    endgenerate

    // ========================================================================
    // 生成16块RAM_B
    // ========================================================================
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_ram_b
            // ================================================================
            // Port A写控制逻辑（清零、直方图统计写入、CDF LUT写入）
            // ================================================================
            // 优先级：清零 > CDF写入 > 统计写入
            // 清零策略：ping_pong_flag=0时清零RAM_B（为下一帧统计准备）
            // 初始化时（init_clear_done=0）同时清零RAM_A和RAM_B

            assign ram_b_we_a[i] =
                   (clear_busy && (!ping_pong_flag || !init_clear_done)) ? 1'b1 :      // 清零（初始化或正常清零）
                   (cdf_wr_en && ping_pong_flag && cdf_tile_idx == i) ? 1'b1 :         // CDF写入
                   (hist_wr_en && ping_pong_flag && hist_wr_tile_idx == i) ? 1'b1 : 1'b0; // 统计写入

            assign ram_b_addr_a[i] =
                   (clear_busy && (!ping_pong_flag || !init_clear_done)) ? clear_addr :     // 清零地址
                   (cdf_wr_en && ping_pong_flag && cdf_tile_idx == i) ? cdf_addr :          // CDF地址
                   (hist_wr_en && ping_pong_flag && hist_wr_tile_idx == i) ? hist_wr_addr : 8'd0; // 统计地址

            assign ram_b_din_a[i] =
                   (clear_busy && (!ping_pong_flag || !init_clear_done)) ? 16'd0 :          // 清零数据
                   (cdf_wr_en && ping_pong_flag && cdf_tile_idx == i) ? {8'd0, cdf_wr_data} : // CDF数据
                   (hist_wr_en && ping_pong_flag && hist_wr_tile_idx == i) ? hist_wr_data : 16'd0; // 统计数据

            // ================================================================
            // Port B读控制逻辑（直方图统计读取、CDF读取、映射读取）
            // ================================================================
            // ping_pong_flag=1时：统计读取 + CDF读取
            // ping_pong_flag=0时：映射读取（四块并行）

            assign ram_b_addr_b[i] =
                   (ping_pong_flag && hist_rd_tile_idx == i) ? hist_rd_addr :   // 统计读取
                   (ping_pong_flag && cdf_rd_en && cdf_tile_idx == i) ? cdf_addr : // CDF读取
                   (!ping_pong_flag && (mapping_tl_tile_idx == i || mapping_tr_tile_idx == i ||
                                        mapping_bl_tile_idx == i || mapping_br_tile_idx == i)) ? mapping_addr : 8'd0; // 映射读取

            // ================================================================
            // 使用RAM行为模型
            // ================================================================
            clahe_simple_dual_ram_model #(
                                            .DATA_WIDTH(16),
                                            .ADDR_WIDTH(8),
                                            .DEPTH(256)
                                        ) ram_b_inst (
                                            .clk_a(pclk),
                                            .we_a(ram_b_we_a[i]),
                                            .addr_a(ram_b_addr_a[i]),
                                            .din_a(ram_b_din_a[i]),
                                            .clk_b(pclk),
                                            .addr_b(ram_b_addr_b[i]),
                                            .dout_b(ram_b_dout_b[i])
                                        );
        end
    endgenerate

    // ========================================================================
    // 读数据选择：根据乒乓标志和操作类型选择对应的RAM数据
    // ========================================================================

    // 直方图统计读数据（从当前统计RAM组读取）
    assign hist_rd_data = (!ping_pong_flag) ? ram_a_dout_b[hist_rd_tile_idx] : ram_b_dout_b[hist_rd_tile_idx];

    // CDF读数据（从当前统计RAM组读取16bit直方图或8bit CDF LUT）
    assign cdf_rd_data = (!ping_pong_flag) ? ram_a_dout_b[cdf_tile_idx] : ram_b_dout_b[cdf_tile_idx];

    // ========================================================================
    // 四块并行映射读数据（从另一组RAM读取8bit CDF LUT）
    // ========================================================================
    // 修复：需要锁存tile索引，确保索引与RAM输出时序匹配
    // RAM读取延迟1周期，所以必须延迟tile索引
    reg [3:0] mapping_tl_tile_idx_d1;
    reg [3:0] mapping_tr_tile_idx_d1;
    reg [3:0] mapping_bl_tile_idx_d1;
    reg [3:0] mapping_br_tile_idx_d1;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            mapping_tl_tile_idx_d1 <= 4'd0;
            mapping_tr_tile_idx_d1 <= 4'd0;
            mapping_bl_tile_idx_d1 <= 4'd0;
            mapping_br_tile_idx_d1 <= 4'd0;
        end
        else begin
            mapping_tl_tile_idx_d1 <= mapping_tl_tile_idx;
            mapping_tr_tile_idx_d1 <= mapping_tr_tile_idx;
            mapping_bl_tile_idx_d1 <= mapping_bl_tile_idx;
            mapping_br_tile_idx_d1 <= mapping_br_tile_idx;
        end
    end

    // 根据乒乓标志和延迟后的索引选择对应的RAM数据
    wire [15:0] mapping_tl_rd_data_16bit = (ping_pong_flag) ? ram_a_dout_b[mapping_tl_tile_idx_d1] : ram_b_dout_b[mapping_tl_tile_idx_d1];
    wire [15:0] mapping_tr_rd_data_16bit = (ping_pong_flag) ? ram_a_dout_b[mapping_tr_tile_idx_d1] : ram_b_dout_b[mapping_tr_tile_idx_d1];
    wire [15:0] mapping_bl_rd_data_16bit = (ping_pong_flag) ? ram_a_dout_b[mapping_bl_tile_idx_d1] : ram_b_dout_b[mapping_bl_tile_idx_d1];
    wire [15:0] mapping_br_rd_data_16bit = (ping_pong_flag) ? ram_a_dout_b[mapping_br_tile_idx_d1] : ram_b_dout_b[mapping_br_tile_idx_d1];

    // 只取低8位作为CDF LUT数据
    assign mapping_tl_rd_data = mapping_tl_rd_data_16bit[7:0];
    assign mapping_tr_rd_data = mapping_tr_rd_data_16bit[7:0];
    assign mapping_bl_rd_data = mapping_bl_rd_data_16bit[7:0];
    assign mapping_br_rd_data = mapping_br_rd_data_16bit[7:0];

endmodule

