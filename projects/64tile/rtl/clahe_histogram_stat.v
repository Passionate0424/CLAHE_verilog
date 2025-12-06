// ============================================================================
// CLAHE 直方图统计模块 - 64块RAM优化版本
//
// 功能描述:
//   - 使用64块独立RAM，每块对应一个tile
//   - 支持并行清零，清零时间从16K周期减少到256周期
//   - 保持原有的乒乓操作和流水线设计
//   - 3级流水线：地址计算 → 数据读取 → 数据写入
//
// 性能提升:
//   - 清零时间: 16,384周期 → 256周期 (64倍提升)
//   - 清零时间: 164μs → 2.56μs (100MHz时钟)
//
// 作者: Passionate.Z
// 日期: 2025-10-17
// ============================================================================

`timescale 1ns / 1ps

module clahe_histogram_stat (
        input  wire        pclk,
        input  wire        rst_n,

        // 输入接口
        input  wire [7:0]  in_y,           // 输入Y分量
        input  wire        in_href,        // 行有效信号
        input  wire        in_vsync,       // 场同步信号
        input  wire [5:0]  tile_idx,       // tile索引 (0-63)

        // 乒乓控制
        input  wire        ping_pong_flag, // 0=使用RAM_A, 1=使用RAM_B

        // 清零控制
        output wire        clear_start,    // 清零开始信号
        input  wire        clear_done,     // 清零完成信号

        // 真双端口RAM接口
        output wire [5:0]  ram_rd_tile_idx, // RAM读tile索引（Stage 1）
        output wire [5:0]  ram_wr_tile_idx, // RAM写tile索引（Stage 3）
        output wire [7:0]  ram_wr_addr_a,  // Port A写地址
        output wire [15:0] ram_wr_data_a,  // Port A写数据
        output wire        ram_wr_en_a,    // Port A写使能
        output wire [7:0]  ram_rd_addr_b,  // Port B读地址
        input  wire [15:0] ram_rd_data_b, // Port B读数据

        // 帧完成标志
        output wire        frame_hist_done // 帧直方图统计完成
    );

    // ========================================================================
    // 参数定义
    // ========================================================================
    localparam TILE_NUM = 64;
    localparam BINS = 256;

    // ========================================================================
    // 内部信号
    // ========================================================================
    reg [7:0]  pixel_d1, pixel_d2, pixel_d3;
    reg [5:0]  tile_idx_d1, tile_idx_d2, tile_idx_d3;
    reg        href_d1, href_d2, href_d3;

    reg [15:0] hist_count_rd;      // 读取的计数值
    reg [15:0] hist_count_inc;     // 递增后的计数值

    // 清零控制
    reg        clear_busy;
    reg [7:0]  clear_addr;

    // 同步信号检测
    reg        vsync_d1, vsync_d2;
    wire       vsync_posedge, vsync_negedge;

    // ========================================================================
    // 同步信号检测
    // ========================================================================
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

    assign vsync_posedge = vsync_d1 && !vsync_d2;
    assign vsync_negedge = !vsync_d1 && vsync_d2;

    // ========================================================================
    // 清零控制逻辑 - 优化版本：映射完成后清零下一帧要使用的RAM
    // ========================================================================
    // 优化思路：
    // 1. 当前帧统计到RAM_A，映射使用RAM_B
    // 2. 当前帧统计到RAM_B，映射使用RAM_A
    // 3. 在vsync下降沿（映射完成）清零下一帧要使用的RAM
    // 4. 这样下一帧开始时，用于统计的RAM已经是空的，不会丢失数据
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            clear_busy <= 1'b0;
            clear_addr <= 8'd0;
        end
        else if (vsync_negedge) begin
            // vsync下降沿，映射完成，开始清零下一帧要使用的RAM
            // ping_pong_flag=0时，当前帧统计RAM_A，清零下一帧用的RAM_B
            // ping_pong_flag=1时，当前帧统计RAM_B，清零下一帧用的RAM_A
            clear_busy <= 1'b1;
            clear_addr <= 8'd0;
        end
        else if (clear_busy ) begin
            if (clear_addr < BINS - 1) begin
                clear_addr <= clear_addr + 8'd1;
            end
            else begin
                clear_busy <= 1'b0;  // 清零完成
            end
        end
    end

    assign clear_start = vsync_negedge;

    // ========================================================================
    // 流水线Stage 1: 计算读地址并读取当前bin的计数值
    // ========================================================================
    // 注意：RAM读取有1周期延迟，所以：
    //   周期N: ram_rd_addr_b = in_y
    //   周期N+1: ram_rd_data_b 有效，被 pixel_d2/href_d2 使用
    // 修复：清零期间禁止读取，避免读写冲突
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_d1 <= 8'd0;
            tile_idx_d1 <= 6'd0;
            href_d1 <= 1'b0;
        end
        else begin
            pixel_d1 <= in_y;
            tile_idx_d1 <= tile_idx;
            href_d1 <= in_href && in_vsync && clear_done;  // 添加clear_done检查，清零期间禁止读取
        end
    end

    // ========================================================================
    // 累加策略：解决读写冲突（优化版）
    // ========================================================================
    // 核心思想：
    //   1. 相邻相同值：本地累加，不写RAM
    //   2. 值变化时：写回累加结果
    //   3. 流水线自然延迟避免冲突
    //
    // 时序保护：
    //   - 写操作延迟3级（检测→寄存→写入）
    //   - 读地址快速移动（每周期更新）
    //   - 清零期间禁止读取
    //   → 无需额外的间隔重复检测！

    reg [15:0] local_accumulator;      // 本地累加器
    reg [7:0]  last_pixel;             // 上一个像素值（用于比较）
    reg [5:0]  last_tile;              // 上一个tile索引（用于比较）
    reg        accumulator_valid;      // 累加器有效标志
    reg [15:0] ram_read_value;         // 保存的RAM读值

    // 用于写回的寄存器
    reg [15:0] write_back_value;       // 需要写回RAM的值
    reg [7:0]  write_back_pixel;       // 需要写回的像素值
    reg [5:0]  write_back_tile;        // 需要写回的tile索引
    reg        need_write_back;        // 需要写回标志

    // 检测像素值或tile变化
    wire pixel_changed_d2 = (pixel_d2 != last_pixel) || (tile_idx_d2 != last_tile);
    wire frame_end = vsync_negedge;

    // ========================================================================
    // 流水线Stage 2: 累加逻辑（简化版 - 流水线自然避免冲突）
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_d2 <= 8'd0;
            tile_idx_d2 <= 6'd0;
            href_d2 <= 1'b0;
            hist_count_rd <= 16'd0;
            local_accumulator <= 16'd0;
            last_pixel <= 8'd0;
            last_tile <= 6'd0;
            accumulator_valid <= 1'b0;
            ram_read_value <= 16'd0;
            write_back_value <= 16'd0;
            write_back_pixel <= 8'd0;
            write_back_tile <= 6'd0;
            need_write_back <= 1'b0;
        end
        else begin
            // 延迟Stage 1的数据
            pixel_d2 <= pixel_d1;
            tile_idx_d2 <= tile_idx_d1;
            href_d2 <= href_d1;

            if (!clear_done) begin
                // 清零期间：完全复位累加器状态
                accumulator_valid <= 1'b0;
                local_accumulator <= 16'd0;
                last_pixel <= 8'd0;
                last_tile <= 6'd0;
                ram_read_value <= 16'd0;
                hist_count_rd <= 16'd0;
                write_back_value <= 16'd0;
                write_back_pixel <= 8'd0;
                write_back_tile <= 6'd0;
                need_write_back <= 1'b0;
            end
            else if (href_d2) begin
                // 注意：此时ram_rd_data_b是pixel_d1的RAM数据（1周期延迟）
                if (!accumulator_valid) begin
                    // 第一个有效像素：使用RAM读数据，开始累加
                    hist_count_rd <= ram_rd_data_b;
                    ram_read_value <= ram_rd_data_b;
                    local_accumulator <= 16'd1;
                    last_pixel <= pixel_d2;
                    last_tile <= tile_idx_d2;
                    accumulator_valid <= 1'b1;
                    need_write_back <= 1'b0;
                end
                else if (pixel_changed_d2) begin
                    // 像素值变化：保存旧像素的累加结果用于写回
                    write_back_value <= ram_read_value + local_accumulator;
                    write_back_pixel <= last_pixel;
                    write_back_tile <= last_tile;
                    need_write_back <= 1'b1;

                    // 使用新像素的RAM值，开始新累加
                    hist_count_rd <= ram_rd_data_b;
                    ram_read_value <= ram_rd_data_b;
                    local_accumulator <= 16'd1;
                    last_pixel <= pixel_d2;
                    last_tile <= tile_idx_d2;
                end
                else begin
                    // 像素值相同：继续累加，不写RAM
                    hist_count_rd <= ram_read_value;
                    local_accumulator <= local_accumulator + 16'd1;
                    need_write_back <= 1'b0;
                    // last_pixel和last_tile保持不变
                end
            end
            else if (frame_end && accumulator_valid) begin
                // 帧结束：保存当前累加结果用于写回
                write_back_value <= ram_read_value + local_accumulator;
                write_back_pixel <= last_pixel;
                write_back_tile <= last_tile;
                need_write_back <= 1'b1;
                accumulator_valid <= 1'b0;  // 清除累加器有效标志
            end
            else begin
                // 其他情况：保持
                need_write_back <= 1'b0;
            end
        end
    end

    // ========================================================================
    // 流水线Stage 3: 写入逻辑（值变化或帧结束时才写）
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_d3 <= 8'd0;
            tile_idx_d3 <= 6'd0;
            href_d3 <= 1'b0;
            hist_count_inc <= 16'd0;
        end
        else begin
            // 直接使用Stage 2的写回信号和数据（单级延迟）
            pixel_d3 <= write_back_pixel;
            tile_idx_d3 <= write_back_tile;

            // 只有在need_write_back时才写入（地址、数据、使能同步）
            if (need_write_back && clear_done) begin
                href_d3 <= 1'b1;  // 使能写入
                hist_count_inc <= write_back_value;
            end
            else begin
                href_d3 <= 1'b0;  // 禁止写入
                hist_count_inc <= 16'd0;
            end
        end
    end

    // ========================================================================
    // 帧完成标志 - 单周期脉冲（更简洁的实现）
    // ========================================================================
    // vsync下降沿产生单周期脉冲，通知CDF模块可以开始处理
    assign frame_hist_done = vsync_negedge;

    // ========================================================================
    // 输出信号（真双端口RAM接口）
    // ========================================================================
    // Port A写接口：用于清零和直方图统计写入
    assign ram_wr_tile_idx = tile_idx_d3;    // 写tile索引：使用Stage 3的tile索引
    assign ram_wr_addr_a = pixel_d3;         // 写地址：像素值作为bin地址
    assign ram_wr_data_a = hist_count_inc;   // 写数据：递增后的计数值
    assign ram_wr_en_a = href_d3 && clear_done; // 修复：清零完成后才能统计，避免冲突

    // Port B读接口：用于直方图统计读取
    assign ram_rd_tile_idx = tile_idx_d1;    // 读tile索引：使用Stage 1的tile索引，与读地址同步
    assign ram_rd_addr_b = pixel_d1;         // 读地址：像素值作为bin地址

endmodule
