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
//   - 每tile处理时间：约1257+(DIV_LATENCY+1)个时钟周期
//     * READ_HIST:   257周期
//     * CLIP_SCAN:   257周期
//     * CLIP_REDIST: 257周期
//     * CALC_CDF:    257周期
//     * WRITE_LUT:   257+(DIV_LATENCY+1)+2级流水线，(DIV_LATENCY+1)个排空周期
//     * 其他状态:    约6周期
//   - 例如DIV_LATENCY=16：16 × 1275 ≈ 20,400周期
//   - 在96MHz时钟下：约0.213ms完成所有处理（时序优化后）
//   - 帧间隙时间充足：33ms@30fps，处理时间占比<0.7%
//
// 关键算法（标准CLAHE实现）:
//   - Clip阈值：clip_limit = (tile_pixels / 256) × clip_factor
//   - 溢出重分配：avg = excess/256, remainder = excess%256
//                 前remainder个bins加(avg+1)，其余bins加avg
//   - CDF归一化：cdf_norm = (cdf[i] - cdf_min) × 255 / (cdf_max - cdf_min)
//                使用3级流水线精确除法，时序友好且完全符合标准CLAHE算法
//
// 流水线优化（归一化阶段）:
//   - 阶段1（1周期）：从CDF RAM读取 + 减法（cdf - cdf_min）
//   - 阶段2（1周期）：乘法（diff × 255）
//   - 阶段3（N周期）：除法IP核（mult / cdf_range），32位无符号除法，N=DIV_LATENCY
//   - 阶段4（1周期）：除法器输出寄存（打断组合路径，解决时序问题）
//   - 阶段5（1周期）：饱和处理 + 写入外部RAM
//   - 流水线排空：(DIV_LATENCY+1)个周期完成剩余bins的写入
//   - 关键路径优化：增加IP核Latency参数（建议16-32）+输出寄存器打断组合路径
//   - 时序裕度：可稳定运行在96MHz+（10.4ns周期），Slack > +5ns（需调整Latency）
//
// 日期: 2025-10-15
// ============================================================================

