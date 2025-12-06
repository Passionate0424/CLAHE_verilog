// ============================================================================
// CLAHE 对比度限制与CDF计算模块
//
// 功能描述:
//   - 在帧间隙期处理上一帧的直方图数据
//   - 对直方图进行对比度限制(Clip)操作，防止过度增强
//   - 重分配溢出的计数值到其他bins
//   - 计算累积分布函数(CDF)，用于像素映射
//   - 生成像素映射查找表，存储到CDF LUT RAM
//
// 处理流程:
//   1. 读取64个tile的直方图数据（每个tile有256个bins）
//   2. Clip操作：限制超过阈值的bins，将溢出值重分配到其他bins
//   3. CDF计算：对clip后的直方图进行累积求和
//   4. 归一化：将CDF值映射到0-255范围，生成查找表
//   5. 写入CDF LUT RAM：供后续像素映射使用
//
// 时序分析:
//   - 每tile处理时间：约400个时钟周期
//   - 总处理时间：64 × 400 = 25,600周期
//   - 在74MHz时钟下：约0.34ms完成所有处理
//   - 帧间隙时间充足：33ms@30fps，处理时间占比<1%
//
// 关键算法:
//   - Clip阈值：clip_limit = (tile_pixels / 256) × clip_factor
//   - 溢出重分配：将超出clip_limit的计数值平均分配到所有bins
//   - CDF归一化：cdf_norm = (cdf[i] × 255) / tile_pixels
//
// 作者: Passionate.Z
// 日期: 2025-10-15
// ============================================================================

