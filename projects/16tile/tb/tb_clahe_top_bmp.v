// ============================================================================
// Testbench for CLAHE - 使用实际BMP图像进行连续多帧输入测试
//
// 功能特性:
//   1. 使用bmp_to_videoStream模块从BMP文件读取图像
//   2. 支持连续多帧输入（可重复播放同一图像或多个图像）
//   3. 自动将BMP数据转换为YUV格式（灰度图）
//   4. 输出结果保存为BMP文件
//
// 使用方法:
//   1. 将BMP图像放在 sim/bmp_in/ 目录下
//   2. 在仿真命令中指定输入文件名：+BMP_INPUT=1.bmp
//   3. 可选：指定帧数 +NUM_FRAMES=5
//
// 作者: Passionate.Z
// 日期: 2025-10-30
// ============================================================================

`timescale 1ns/1ps

module tb_clahe_top_bmp #(
        // ========================================================================
        // 全局参数接口
        // ========================================================================
        parameter ENABLE_CLAHE  = 1,     // CLAHE功能全局使能：1=启用，0=禁用
        parameter ENABLE_INTERP = 1,     // 插值功能全局使能：1=启用，0=禁用
        parameter CLIP_THRESHOLD = 6,    // Clip限制值
        parameter NUM_FRAMES = 3         // 要处理的帧数
    ) ();

    // ========================================================================
    // 参数定义
    // ========================================================================
    parameter WIDTH = 1280;
    parameter HEIGHT = 720;
    parameter CLK_PERIOD = 13.5;  // 74.25MHz

    // ========================================================================
    // 信号定义
    // ========================================================================
    reg         pclk;
    reg         rst_n;
    reg         clahe_enable;
    reg         interp_enable;
    reg  [15:0] clip_threshold;

    // CLAHE接口信号
    reg         in_href;
    reg         in_vsync;
    reg  [7:0]  in_y;
    reg  [7:0]  in_u;
    reg  [7:0]  in_v;

    wire        out_href;
    wire        out_vsync;
    wire [7:0]  out_y;
    wire [7:0]  out_u;
    wire [7:0]  out_v;

    // BMP读取模块信号
    wire                vout_vsync;
    wire                vout_hsync;
    wire [2:0][7:0]     vout_dat;
    wire                vout_valid;
    reg                 vout_begin;
    wire                vout_done;
    wire [15:0]         vout_xres;
    wire [15:0]         vout_yres;

    // 调试信号
    wire        processing = u_dut.cdf_processing;
    wire        cdf_ready = u_dut.cdf_done;

    // 统计变量
    integer frame_count;
    integer pixel_count;
    integer total_pixels;
    integer in_y_sum, out_y_sum;

    // BMP保存相关信号
    wire        bmp_out_ready;
    wire [7:0]  bmp_out_b, bmp_out_g, bmp_out_r;
    wire        bmp_out_frame_sync_n;
    wire [15:0] bmp_xres;
    wire [15:0] bmp_yres;

    // 文件路径参数
    reg [1024*8-1:0] bmp_input_file;
    reg [1024*8-1:0] bmp_input_path;

    // ========================================================================
    // DUT实例化 - CLAHE Top Module
    // ========================================================================
    clahe_top u_dut (
                  .pclk(pclk),
                  .rst_n(rst_n),
                  .in_y(in_y),
                  .in_u(in_u),
                  .in_v(in_v),
                  .in_href(in_href),
                  .in_vsync(in_vsync),
                  .out_y(out_y),
                  .out_u(out_u),
                  .out_v(out_v),
                  .out_href(out_href),
                  .out_vsync(out_vsync),
                  .clip_threshold(clip_threshold),
                  .enable_clahe(clahe_enable),
                  .enable_interp(interp_enable)
              );

    // ========================================================================
    // BMP读取模块 - 从文件读取图像数据
    // ========================================================================
    bmp_to_videoStream #(
                           .H_SYNC(40),
                           .H_BACK(220),
                           .H_DISP(WIDTH),
                           .H_FRONT(110),
                           .H_TOTAL(1650),
                           .V_SYNC(5),
                           .V_BACK(20),
                           .V_DISP(HEIGHT),
                           .V_FRONT(5),
                           .V_TOTAL(750),
                           .iBMP_FILE_PATH("sim/bmp_in/"),
                           .iBMP_FILE_NAME("1.bmp")
                       ) u_bmp_reader (
                           .clk(pclk),
                           .rst_n(rst_n),
                           .vout_vsync(vout_vsync),
                           .vout_hsync(vout_hsync),
                           .vout_dat(vout_dat),
                           .vout_valid(vout_valid),
                           .vout_begin(vout_begin),
                           .vout_done(vout_done),
                           .vout_xres(vout_xres),
                           .vout_yres(vout_yres)
                       );

    // ========================================================================
    // BMP保存模块 - 输出图像
    // ========================================================================
    bmp_for_videoStream_24bit #(
                                  .iREADY(10),
                                  .iBMP_FILE_PATH("sim_outputs/"),
                                  .iBMP_FILE_NAME("bmp_output")
                              ) u_bmp_output (
                                  .clk(pclk),
                                  .rst_n(rst_n),
                                  .frame_sync_n(bmp_out_frame_sync_n),
                                  .vin_ready(bmp_out_ready),
                                  .vin_dat({bmp_out_r, bmp_out_g, bmp_out_b}),
                                  .vin_valid(out_href),
                                  .vin_xres(bmp_xres),
                                  .vin_yres(bmp_yres)
                              );

    // ========================================================================
    // RGB到YUV转换（从BMP读取的数据）
    // 简化版：将RGB转换为灰度（Y通道），U/V固定为128
    // ========================================================================
    always @(*) begin
        // 使用标准灰度转换公式: Y = 0.299*R + 0.587*G + 0.114*B
        // 近似为: Y = (77*R + 150*G + 29*B) >> 8
        in_y = (77 * vout_dat[2] + 150 * vout_dat[1] + 29 * vout_dat[0]) >> 8;
        in_u = 8'd128;
        in_v = 8'd128;
        in_href = vout_valid;
        in_vsync = vout_vsync;
    end

    // ========================================================================
    // YUV到RGB转换（输出到BMP保存）
    // ========================================================================
    assign bmp_out_r = out_y;
    assign bmp_out_g = out_y;
    assign bmp_out_b = out_y;

    // ========================================================================
    // BMP控制信号生成
    // ========================================================================
    reg out_vsync_d1, out_vsync_d2;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            out_vsync_d1 <= 0;
            out_vsync_d2 <= 0;
        end
        else begin
            out_vsync_d1 <= out_vsync;
            out_vsync_d2 <= out_vsync_d1;
        end
    end
    assign bmp_out_frame_sync_n = !(out_vsync_d1 && !out_vsync_d2);

    assign bmp_xres = WIDTH;
    assign bmp_yres = HEIGHT;

    // ========================================================================
    // 时钟生成
    // ========================================================================
    initial begin
        pclk = 0;
        forever
            #(CLK_PERIOD/2) pclk = ~pclk;
    end

    // ========================================================================
    // 测试激励 - 连续多帧处理
    // ========================================================================
    initial begin
        // 创建输出文件夹
        $system("if not exist sim_outputs mkdir sim_outputs");

        // 初始化
        rst_n = 0;
        clahe_enable = ENABLE_CLAHE;
        interp_enable = ENABLE_INTERP;
        clip_threshold = CLIP_THRESHOLD;
        vout_begin = 0;
        frame_count = 0;
        total_pixels = 0;
        in_y_sum = 0;
        out_y_sum = 0;

        // 打印配置信息
        $display("\n========================================");
        $display("  CLAHE BMP Image Test");
        $display("========================================");
        $display("  Input: sim/bmp_in/1.bmp");
        $display("  Output: sim_outputs/bmp_output_N.bmp");
        $display("  Resolution: %0dx%0d", WIDTH, HEIGHT);
        $display("  Frames to process: %0d", NUM_FRAMES);
        $display("  Config:");
        $display("    CLAHE Enable:  %0d", ENABLE_CLAHE);
        $display("    Interp Enable: %0d", ENABLE_INTERP);
        $display("    Clip Threshold: %0d", CLIP_THRESHOLD);
        $display("========================================\n");

        // 复位
        #(CLK_PERIOD*20);
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        #(CLK_PERIOD*100);

        // ====================================================================
        // 连续多帧处理
        // ====================================================================
        repeat(NUM_FRAMES) begin
            $display("\n[%0t] ========== Processing Frame %0d ==========", $time, frame_count);

            // 启动BMP读取
            vout_begin = 1;
            @(posedge pclk);
            vout_begin = 0;

            // 等待帧处理完成
            wait(vout_done);
            $display("[%0t] Frame %0d: BMP reading completed", $time, frame_count);

            // 等待CLAHE处理完成
            #(CLK_PERIOD*100);
            if (processing) begin
                $display("[%0t] Frame %0d: Waiting for CDF processing...", $time, frame_count);
                wait(processing == 0);
                $display("[%0t] Frame %0d: CDF processing completed", $time, frame_count);
            end

            frame_count = frame_count + 1;

            // 帧间延迟
            #(CLK_PERIOD*10000);
        end

        // ====================================================================
        // 测试完成
        // ====================================================================
        $display("\n========================================");
        $display("  Test Complete!");
        $display("========================================");
        $display("  Total frames processed: %0d", frame_count);
        $display("  Output files:");
        repeat(NUM_FRAMES) begin
            $display("    - sim_outputs/bmp_output_%0d.bmp", frame_count - NUM_FRAMES + 1);
        end
        $display("========================================\n");

        #(CLK_PERIOD*10000);
        $stop;
    end

    // ========================================================================
    // 监控和统计
    // ========================================================================
    reg [31:0] black_pixels;
    reg [31:0] frame_pixels;

    initial begin
        black_pixels = 0;
        frame_pixels = 0;
    end

    // 像素统计
    always @(posedge pclk) begin
        if (out_href) begin
            frame_pixels = frame_pixels + 1;
            in_y_sum = in_y_sum + in_y;
            out_y_sum = out_y_sum + out_y;

            if (out_y == 0) begin
                black_pixels = black_pixels + 1;
            end
        end

        // 帧结束统计
        if (out_vsync && !out_vsync_d1) begin
            if (frame_pixels > 0) begin
                $display("[STATS] Frame %0d:", frame_count);
                $display("  Total pixels: %0d", frame_pixels);
                $display("  Black pixels: %0d (%.1f%%)", black_pixels, (black_pixels*100.0)/frame_pixels);
                $display("  Avg input Y: %0d", in_y_sum/frame_pixels);
                $display("  Avg output Y: %0d", out_y_sum/frame_pixels);
                $display("  CDF ready: %0d", cdf_ready);
            end
            black_pixels = 0;
            frame_pixels = 0;
            in_y_sum = 0;
            out_y_sum = 0;
        end
    end

    // 监控关键事件
    always @(posedge processing) begin
        $display("[%0t] >>> CDF Processing started", $time);
    end

    always @(negedge processing) begin
        $display("[%0t] <<< CDF Processing finished", $time);
    end

    always @(posedge cdf_ready) begin
        $display("[%0t] *** CDF Ready - CLAHE active", $time);
    end

    // 帧开始/结束监控
    reg vout_vsync_d1;
    always @(posedge pclk) begin
        vout_vsync_d1 <= vout_vsync;

        // 检测vsync上升沿（帧开始）
        if (vout_vsync && !vout_vsync_d1) begin
            $display("[%0t] === Frame %0d Start ===", $time, frame_count);
        end

        // 检测vsync下降沿（帧结束）
        if (!vout_vsync && vout_vsync_d1) begin
            $display("[%0t] === Frame %0d End ===", $time, frame_count - 1);
        end
    end

    // ========================================================================
    // 波形转储
    // ========================================================================
    initial begin
        $dumpfile("tb_clahe_top_bmp.vcd");
        $dumpvars(0, tb_clahe_top_bmp);

        // 选择性转储关键信号
        $dumpvars(1, u_dut.ping_pong_flag);
        $dumpvars(1, u_dut.frame_hist_done);
        $dumpvars(1, u_dut.cdf_done);
    end

    // ========================================================================
    // 调试监控（可选）
    // ========================================================================
    // 监控前几个像素的详细信息
    integer pixel_debug_cnt;
    initial
        pixel_debug_cnt = 0;

    always @(posedge pclk) begin
        if (!rst_n || (vout_vsync && !vout_vsync_d1)) begin
            pixel_debug_cnt = 0;
        end
        else if (vout_valid && pixel_debug_cnt < 10) begin
            $display("[PIXEL %0d] BMP_RGB=(%0d,%0d,%0d) -> Y=%0d, out_y=%0d",
                     pixel_debug_cnt,
                     vout_dat[2], vout_dat[1], vout_dat[0],
                     in_y, out_y);
            pixel_debug_cnt = pixel_debug_cnt + 1;
        end
    end

endmodule