module clahe_clipper_cdf #(
        parameter TILE_NUM = 16,
        parameter BINS = 256,
        parameter TILE_PIXELS = 57600  // 320*180
    )(
        input  wire         pclk,
        input  wire         rst_n,

        // 控制信号
        input  wire         frame_hist_done,    // 直方图统计完成，触发处理
        input  wire [15:0]  clip_limit,         // 裁剪阈值
        input  wire         ping_pong_flag,     // 读取哪个hist RAM (与统计相反)

        // 直方图RAM读接口
        output reg  [3:0]   hist_rd_tile_idx,   // 读tile索引 (0-15)
        output reg  [7:0]   hist_rd_bin_addr,   // 读bin地址 (0-255)
        input  wire [15:0]  hist_rd_data_a,     // RAM A数据
        input  wire [15:0]  hist_rd_data_b,     // RAM B数据

        // CDF LUT写入接口（写入16块RAM）
        output reg  [3:0]   cdf_wr_tile_idx,   // 写tile索引
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
    reg  [3:0]  tile_cnt;              // 当前处理的tile索引(0-15)
    reg  [8:0]  bin_cnt;               // 当前处理的bin索引(0-256)，需要9位以支持RAM读延迟

    // frame_hist_done现在是单周期脉冲，无需边沿检测

    // ========================================================================
    // RAM优化：使用RAM替代大型寄存器数组
    // ========================================================================
    // hist_buf RAM: 存储直方图数据（256×16bit）
    wire [15:0] hist_buf_douta;
    wire [15:0] hist_buf_doutb;

    // cdf RAM: 存储CDF数据（256×16bit）
    wire [15:0] cdf_ram_douta;

    // RAM控制信号寄存器（优化：直接用reg驱动RAM，省略wire层）
    reg         hist_buf_ena_r;
    reg         hist_buf_wea_r;
    reg  [7:0]  hist_buf_addra_r;
    reg  [15:0] hist_buf_dina_r;
    reg         hist_buf_enb_r;
    reg         hist_buf_web_r;
    reg  [7:0]  hist_buf_addrb_r;
    reg  [15:0] hist_buf_dinb_r;

    reg         cdf_ram_wea_r;
    reg  [7:0]  cdf_ram_addra_r;
    reg  [15:0] cdf_ram_dina_r;

    // Clip相关信号 - 标准CLAHE实现
    reg  [16:0] excess_total;          // 总溢出量 (最大57600+裕度)
    wire [8:0]  excess_per_bin;        // 每个bin分配的溢出量（整数部分）
    wire [7:0]  excess_remainder;      // 余数部分（需要分配给前N个bins）

    // CDF相关信号 - 标准CLAHE实现（带流水线优化）
    // 57600像素累加，用16位安全（最大65535 > 57600）
    reg  [15:0] cdf_min;               // CDF最小值
    reg         cdf_min_found;         // cdf_min是否已找到（用于查找第一个非零CDF）
    reg  [15:0] cdf_max;               // CDF最大值
    reg  [15:0] cdf_range;             // CDF范围
    reg  [15:0] cdf_temp;              // 临时累加值

    // 归一化流水线寄存器（改为8+2级流水：读取→乘法→除法IP[8周期]→写入）
    reg  [15:0] norm_stage1_diff;      // 阶段1：cdf - cdf_min
    reg  [31:0] norm_stage2_mult;      // 阶段2：diff * 255
    reg  [7:0]  norm_stage1_addr;      // 阶段1的地址（用于延迟对齐）
    reg  [7:0]  norm_stage2_addr;      // 阶段2的地址（用于延迟对齐）

    // 除法器IP核控制信号
    reg         div_clken;             // 除法器时钟使能
    reg  [31:0] div_numer;             // 除法器被除数（norm_stage2_mult，32位）
    reg  [15:0] div_denom;             // 除法器除数（cdf_range，16位）
    wire [31:0] div_quotient_wire;     // 除法器商（IP核输出，32位组合逻辑）
    wire [15:0] div_remain;            // 除法器余数（16位，不使用）
    reg  [31:0] div_quotient;          // 除法器商（打一拍寄存，打断组合路径）
    reg  [31:0] div_quotient_d1;       // 除法器商再延迟1拍（与地址最终对齐）

    // 除法器流水线地址延迟（N+1级：N级IP+1级输出寄存）
    // 注意：修改IP核Latency后，需要同步修改这里的数组大小
    parameter DIV_LATENCY = 24;  // IP核延迟周期数（根据IP配置调整：8/16/24/32）
    reg  [7:0]  div_addr_pipe[DIV_LATENCY:0];  // 地址延迟管道
    reg  [7:0]  div_addr_d1;      // 地址第一级延迟
    reg  [7:0]  div_addr_d2;      // 地址第二级延迟（与div_quotient对齐）
    reg  [7:0]  div_addr_final;   // 地址第三级延迟（与div_quotient_d1对齐）

    // 乒乓RAM数据选择
    // CDF读取当前帧统计的RAM（与统计写入同一组）
    // ping_pong_flag=0：统计写RAM_A，CDF读RAM_A
    // ping_pong_flag=1：统计写RAM_B，CDF读RAM_B
    wire [15:0] hist_rd_data;           // 根据ping_pong_flag选择读取的RAM数据
    assign hist_rd_data = ping_pong_flag ? hist_rd_data_b : hist_rd_data_a;

    // 标准CLAHE：将溢出量平均分配到所有256个bins
    assign excess_per_bin = excess_total[16:8];      // 整数部分：除以256（等效于右移8位）
    assign excess_remainder = excess_total[7:0];     // 余数部分：模256（等效于取低8位）

    // 归一化除法结果（使用除法器IP核输出，带饱和处理）
    wire [7:0]  norm_saturated;
    assign norm_saturated = (div_quotient_d1 > 32'd255) ? 8'd255 : div_quotient_d1[7:0];

    // ========================================================================
    // RAM实例化：hist_buf和cdf使用真双端口RAM
    // ========================================================================
    // hist_buf RAM实例：用于存储直方图数据
    clahe_true_dual_port_ram #(
                                 .DATA_WIDTH(16),
                                 .ADDR_WIDTH(8),
                                 .DEPTH(256)
                             ) hist_buf_ram_inst (
                                 .clk(pclk),
                                 // 端口A（优化：直接连接reg）
                                 .ena(hist_buf_ena_r),
                                 .wea(hist_buf_wea_r),
                                 .addra(hist_buf_addra_r),
                                 .dina(hist_buf_dina_r),
                                 .douta(hist_buf_douta),
                                 // 端口B
                                 .enb(hist_buf_enb_r),
                                 .web(hist_buf_web_r),
                                 .addrb(hist_buf_addrb_r),
                                 .dinb(hist_buf_dinb_r),
                                 .doutb(hist_buf_doutb)
                             );

    // cdf RAM实例：用于存储CDF数据（优化：使用简单双端口RAM IP核，节省BRAM资源）
    clahe_simple_dual_ram cdf_ram_inst (
                              .clk(pclk),
                              // 写端口（优化：直接连接reg）
                              .we(cdf_ram_wea_r),
                              .waddr(cdf_ram_addra_r),
                              .wdata_a(cdf_ram_dina_r),
                              // 读端口
                              .raddr(cdf_ram_addra_r),  // 读写共用同一地址
                              .rdata_b(cdf_ram_douta)
                          );

    // ========================================================================
    // 除法器IP核实例化：用于CDF归一化计算
    // ========================================================================
    // 配置：32位÷16位无符号除法，24周期延迟，流水线模式
    // 功能：计算 (cdf - cdf_min) * 255 / (cdf_max - cdf_min)
    // 优化：除数仅16位（cdf_range最大57600），节省50%除法器资源
    //       24级深流水线，每级仅需处理1.33位，时序裕度充足
    // 注意：IP核输出quotient是组合逻辑，需要额外打一拍寄存以打断时序路径
    clahe_cdf_divider u_clahe_cdf_divider (
                          .numer    (div_numer),         // [31:0] 被除数（32位）
                          .denom    (div_denom),         // [15:0] 除数（16位）
                          .clken    (div_clken),         // 时钟使能
                          .clk      (pclk),              // 时钟
                          .reset    (~rst_n),            // 复位（高有效）
                          .quotient (div_quotient_wire), // [31:0] 商（24周期后，组合逻辑输出）
                          .remain   (div_remain)         // [15:0] 余数（不使用）
                      );

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
                // 需要257个周期完成(0-256)，在bin_cnt==256时所有数据处理完毕
                if (bin_cnt == 256) begin
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
                // 需要257个周期完成(0-256)，在bin_cnt==256时所有数据处理完毕
                if (bin_cnt == 256) begin
                    next_state = CALC_CDF;  // 重分配完成，开始计算CDF
                end
            end

            CALC_CDF: begin
                // CDF计算状态：计算累积分布函数
                // 需要257个周期完成(0-256)，在bin_cnt==256时所有数据处理完毕
                if (bin_cnt == 256) begin
                    next_state = WRITE_LUT;  // CDF计算完成，开始写入查找表
                end
            end

            WRITE_LUT: begin
                // 写入查找表状态：将CDF结果写入RAM
                // 流水线优化：需要等待流水线完全排空（1个初始化 + 256个读取 + (DIV_LATENCY+4)个流水线排空）
                // 总周期数：1 + 256 + 28 = 285，所以bin_cnt从0到285，当bin_cnt==286时退出
                if (bin_cnt == (9'd258 + DIV_LATENCY + 9'd4 + 9'd1)) begin
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
            tile_cnt <= 4'd0;
            bin_cnt <= 9'd0;
            excess_total <= 17'd0;
            cdf_min <= 16'd0;
            cdf_min_found <= 1'b0;
            cdf_max <= 16'd0;
            cdf_range <= 16'd0;
            cdf_temp <= 16'd0;

            // 归一化流水线寄存器
            norm_stage1_diff <= 16'd0;
            norm_stage2_mult <= 32'd0;
            norm_stage1_addr <= 8'd0;
            norm_stage2_addr <= 8'd0;

            // 除法器控制信号初始化
            div_clken <= 1'b0;
            div_numer <= 32'd0;
            div_denom <= 16'd0;  // 16位除数
            div_quotient <= 32'd0;
            for (i = 0; i <= DIV_LATENCY; i = i + 1) begin
                div_addr_pipe[i] <= 8'd0;
            end

            hist_rd_tile_idx <= 4'd0;
            hist_rd_bin_addr <= 8'd0;
            cdf_wr_tile_idx <= 4'd0;
            cdf_wr_bin_addr <= 8'd0;
            cdf_wr_data <= 8'd0;
            cdf_wr_en <= 1'b0;
            processing <= 1'b0;
            cdf_done <= 1'b0;

            // RAM控制信号初始化
            hist_buf_ena_r <= 1'b0;
            hist_buf_wea_r <= 1'b0;
            hist_buf_addra_r <= 8'd0;
            hist_buf_dina_r <= 16'd0;
            hist_buf_enb_r <= 1'b0;
            hist_buf_web_r <= 1'b0;
            hist_buf_addrb_r <= 8'd0;
            hist_buf_dinb_r <= 16'd0;

            cdf_ram_wea_r <= 1'b0;
            cdf_ram_addra_r <= 8'd0;
            cdf_ram_dina_r <= 16'd0;
        end
        else begin
            case (state)
                // ============================================================
                // IDLE: 等待触发
                // ============================================================
                IDLE: begin
                    // 保持所有RAM信号稳定，避免X态
                    hist_rd_tile_idx <= 4'd0;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= 4'd0;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    // 禁用内部RAM
                    hist_buf_ena_r <= 1'b0;
                    hist_buf_wea_r <= 1'b0;
                    hist_buf_enb_r <= 1'b0;
                    hist_buf_web_r <= 1'b0;
                    cdf_ram_wea_r <= 1'b0;

                    if (frame_hist_done) begin
                        tile_cnt <= 4'd0;
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

                    // 禁用cdf RAM
                    cdf_ram_wea_r <= 1'b0;

                    // 修复：RAM有1周期延迟，需要257个周期完成读取
                    // 周期0-255: 发出地址0-255
                    // 周期1-256: 接收数据0-255
                    if (bin_cnt < 9'd256) begin
                        hist_rd_bin_addr <= bin_cnt[7:0];  // 发送地址（0-255）
                    end

                    // 从周期1开始存储数据到hist_buf RAM（周期0没有有效数据）
                    if (bin_cnt > 0 && bin_cnt <= 9'd256) begin
                        hist_buf_ena_r <= 1'b1;
                        hist_buf_wea_r <= 1'b1;
                        hist_buf_addra_r <= bin_cnt[7:0] - 1;
                        hist_buf_dina_r <= hist_rd_data;
                    end
                    else begin
                        hist_buf_ena_r <= 1'b0;
                        hist_buf_wea_r <= 1'b0;
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
                    // 保持外部RAM信号稳定，避免X态
                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= tile_cnt;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    // 禁用cdf RAM
                    cdf_ram_wea_r <= 1'b0;

                    if (bin_cnt == 0) begin
                        excess_total <= 17'd0;
                    end

                    // 使用端口A读取hist_buf RAM
                    // 周期0-255: 发出读地址0-255
                    // 周期1-256: 接收并处理数据0-255
                    if (bin_cnt < 9'd256) begin
                        hist_buf_ena_r <= 1'b1;
                        hist_buf_addra_r <= bin_cnt[7:0];
                        hist_buf_wea_r <= 1'b0;  // 只读
                    end
                    else begin
                        hist_buf_ena_r <= 1'b0;
                        hist_buf_wea_r <= 1'b0;
                    end

                    // 从周期1开始处理读取的数据，周期256处理最后一个数据
                    if (bin_cnt > 0 && bin_cnt <= 9'd256) begin
                        // 检查是否需要clip
                        if (hist_buf_douta > clip_limit) begin
                            // 超过阈值，计算溢出量并使用端口B写回clipped值
                            excess_total <= excess_total + ({1'd0, hist_buf_douta} - {1'd0, clip_limit});
                            hist_buf_enb_r <= 1'b1;
                            hist_buf_web_r <= 1'b1;
                            hist_buf_addrb_r <= bin_cnt[7:0] - 1;
                            hist_buf_dinb_r <= clip_limit;
                        end
                        else begin
                            hist_buf_enb_r <= 1'b0;
                            hist_buf_web_r <= 1'b0;
                        end
                    end
                    else begin
                        hist_buf_enb_r <= 1'b0;
                        hist_buf_web_r <= 1'b0;
                    end

                    if (bin_cnt < 9'd256) begin
                        bin_cnt <= bin_cnt + 9'd1;
                    end
                    else begin
                        bin_cnt <= 9'd0;
                    end
                end

                // ============================================================
                // CLIP_REDIST: 重分配溢出量到所有bins（标准CLAHE）
                // 标准算法：每个bin加上平均值，前remainder个bin额外加1
                // ============================================================
                CLIP_REDIST: begin
                    // 保持外部RAM信号稳定，避免X态
                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= tile_cnt;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    // 禁用cdf RAM
                    cdf_ram_wea_r <= 1'b0;

                    // 标准CLAHE：所有bins都接收溢出值
                    // 使用端口A读取，端口B写回
                    // 周期0-255: 发出读地址0-255
                    // 周期1-256: 接收并处理数据0-255，写回到端口B
                    if (bin_cnt < 9'd256) begin
                        hist_buf_ena_r <= 1'b1;
                        hist_buf_wea_r <= 1'b0;
                        hist_buf_addra_r <= bin_cnt[7:0];
                    end
                    else begin
                        hist_buf_ena_r <= 1'b0;
                        hist_buf_wea_r <= 1'b0;
                    end

                    // 从周期1开始处理读取的数据并写回，周期256处理最后一个数据
                    if (bin_cnt > 0 && bin_cnt <= 9'd256) begin
                        hist_buf_enb_r <= 1'b1;
                        hist_buf_web_r <= 1'b1;
                        hist_buf_addrb_r <= bin_cnt[7:0] - 1;

                        // 标准CLAHE余数分配：前remainder个bins额外加1
                        if ((bin_cnt[7:0] - 1) < excess_remainder) begin
                            // 前remainder个bins：加上 avg_increment + 1
                            hist_buf_dinb_r <= hist_buf_douta + {7'd0, excess_per_bin} + 16'd1;
                        end
                        else begin
                            // 剩余bins：只加上 avg_increment
                            hist_buf_dinb_r <= hist_buf_douta + {7'd0, excess_per_bin};
                        end
                    end
                    else begin
                        hist_buf_enb_r <= 1'b0;
                        hist_buf_web_r <= 1'b0;
                    end

                    if (bin_cnt < 9'd256) begin
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
                    // 保持外部RAM信号稳定，避免X态
                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= tile_cnt;
                    cdf_wr_bin_addr <= 8'd0;
                    cdf_wr_en <= 1'b0;

                    // 禁用hist_buf RAM（不再需要）
                    hist_buf_enb_r <= 1'b0;
                    hist_buf_web_r <= 1'b0;

                    // 周期0: 发出读地址0
                    // 周期1-255: 接收bin 0-254数据，写入cdf[0-254]，发出读地址1-255
                    // 周期256: 接收bin 255数据，写入cdf[255]
                    if (bin_cnt == 0) begin
                        // 初始化：第一个周期发出读地址0
                        hist_buf_ena_r <= 1'b1;
                        hist_buf_wea_r <= 1'b0;
                        hist_buf_addra_r <= 8'd0;

                        cdf_temp <= 16'd0;
                        cdf_min <= 16'd0;
                        cdf_min_found <= 1'b0;  // 重置cdf_min查找标志
                        cdf_max <= 16'd0;

                        // 禁用cdf RAM写入
                        cdf_ram_wea_r <= 1'b0;

                        bin_cnt <= 9'd1;
                    end
                    else if (bin_cnt <= 9'd255) begin
                        // 周期1-255: 发出下一个读地址，同时处理上一周期的数据
                        hist_buf_ena_r <= 1'b1;
                        hist_buf_wea_r <= 1'b0;
                        hist_buf_addra_r <= bin_cnt[7:0];

                        // 处理上一周期读取的数据
                        cdf_temp <= cdf_temp + hist_buf_douta;

                        // 写入CDF到RAM
                        cdf_ram_wea_r <= 1'b1;
                        cdf_ram_addra_r <= bin_cnt[7:0] - 1;
                        cdf_ram_dina_r <= cdf_temp + hist_buf_douta;

                        // 标准CLAHE：查找第一个非零CDF值作为cdf_min
                        if (!cdf_min_found && (cdf_temp + hist_buf_douta) > 16'd0) begin
                            cdf_min <= cdf_temp + hist_buf_douta;
                            cdf_min_found <= 1'b1;
                        end

                        // 更新cdf_max（始终跟踪最大值）
                        if ((cdf_temp + hist_buf_douta) > cdf_max) begin
                            cdf_max <= cdf_temp + hist_buf_douta;
                        end

                        bin_cnt <= bin_cnt + 9'd1;
                    end
                    else begin
                        // 周期256: 处理bin 255的数据
                        hist_buf_ena_r <= 1'b0;
                        hist_buf_wea_r <= 1'b0;

                        cdf_temp <= cdf_temp + hist_buf_douta;

                        // 写入最后一个CDF值
                        cdf_ram_wea_r <= 1'b1;
                        cdf_ram_addra_r <= 8'd255;
                        cdf_ram_dina_r <= cdf_temp + hist_buf_douta;

                        // 标准CLAHE：查找第一个非零CDF值作为cdf_min
                        if (!cdf_min_found && (cdf_temp + hist_buf_douta) > 16'd0) begin
                            cdf_min <= cdf_temp + hist_buf_douta;
                            cdf_min_found <= 1'b1;
                        end

                        // 更新cdf_max（最后一个值）
                        if ((cdf_temp + hist_buf_douta) > cdf_max) begin
                            cdf_max <= cdf_temp + hist_buf_douta;
                        end

                        bin_cnt <= 9'd0;
                    end
                end

                // ============================================================
                // WRITE_LUT: 归一化并写入CDF查找表（8+1+2级流水线优化）
                // 标准公式：normalized_cdf = (cdf - cdf_min) * 255 / (cdf_max - cdf_min)
                // 流水线：读RAM → 减法 → 乘法 → 除法IP[8周期] → 输出寄存[1周期] → 写入
                // 关键：输出寄存器打断除法IP的组合逻辑输出，解决时序违例
                // ============================================================
                WRITE_LUT: begin
                    // 保持外部hist RAM读信号稳定，避免X态
                    hist_rd_tile_idx <= tile_cnt;
                    hist_rd_bin_addr <= 8'd0;

                    // 禁用hist_buf RAM
                    hist_buf_ena_r <= 1'b0;
                    hist_buf_wea_r <= 1'b0;
                    hist_buf_enb_r <= 1'b0;
                    hist_buf_web_r <= 1'b0;

                    // 周期0: 初始化，计算cdf_range，发出读地址0
                    if (bin_cnt == 0) begin
                        cdf_range <= cdf_max - cdf_min;

                        // 发出第一个CDF读地址
                        cdf_ram_wea_r <= 1'b0;
                        cdf_ram_addra_r <= 8'd0;

                        // 初始化流水线
                        norm_stage1_diff <= 16'd0;
                        norm_stage2_mult <= 32'd0;
                        norm_stage1_addr <= 8'd0;
                        norm_stage2_addr <= 8'd0;

                        // 初始化除法器控制
                        div_clken <= 1'b0;
                        div_numer <= 32'd0;
                        div_denom <= cdf_max - cdf_min;  // 16位除数，直接赋值
                        div_quotient <= 32'd0;
                        div_quotient_d1 <= 32'd0;  // 初始化延迟寄存器
                        for (i = 0; i <= DIV_LATENCY; i = i + 1) begin
                            div_addr_pipe[i] <= 8'd0;
                        end
                        div_addr_d1 <= 8'd0;     // 初始化地址第一级延迟
                        div_addr_d2 <= 8'd0;     // 初始化地址第二级延迟
                        div_addr_final <= 8'd0;  // 初始化地址第三级延迟

                        cdf_wr_tile_idx <= tile_cnt;
                        cdf_wr_en <= 1'b0;
                        bin_cnt <= 9'd1;
                    end
                    // 周期1-258: 持续读取CDF数据，流水线处理（含排空前2周期）
                    else if (bin_cnt <= 9'd258) begin
                        // 继续发出CDF读地址（周期1-255发出地址1-255）
                        if (bin_cnt < 9'd256) begin
                            cdf_ram_wea_r <= 1'b0;
                            cdf_ram_addra_r <= bin_cnt[7:0];
                        end
                        else begin
                            // 周期256：停止读取（保持地址稳定）
                            cdf_ram_wea_r <= 1'b0;
                        end

                        // === 流水线阶段1：减法（处理上一周期读取的数据）===
                        // 只在bin_cnt=1-256时处理（对应地址0-255）
                        if (bin_cnt >= 9'd1 && bin_cnt <= 9'd256) begin
                            // 防止负数：如果cdf[i] < cdf_min，则diff = 0
                            if (cdf_ram_douta >= cdf_min) begin
                                norm_stage1_diff <= cdf_ram_douta - cdf_min;
                            end
                            else begin
                                norm_stage1_diff <= 16'd0;  // 饱和到0
                            end
                            norm_stage1_addr <= bin_cnt[7:0] - 1;
                        end

                        // === 流水线阶段2：乘法 ===
                        // 只在bin_cnt=2-257时处理（对应地址0-255）
                        if (bin_cnt >= 9'd2 && bin_cnt <= 9'd257) begin
                            norm_stage2_mult <= norm_stage1_diff * 32'd255;
                            norm_stage2_addr <= norm_stage1_addr;
                        end

                        // === 流水线阶段3：触发除法器（处理阶段2的数据）===
                        // 从周期3开始触发除法运算
                        if (bin_cnt >= 9'd3 && bin_cnt < 9'd259) begin
                            // 除以0保护：如果cdf_range=0（对比度为0），bypass除法器
                            if (cdf_range > 16'd0) begin
                                div_clken <= 1'b1;
                                div_numer <= norm_stage2_mult;
                                div_denom <= cdf_range;  // 16位除数，直接赋值
                            end
                            else begin
                                // cdf_range=0时，所有像素同一灰度值，输出平坦LUT（中间值128）
                                div_clken <= 1'b0;
                                div_numer <= 32'd0;
                            end
                            // === 地址管道：与除法器同步更新 ===
                            div_addr_pipe[0] <= norm_stage2_addr;
                        end
                        else begin
                            div_clken <= 1'b0;
                            div_numer <= 32'd0;
                            div_addr_pipe[0] <= 8'd0;  // 前几个周期地址保持0
                        end

                        // === 除法器输出采样（只在结果有效后采样）===
                        // 除法器延迟DIV_LATENCY周期，所以结果在bin_cnt >= 3+DIV_LATENCY时才有效
                        if (bin_cnt >= (9'd3 + DIV_LATENCY)) begin
                            if (cdf_range > 16'd0) begin
                                div_quotient <= div_quotient_wire;  // 采样有效结果
                            end
                            else begin
                                div_quotient <= 32'd128;  // 对比度为0，输出中间灰度
                            end
                        end
                        else begin
                            div_quotient <= 32'd0;  // 结果未准备好，保持0
                        end

                        // === 地址延迟管道：N+1级移位寄存器（N级IP+1级输出寄存）===
                        for (i = 1; i <= DIV_LATENCY; i = i + 1) begin
                            div_addr_pipe[i] <= div_addr_pipe[i-1];
                        end

                        // === 地址三级延迟链（追赶数据延迟）===
                        div_addr_d1 <= div_addr_pipe[DIV_LATENCY];  // 第一级
                        div_addr_d2 <= div_addr_d1;                  // 第二级（与div_quotient对齐）
                        div_addr_final <= div_addr_d2;               // 第三级（与div_quotient_d1对齐）

                        // === 数据一级延迟 ===
                        div_quotient_d1 <= div_quotient;

                        // === 流水线写入：使用除法结果（N+4周期后）===
                        // 完美对齐：地址3级延迟 = 数据1级延迟
                        if (bin_cnt >= (9'd3 + DIV_LATENCY + 9'd4)) begin
                            cdf_wr_tile_idx <= tile_cnt;
                            cdf_wr_bin_addr <= div_addr_final;  // 使用再延迟1拍的地址
                            cdf_wr_en <= 1'b1;
                            cdf_wr_data <= norm_saturated;  // 使用饱和后的除法结果
                        end
                        else begin
                            cdf_wr_en <= 1'b0;
                        end

                        bin_cnt <= bin_cnt + 9'd1;
                    end
                    // 周期259-286: 流水线排空，完成剩余数据的写入
                    // 最后一次除法触发在bin_cnt=258，写入延迟28周期，所以需要到258+28=286
                    else if (bin_cnt <= (9'd258 + DIV_LATENCY + 9'd4)) begin
                        cdf_ram_wea_r <= 1'b0;

                        // === 停止除法器（所有256次除法已在正常阶段完成）===
                        div_clken <= 1'b0;

                        // 继续除法器输出寄存（带除以0保护）
                        if (cdf_range > 16'd0) begin
                            div_quotient <= div_quotient_wire;
                        end
                        else begin
                            div_quotient <= 32'd128;  // 对比度为0时输出中间灰度值
                        end

                        // === 修复：地址延迟管道移位（防止div_addr_pipe[0]被重复读取）===
                        // 问题：在排空阶段，div_addr_pipe[0]保持最后的值（255），如果继续执行
                        //       div_addr_pipe[1] <= div_addr_pipe[0]，会导致255被重复填充到流水线
                        // 解决：从i=2开始移位，只在bin_cnt=259时手动更新div_addr_pipe[1]一次
                        for (i = 2; i <= DIV_LATENCY; i = i + 1) begin
                            div_addr_pipe[i] <= div_addr_pipe[i-1];
                        end
                        // 特殊处理：只在排空第一个周期（bin_cnt=259）更新div_addr_pipe[1]
                        // 这样地址255可以正确进入流水线，但不会被重复读取
                        if (bin_cnt == 9'd259) begin
                            div_addr_pipe[1] <= div_addr_pipe[0];
                        end

                        // 继续三级地址延迟和一级数据延迟
                        div_addr_d1 <= div_addr_pipe[DIV_LATENCY];
                        div_addr_d2 <= div_addr_d1;
                        div_addr_final <= div_addr_d2;
                        div_quotient_d1 <= div_quotient;

                        // 继续写入剩余数据（除法结果在流水线中）
                        // 写入范围：bin_cnt=259到286（对应地址228到255）
                        if (bin_cnt >= 9'd259 && bin_cnt <= (9'd258 + DIV_LATENCY + 9'd4)) begin
                            cdf_wr_tile_idx <= tile_cnt;
                            cdf_wr_bin_addr <= div_addr_final;  // 使用再延迟1拍的地址
                            cdf_wr_en <= 1'b1;
                            cdf_wr_data <= norm_saturated;
                        end
                        else begin
                            cdf_wr_en <= 1'b0;
                        end

                        bin_cnt <= bin_cnt + 9'd1;
                    end
                    else begin
                        // 完成，准备退出
                        cdf_wr_en <= 1'b0;
                        div_clken <= 1'b0;
                        bin_cnt <= 9'd0;
                    end
                end

                // ============================================================
                // NEXT_TILE: 移动到下一个tile
                // ============================================================
                NEXT_TILE: begin
                    cdf_wr_en <= 1'b0;
                    cdf_wr_bin_addr <= 8'd0;
                    bin_cnt <= 9'd0;  // 重置bin计数器，为下一个tile准备

                    // 禁用内部RAM
                    hist_buf_ena_r <= 1'b0;
                    hist_buf_wea_r <= 1'b0;
                    hist_buf_enb_r <= 1'b0;
                    hist_buf_web_r <= 1'b0;
                    cdf_ram_wea_r <= 1'b0;

                    if (tile_cnt < TILE_NUM - 1) begin
                        tile_cnt <= tile_cnt + 4'd1;
                        // 预先设置下一个tile的RAM信号
                        hist_rd_tile_idx <= tile_cnt + 4'd1;
                        hist_rd_bin_addr <= 8'd0;
                        cdf_wr_tile_idx <= tile_cnt + 4'd1;
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

                    // 禁用内部RAM
                    hist_buf_ena_r <= 1'b0;
                    hist_buf_wea_r <= 1'b0;
                    hist_buf_enb_r <= 1'b0;
                    hist_buf_web_r <= 1'b0;
                    cdf_ram_wea_r <= 1'b0;

                    // 保持所有外部RAM信号稳定
                    hist_rd_tile_idx <= 4'd0;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= 4'd0;
                    cdf_wr_bin_addr <= 8'd0;
                end

                // ============================================================
                // DONE_PULSE: 完成脉冲状态，重置cdf_done信号
                // ============================================================
                DONE_PULSE: begin
                    cdf_done <= 1'b0;  // 重置cdf_done信号
                    cdf_wr_en <= 1'b0;

                    // 禁用内部RAM
                    hist_buf_ena_r <= 1'b0;
                    hist_buf_wea_r <= 1'b0;
                    hist_buf_enb_r <= 1'b0;
                    hist_buf_web_r <= 1'b0;
                    cdf_ram_wea_r <= 1'b0;

                    // 保持所有外部RAM信号稳定
                    hist_rd_tile_idx <= 4'd0;
                    hist_rd_bin_addr <= 8'd0;
                    cdf_wr_tile_idx <= 4'd0;
                    cdf_wr_bin_addr <= 8'd0;
                end

            endcase
        end
    end

endmodule