module clahe_clipper_cdf #(
        parameter TILE_NUM = 64,
        parameter BINS = 256,
        parameter TILE_PIXELS = 14400  // 160*90
    )(
        input  wire         pclk,
        input  wire         rst_n,

        // 控制信号
        input  wire         frame_hist_done,    // 直方图统计完成，触发处理
        input  wire [15:0]  clip_limit,         // 裁剪阈值
        input  wire         ping_pong_flag,     // 读取哪个hist RAM (与统计相反)

        // 直方图RAM读接口
        output reg  [5:0]   hist_rd_tile_idx,   // 读tile索引 (0-63)
        output reg  [7:0]   hist_rd_bin_addr,   // 读bin地址 (0-255)
        input  wire [15:0]  hist_rd_data_a,     // RAM A数据
        input  wire [15:0]  hist_rd_data_b,     // RAM B数据

        // CDF LUT写入接口（写入64块RAM）
        output reg  [5:0]   cdf_wr_tile_idx,   // 写tile索引
        output reg  [7:0]   cdf_wr_bin_addr,   // 写bin地址
        output reg  [7:0]   cdf_wr_data,        // 映射后的灰度值
        output reg          cdf_wr_en,         // 写使能

        // 状态输出
        output reg          cdf_done,           // CDF计算完成，可开始映射
        output reg          processing          // 处理中标志
    );

    // ========================================================================
    // 状态机定义
    // ========================================================================
    // 状态机用于控制整个CDF计算流程
    // 每个状态对应一个处理阶段，确保数据处理的正确性
    localparam IDLE           = 4'd0;  // 空闲状态，等待触发
    localparam READ_HIST      = 4'd1;  // 读取直方图数据到缓存
    localparam CLIP_SCAN      = 4'd2;  // 扫描需要clip的bins
    localparam CLIP_REDIST    = 4'd3;  // 重分配溢出值到其他bins
    localparam CALC_CDF       = 4'd4;  // 计算累积分布函数
    localparam WRITE_LUT      = 4'd5;  // 写入CDF查找表到RAM
    localparam NEXT_TILE      = 4'd6;  // 处理下一个tile
    localparam DONE           = 4'd7;  // 所有tile处理完成
    localparam DONE_PULSE     = 4'd8;  // 完成脉冲状态，用于重置cdf_done

    reg  [3:0]  state, next_state;       // 当前状态和下一状态

    // ========================================================================
    // 内部寄存器和信号
    // ========================================================================
    reg  [5:0]  tile_cnt;              // 当前处理的tile索引(0-63)
    reg  [8:0]  bin_cnt;               // 当前处理的bin索引(0-256)，需要9位以支持RAM读延迟

    // frame_hist_done现在是单周期脉冲，无需边沿检测

    // 直方图缓存（单个tile的256个bins）
    reg  [15:0] hist_buf [0:255];      // 原始直方图缓存
    reg  [15:0] hist_clipped [0:255];  // clip后的直方图缓存

    // Clip相关信号
    reg  [31:0] excess_total;          // 总溢出量（所有超出clip_limit的计数值）
    wire [23:0] excess_base;           // 每个bin的基础分配量（除法结果）
    wire [7:0]  excess_remainder;      // 余数（需要额外分配给前remainder个bins）

    // CDF相关信号
    reg  [31:0] cdf [0:255];           // 累积分布函数数组
    reg  [31:0] cdf_min;               // CDF最小值（第一个非零值）
    reg  [31:0] cdf_max;               // CDF最大值（用于归一化）
    reg  [31:0] cdf_range;             // CDF范围（最大值-最小值）
    reg  [31:0] cdf_temp;              // 临时累加值

    // 乒乓RAM数据选择
    // CDF读取当前帧统计的RAM（与统计写入同一组）
    // ping_pong_flag=0：统计写RAM_A，CDF读RAM_A
    // ping_pong_flag=1：统计写RAM_B，CDF读RAM_B
    wire [15:0] hist_rd_data;           // 根据ping_pong_flag选择读取的RAM数据
    assign hist_rd_data = ping_pong_flag ? hist_rd_data_b : hist_rd_data_a;

    // Clip优化：使用组合逻辑计算基础分配量和余数（确保像素总数守恒）
    // 标准CLAHE算法：base = excess_total / 256, remainder = excess_total % 256
    // 前remainder个bins分配(base+1)个像素，其余bins分配base个像素
    assign excess_base = excess_total[31:8];      // 除以256：取高24位
    assign excess_remainder = excess_total[7:0];  // 模256：取低8位


    integer i;

    // ========================================================================
    // 状态机 - 时序逻辑
    // ========================================================================
    // 功能：状态机的时序部分，在每个时钟上升沿更新状态
    // 复位：系统复位时回到IDLE状态
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;  // 复位时回到空闲状态
        end
        else begin
            state <= next_state;  // 更新到下一状态
        end
    end

    // ========================================================================
    // 状态机 - 组合逻辑
    // ========================================================================
    // 功能：状态机的组合逻辑部分，根据当前状态和条件决定下一状态
    // 状态转换：IDLE → READ_HIST → CLIP_SCAN → CLIP_REDIST → CALC_CDF → WRITE_LUT → NEXT_TILE → DONE
    always @(*) begin
        next_state = state;  // 默认保持当前状态

        case (state)
            IDLE: begin
                // 空闲状态：等待直方图统计完成脉冲
                if (frame_hist_done) begin
                    next_state = READ_HIST;  // 开始读取直方图数据
                end
            end

            READ_HIST: begin
                // 读取直方图状态：逐个读取256个bins的数据
                // 修复：由于RAM有1周期延迟，需要读取257个周期（0-256）
                if (bin_cnt == 9'd256) begin
                    next_state = CLIP_SCAN;  // 读取完成，开始clip扫描
                end
            end

            CLIP_SCAN: begin
                // Clip扫描状态：检查哪些bins需要clip
                if (bin_cnt == 255) begin
                    if (excess_total > 0) begin
                        next_state = CLIP_REDIST;  // 有溢出，需要重分配
                    end
                    else begin
                        next_state = CALC_CDF;     // 无溢出，直接计算CDF
                    end
                end
            end

            CLIP_REDIST: begin
                // Clip重分配状态：将溢出值重分配到其他bins
                if (bin_cnt == 255) begin
                    next_state = CALC_CDF;  // 重分配完成，开始计算CDF
                end
            end

            CALC_CDF: begin
                // CDF计算状态：计算累积分布函数
                if (bin_cnt == 255) begin
                    next_state = WRITE_LUT;  // CDF计算完成，开始写入查找表
                end
            end

            WRITE_LUT: begin
                // 写入查找表状态：将CDF结果写入RAM
                // 修复：需要257个周期（1个计算cdf_range + 256个写入）
                if (bin_cnt == 256) begin
                    next_state = NEXT_TILE;  // 写入完成，处理下一个tile
                end
            end

            NEXT_TILE: begin
                // 下一个tile状态：检查是否还有tile需要处理
                if (tile_cnt == TILE_NUM - 1) begin
                    next_state = DONE;       // 所有tile处理完成
                end
                else begin
                    next_state = READ_HIST;  // 还有tile，继续处理
                end
            end

            DONE: begin
                // 完成状态：所有处理完成，进入脉冲状态
                next_state = DONE_PULSE;
            end

            DONE_PULSE: begin
                // 脉冲状态：重置cdf_done信号，然后回到空闲状态
                next_state = IDLE;
            end

            default:
                next_state = IDLE;  // 异常情况，回到空闲状态
        endcase
    end

    // ========================================================================
    // 处理逻辑
    // ========================================================================
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            tile_cnt <= 6'd0;
            bin_cnt <= 9'd0;
            excess_total <= 32'd0;
            cdf_min <= 32'd0;
            cdf_max <= 32'd0;
            cdf_range <= 32'd0;
            cdf_temp <= 32'd0;
            hist_rd_tile_idx <= 6'd0;
            hist_rd_bin_addr <= 8'd0;
            cdf_wr_tile_idx <= 6'd0;
            cdf_wr_bin_addr <= 8'd0;
            cdf_wr_data <= 8'd0;
            cdf_wr_en <= 1'b0;
            processing <= 1'b0;
            cdf_done <= 1'b0;

            for (i = 0; i < 256; i = i + 1) begin
                hist_buf[i] <= 16'd0;
                hist_clipped[i] <= 16'd0;
                cdf[i] <= 32'd0;
            end
        end
        else begin
            case (state)
                // ============================================================
                // IDLE: 等待触发
                // ============================================================
                IDLE: begin
                    // 保持所有RAM信号稳定，避免X态
                    hist_rd_tile_idx <= 6'd0;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= 6'd0;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    if (frame_hist_done) begin
                        tile_cnt <= 6'd0;
                        bin_cnt <= 9'd0;
                        processing <= 1'b1;
                    end
                end

                // ============================================================
                // READ_HIST: 读取当前tile的256个bins
                // ============================================================
                READ_HIST: begin
                    hist_rd_tile_idx <= tile_cnt;    // 选择当前tile对应的RAM
                    cdf_wr_tile_idx <= tile_cnt;     // 保持CDF写信号稳定
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    // 修复：RAM有1周期延迟，需要257个周期完成读取
                    // 周期0-255: 发出地址0-255
                    // 周期1-256: 接收数据0-255
                    if (bin_cnt < 9'd256) begin
                        hist_rd_bin_addr <= bin_cnt[7:0];  // 发送地址（0-255）
                    end

                    // 从周期1开始存储数据（周期0没有有效数据）
                    if (bin_cnt > 0 && bin_cnt <= 9'd256) begin
                        hist_buf[bin_cnt[7:0] - 1] <= hist_rd_data;
                    end

                    if (bin_cnt < 9'd256) begin
                        bin_cnt <= bin_cnt + 9'd1;
                    end
                    else begin
                        bin_cnt <= 9'd0;
                    end
                end

                // ============================================================
                // CLIP_SCAN: 扫描并计算溢出量
                // ============================================================
                CLIP_SCAN: begin
                    // 保持RAM信号稳定，避免X态
                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= tile_cnt;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    if (bin_cnt == 0) begin
                        excess_total <= 32'd0;
                    end
                    else if (hist_buf[bin_cnt[7:0]] > clip_limit) begin
                        // 超过阈值，计算溢出量
                        excess_total <= excess_total + (hist_buf[bin_cnt[7:0]] - clip_limit);
                        hist_clipped[bin_cnt[7:0]] <= clip_limit;
                    end
                    else begin
                        hist_clipped[bin_cnt[7:0]] <= hist_buf[bin_cnt[7:0]];
                    end

                    if (bin_cnt < 9'd255) begin
                        bin_cnt <= bin_cnt + 9'd1;
                    end
                    else begin
                        bin_cnt <= 9'd0;
                    end
                end

                // ============================================================
                // CLIP_REDIST: 重分配溢出量到所有bins（标准CLAHE，确保像素守恒）
                // ============================================================
                CLIP_REDIST: begin
                    // 保持RAM信号稳定，避免X态
                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= tile_cnt;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    // 标准CLAHE：像素总数守恒的分配策略
                    // 前remainder个bins分配(base+1)，其余bins分配base
                    if (bin_cnt < excess_remainder) begin
                        // 前remainder个bins多分配1个像素
                        hist_clipped[bin_cnt[7:0]] <= hist_clipped[bin_cnt[7:0]] + excess_base[15:0] + 16'd1;
                    end
                    else begin
                        // 其余bins只分配base个像素
                        hist_clipped[bin_cnt[7:0]] <= hist_clipped[bin_cnt[7:0]] + excess_base[15:0];
                    end

                    if (bin_cnt < 9'd255) begin
                        bin_cnt <= bin_cnt + 9'd1;
                    end
                    else begin
                        bin_cnt <= 9'd0;
                    end
                end

                // ============================================================
                // CALC_CDF: 计算累积分布函数
                // ============================================================
                CALC_CDF: begin
                    // 保持RAM信号稳定，避免X态cdf_done

                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= tile_cnt;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    if (bin_cnt == 0) begin
                        // 初始化：第一个周期只设置初始值
                        cdf[0] <= hist_clipped[0];
                        cdf_temp <= hist_clipped[0];
                        // 修复：检查bin0是否是第一个非零CDF
                        if (hist_clipped[0] > 0) begin
                            cdf_min <= hist_clipped[0];  // bin0就是第一个非零值
                            cdf_max <= hist_clipped[0];
                        end
                        else begin
                            cdf_min <= 32'd0;  // 还没找到，继续寻找
                            cdf_max <= 32'd0;
                        end

                        bin_cnt <= 9'd1;
                    end
                    else begin
                        // 计算后续bins的CDF
                        cdf_temp <= cdf_temp + hist_clipped[bin_cnt[7:0]];
                        cdf[bin_cnt[7:0]] <= cdf_temp + hist_clipped[bin_cnt[7:0]];

                        // 修复：查找第一个非零CDF值（不是最小值！）
                        // cdf_min应该是按顺序扫描bin时第一次遇到的非零CDF
                        if ((cdf_temp + hist_clipped[bin_cnt[7:0]]) > 0 && cdf_min == 32'd0) begin
                            cdf_min <= cdf_temp + hist_clipped[bin_cnt[7:0]];
                        end
                        // cdf_max是最大的CDF值（最后一个bin的CDF）
                        if ((cdf_temp + hist_clipped[bin_cnt[7:0]]) > cdf_max) begin
                            cdf_max <= cdf_temp + hist_clipped[bin_cnt[7:0]];
                        end

                        if (bin_cnt == 9'd255) begin
                            // 不在这里计算cdf_range，延迟到下一个状态
                            bin_cnt <= 9'd0;
                        end
                        else begin
                            bin_cnt <= bin_cnt + 9'd1;
                        end
                    end
                end

                // ============================================================
                // WRITE_LUT: 归一化并写入CDF查找表（标准CLAHE）
                // ============================================================
                WRITE_LUT: begin
                    // 保持RAM读信号稳定，避免X态
                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;

                    if (bin_cnt == 0) begin
                        // 修复：第一个周期计算cdf_range，确保使用正确的cdf_max和cdf_min
                        cdf_range <= cdf_max - cdf_min;
                        cdf_wr_tile_idx <= tile_cnt;
                        cdf_wr_bin_addr <= 8'd0;
                        cdf_wr_en <= 1'b0;  // 第一个周期不写入
                        bin_cnt <= 9'd1;    // 下一个周期从bin 0开始写入
                    end
                    else begin
                        // 从第二个周期开始写入（bin_cnt=1对应写入bin 0）
                        cdf_wr_tile_idx <= tile_cnt;
                        cdf_wr_bin_addr <= bin_cnt[7:0] - 1;  // bin_cnt-1才是实际写入的bin
                        cdf_wr_en <= 1'b1;

                        // 标准CLAHE归一化公式: (cdf[i] - cdf_min) * 255 / (cdf_max - cdf_min)
                        if (cdf_range > 0) begin
                            cdf_wr_data <= ((cdf[bin_cnt[7:0] - 1] - cdf_min) * 255) / cdf_range;
                        end
                        else begin
                            // 边界情况：所有像素值相同
                            cdf_wr_data <= 8'd128;  // 映射到中等灰度
                        end

                        if (bin_cnt < 9'd256) begin  // 需要257个周期：1个计算+256个写入
                            bin_cnt <= bin_cnt + 9'd1;
                        end
                        else begin
                            // 所有bin写入完成后，准备下一个tile
                            bin_cnt <= 9'd0;
                        end
                    end
                end

                // ============================================================
                // NEXT_TILE: 移动到下一个tile
                // ============================================================
                NEXT_TILE: begin
                    cdf_wr_en <= 1'b0;
                    cdf_wr_bin_addr <= 8'd0;
                    bin_cnt <= 9'd0;  // 重置bin计数器，为下一个tile准备
                    if (tile_cnt < TILE_NUM - 1) begin
                        tile_cnt <= tile_cnt + 6'd1;
                        // 预先设置下一个tile的RAM信号
                        hist_rd_tile_idx <= tile_cnt + 6'd1;
                        hist_rd_bin_addr <= 8'd0;
                        cdf_wr_tile_idx <= tile_cnt + 6'd1;
                    end
                    else begin
                        // 保持信号稳定
                        hist_rd_tile_idx <= tile_cnt;
                        hist_rd_bin_addr <= 8'd0;
                        cdf_wr_tile_idx <= tile_cnt;
                    end
                end

                // ============================================================
                // DONE: 所有tile处理完成
                // ============================================================
                DONE: begin
                    processing <= 1'b0;
                    cdf_done <= 1'b1;  // 单周期脉冲
                    cdf_wr_en <= 1'b0;
                    // 保持所有RAM信号稳定
                    hist_rd_tile_idx <= 6'd0;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= 6'd0;
                    cdf_wr_bin_addr <= 8'd0;
                end

                // ============================================================
                // DONE_PULSE: 完成脉冲状态，重置cdf_done信号
                // ============================================================
                DONE_PULSE: begin
                    cdf_done <= 1'b0;  // 重置cdf_done信号
                    cdf_wr_en <= 1'b0;
                    // 保持所有RAM信号稳定
                    hist_rd_tile_idx <= 6'd0;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= 6'd0;
                    cdf_wr_bin_addr <= 8'd0;
                end

            endcase
        end
    end

endmodule



