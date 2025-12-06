// ============================================================================
// CLAHE 直方图统计模块 - 简化重构版
//
// 设计思路：
//   1. 参考代码的流水线结构（3级）
//   2. 参考代码的相邻相同检测
//   3. 手动旁路逻辑处理间隔冲突（易灵思READ_FIRST）
//
// 流水线结构：
//   Stage 1: 输入打拍 + 相邻相同检测
//   Stage 2: RAM读取 + 旁路数据选择
//   Stage 3: RAM写入
//
// 冲突处理：
//   - 相邻相同（AA）：检测到后写+2而不是+1
//   - 间隔相同（ABA）：旁路逻辑返回新写入的数据
//
// 作者: Passionate.Z
// 日期: 2025-10-31
// ============================================================================

`timescale 1ns / 1ps

module clahe_histogram_stat #(
        parameter TILE_NUM_BITS = 6
    )(
        input  wire        pclk,
        input  wire        rst_n,

        // 输入接口
        input  wire [7:0]  in_y,           // 输入Y分量
        input  wire        in_href,        // 行有效信号
        input  wire        in_vsync,       // 场同步信号
        input  wire [TILE_NUM_BITS-1:0] tile_idx,       // tile索引

        // 乒乓控制
        input  wire        ping_pong_flag,

        // 清零控制
        output wire        clear_start,
        input  wire        clear_done,

        // RAM接口
        output wire [TILE_NUM_BITS-1:0] ram_rd_tile_idx,
        output wire [TILE_NUM_BITS-1:0] ram_wr_tile_idx,
        output wire [7:0]  ram_wr_addr_a,
        output wire [15:0] ram_wr_data_a,
        output wire        ram_wr_en_a,
        output wire [7:0]  ram_rd_addr_b,
        input  wire [15:0] ram_rd_data_b,

        // 帧完成标志
        output wire        frame_hist_done
    );

    // ========================================================================
    // 信号边沿检测
    // ========================================================================
    reg vsync_d;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n)
            vsync_d <= 1'b0;
        else
            vsync_d <= in_vsync;
    end

    wire vsync_pos = in_vsync && !vsync_d;  // Frame Start
    wire vsync_neg = !in_vsync && vsync_d;  // Frame End

    // ========================================================================
    // 输出信号生成
    // ========================================================================
    // Clear Start: Trigger at Frame Start (VSync Posedge) to clear the NEW active bank
    assign clear_start = vsync_pos;

    // Frame Hist Done: Trigger at Frame End (VSync Negedge) to start Clipper on the COMPLETED bank
    assign frame_hist_done = vsync_neg;
    // Stage 1: 输入打拍 + 相邻相同检测
    // ========================================================================
    reg [7:0]  pixel_s1;
    reg [TILE_NUM_BITS-1:0] tile_s1;
    reg        valid_s1;
    reg        same_as_prev;   // 与上一个相同的标志

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_s1 <= 8'd0;
            tile_s1 <= {TILE_NUM_BITS{1'b0}};
            valid_s1 <= 1'b0;
            same_as_prev <= 1'b0;
        end
        else begin
            pixel_s1 <= in_y;
            tile_s1 <= tile_idx;
            // valid_s1 depends on inputs and clear_done
            // Also need to handle boundary conditions if necessary
            valid_s1 <= in_href && in_vsync && clear_done;

            // Same pixel detection for Read-Modify-Write optimization
            // If current input is valid and same as currently latched pixel (previous cycle input)
            if ((in_y == pixel_s1) && (tile_idx == tile_s1) && (in_href && in_vsync && clear_done)) begin
                same_as_prev <= 1'b1;
            end
            else begin
                same_as_prev <= 1'b0;
            end
        end
    end

    // ========================================================================
    // Stage 2: RAM读取 + 旁路数据选择
    // ========================================================================
    reg [7:0]  pixel_s2;
    reg [TILE_NUM_BITS-1:0] tile_s2;
    reg        valid_s2;
    reg        same_s2;
    reg [1:0]  increment_s2;  // 增量：1或2

    // ========================================================================
    // Stage 3: 寄存器声明（需要在旁路逻辑之前声明）
    // ========================================================================
    reg [7:0]  pixel_s3;
    reg [TILE_NUM_BITS-1:0] tile_s3;
    reg        valid_s3;
    reg [15:0] ram_data_s3;
    reg [15:0] ram_wr_data_s3;

    // ========================================================================
    // 旁路逻辑：检测读写冲突
    // ========================================================================
    reg        bypass_valid;
    reg [15:0] bypass_data;

    // 冲突检测：Stage1读地址 == Stage3写地址
    wire conflict = (pixel_s1 == pixel_s3) &&
         (tile_s1 == tile_s3) &&
         valid_s3;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            bypass_valid <= 1'b0;
            bypass_data <= 16'd0;
        end
        else begin
            if (conflict) begin
                bypass_valid <= 1'b1;
                bypass_data <= ram_wr_data_s3;  // 保存写入的数据
            end
            else begin
                bypass_valid <= 1'b0;
            end
        end
    end

    // 数据选择：旁路优先
    wire [15:0] selected_data = bypass_valid ? bypass_data : ram_rd_data_b;

    // ========================================================================
    // Stage 2: 流水线逻辑
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_s2 <= 8'd0;
            tile_s2 <= {TILE_NUM_BITS{1'b0}};
            valid_s2 <= 1'b0;
            same_s2 <= 1'b0;
            increment_s2 <= 2'd1;
        end
        else begin
            pixel_s2 <= pixel_s1;
            tile_s2 <= tile_s1;
            valid_s2 <= valid_s1;
            same_s2 <= same_as_prev;

            // 设置增量：相邻相同+2，否则+1
            if (same_as_prev) begin
                increment_s2 <= 2'd2;
            end
            else begin
                increment_s2 <= 2'd1;
            end
        end
    end

    // ========================================================================
    // Stage 3: RAM写入逻辑
    // ========================================================================

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_s3 <= 8'd0;
            tile_s3 <= {TILE_NUM_BITS{1'b0}};
            valid_s3 <= 1'b0;
            ram_data_s3 <= 16'd0;
            ram_wr_data_s3 <= 16'd0;
        end
        else begin
            pixel_s3 <= pixel_s2;
            tile_s3 <= tile_s2;
            valid_s3 <= valid_s2;
            ram_data_s3 <= selected_data;

            // 计算写入值：旧值 + 增量
            ram_wr_data_s3 <= selected_data + increment_s2;
        end
    end

    // ========================================================================
    // RAM接口连接
    // ========================================================================
    // Port B: 读接口（Stage 1）
    assign ram_rd_tile_idx = tile_s1;
    assign ram_rd_addr_b = pixel_s1;

    // Port A: 写接口（Stage 3）
    assign ram_wr_tile_idx = tile_s3;
    assign ram_wr_addr_a = pixel_s3;
    assign ram_wr_data_a = ram_wr_data_s3;
    assign ram_wr_en_a = valid_s3 && clear_done;

endmodule

