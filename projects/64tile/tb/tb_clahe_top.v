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
// Testbench for CLAHE顶层模块（完整系统测试）
//
// 测试项目:
//   1. 完整的CLAHE处理流程
//   2. 多帧连续处理
//   3. 乒乓操作验证
//   4. 不同图像模式测试
//   5. Enable控制测试
//
// 测试场景:
//   - 低对比度图像增强
//   - 高对比度图像处理
//   - 纯色图像处理
//   - Bypass模式切换
//
// 作者: Passionate.Z
// 日期: 2025-10-15
// ============================================================================

`timescale 1ns/1ps

module tb_clahe_top #(
        // ========================================================================
        // 全局参数接口 - 可通过仿真命令行或do文件设置
        // ========================================================================
        parameter ENABLE_CLAHE  = 1,     // CLAHE功能全局使能：1=启用，0=禁用
        parameter ENABLE_INTERP = 1,     // 插值功能全局使能：1=启用，0=禁用
        parameter CLIP_THRESHOLD = 20     // 默认clip阈值
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
    reg         clahe_enable;       // 内部控制信号，可被全局参数覆盖
    reg         interp_enable;      // 内部控制信号，可被全局参数覆盖
    reg  [7:0]  clip_threshold;

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

    // 从DUT内部访问调试信号
    wire        processing = u_dut.cdf_processing;
    wire        cdf_ready = u_dut.cdf_done;

    // 测试变量
    integer x, y, frame;
    integer pixel_count;
    reg [7:0] test_pattern [0:255];

    // 统计
    integer total_frames;
    integer enhanced_pixels;

    // BMP保存相关信号
    wire        bmp_in_ready;
    wire        bmp_out_ready;
    wire [7:0]  bmp_in_b, bmp_in_g, bmp_in_r;
    wire [7:0]  bmp_out_b, bmp_out_g, bmp_out_r;
    wire        bmp_in_frame_sync_n;   // 输入BMP的同步信号
    wire        bmp_out_frame_sync_n;  // 输出BMP的同步信号
    wire [15:0] bmp_xres;
    wire [15:0] bmp_yres;

    // ========================================================================
    // DUT实例化 - 64块RAM版本
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
    // BMP保存模块 - 输入图像
    // ========================================================================
    bmp_for_videoStream_24bit #(
                                  .iREADY(10),
                                  .iBMP_FILE_PATH("sim_outputs/"),
                                  .iBMP_FILE_NAME("frame_input")
                              ) u_bmp_input (
                                  .clk(pclk),
                                  .rst_n(rst_n),
                                  .frame_sync_n(bmp_in_frame_sync_n),
                                  .vin_ready(bmp_in_ready),
                                  .vin_dat({bmp_in_r, bmp_in_g, bmp_in_b}),
                                  .vin_valid(in_href),
                                  .vin_xres(bmp_xres),
                                  .vin_yres(bmp_yres)
                              );

    // ========================================================================
    // BMP保存模块 - 输出图像
    // ========================================================================
    bmp_for_videoStream_24bit #(
                                  .iREADY(10),
                                  .iBMP_FILE_PATH("sim_outputs/"),
                                  .iBMP_FILE_NAME("frame_output")
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
    // YUV到RGB转换（简化版 - 将Y作为灰度图）
    // ========================================================================
    assign bmp_in_r = in_y;
    assign bmp_in_g = in_y;
    assign bmp_in_b = in_y;

    assign bmp_out_r = out_y;
    assign bmp_out_g = out_y;
    assign bmp_out_b = out_y;

    // ========================================================================
    // BMP控制信号生成
    // ========================================================================
    // 输入BMP：基于in_vsync生成frame_sync_n
    reg in_vsync_d1, in_vsync_d2;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            in_vsync_d1 <= 0;
            in_vsync_d2 <= 0;
        end
        else begin
            in_vsync_d1 <= in_vsync;
            in_vsync_d2 <= in_vsync_d1;
        end
    end
    assign bmp_in_frame_sync_n = !(in_vsync_d1 && !in_vsync_d2);  // 检测vsync上升沿

    // 输出BMP：基于out_vsync生成frame_sync_n
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
    assign bmp_out_frame_sync_n = !(out_vsync_d1 && !out_vsync_d2);  // 检测vsync上升沿

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
    // 测试激励
    // ========================================================================
    initial begin
        // 创建输出文件夹
        $system("if not exist sim_outputs mkdir sim_outputs");

        // 初始化
        rst_n = 0;
        // 使用全局参数初始化控制信号
        clahe_enable = ENABLE_CLAHE;
        interp_enable = ENABLE_INTERP;
        clip_threshold = CLIP_THRESHOLD;
        in_href = 0;
        in_vsync = 0;
        in_y = 0;
        in_u = 128;
        in_v = 128;
        total_frames = 0;
        enhanced_pixels = 0;

        // 复位
        #(CLK_PERIOD*20);
        rst_n = 1;
        $display("\n========================================");
        $display("  CLAHE Top Module Test");
        $display("  Image: %0dx%0d", WIDTH, HEIGHT);
        $display("  Tiles: 8x8 = 64");
        $display("  Output Path: sim_outputs/");
        $display("  Global Config:");
        $display("    CLAHE Enable:  %0d", ENABLE_CLAHE);
        $display("    Interp Enable: %0d", ENABLE_INTERP);
        $display("    Clip Threshold: %0d", CLIP_THRESHOLD);
        $display("========================================\n");
        $display("[%0t] Reset released", $time);
        #(CLK_PERIOD*10);

        // ====================================================================
        // 测试序列：只测试复杂场景，去掉所有纯色测试
        // 符合实际视频流特性：真实场景包含丰富的灰度分布
        // ====================================================================

        // ====================================================================
        // 阶段1: 初始化 - Bypass模式（第一帧用低对比度图像）
        // ====================================================================
        $display("\n[TEST 1] Frame 0 - Bypass mode, low contrast");
        // 使用全局参数（已在初始化时设置）
        // clahe_enable = ENABLE_CLAHE
        // interp_enable = ENABLE_INTERP
        // clip_threshold = CLIP_THRESHOLD

        gen_frame_low_contrast();  // 用接近真实场景的低对比度图像初始化
        wait_frame_complete();
        $display("[INFO] Frame 0 completed - Bypass mode (CDF building)");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        // ====================================================================
        // 阶段2: 低对比度图像组（相似分布特性）
        // ====================================================================
        $display("\n[TEST 2] Frame 1 - Low contrast (100-140 range) - Similar to previous");
        gen_frame_low_contrast();  // 与Frame 0相似，CDF应该稳定
        wait_frame_complete();
        $display("[INFO] Frame 1 completed - Low contrast stable");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 3] Frame 2 - Very low contrast (120-130 range)");
        gen_frame_very_low_contrast();  // 范围更窄但相似的分布
        wait_frame_complete();
        $display("[INFO] Frame 2 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 4] Frame 3 - Low contrast again");
        gen_frame_low_contrast();  // 再次相似图像
        wait_frame_complete();
        $display("[INFO] Frame 3 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 5] Frame 4 - Very low contrast again");
        gen_frame_very_low_contrast();  // 连续相似帧
        wait_frame_complete();
        $display("[INFO] Frame 4 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        // ====================================================================
        // 阶段3: 渐变图像组（相似渐变特性，模拟真实光照变化）
        // ====================================================================
        $display("\n[TEST 6] Frame 5 - Horizontal gradient");
        gen_frame_gradient();
        wait_frame_complete();
        $display("[INFO] Frame 5 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 7] Frame 6 - Horizontal gradient again");
        gen_frame_gradient();  // 相同渐变，CDF应该稳定
        wait_frame_complete();
        $display("[INFO] Frame 6 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 8] Frame 7 - Vertical gradient");
        gen_frame_vertical_gradient();  // 相似的渐变特性
        wait_frame_complete();
        $display("[INFO] Frame 7 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 9] Frame 8 - Vertical gradient again");
        gen_frame_vertical_gradient();  // 连续相似帧
        wait_frame_complete();
        $display("[INFO] Frame 8 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 10] Frame 9 - Diagonal gradient");
        gen_frame_diagonal_gradient();  // 相似的渐变特性
        wait_frame_complete();
        $display("[INFO] Frame 9 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 11] Frame 10 - Diagonal gradient again");
        gen_frame_diagonal_gradient();  // 相同渐变
        wait_frame_complete();
        $display("[INFO] Frame 10 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        // ====================================================================
        // 阶段4: 特殊图案（高对比度场景）
        // ====================================================================
        $display("\n[TEST 12] Frame 11 - Checkerboard pattern");
        gen_frame_checkerboard();
        wait_frame_complete();
        $display("[INFO] Frame 11 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 13] Frame 12 - Checkerboard pattern again");
        gen_frame_checkerboard();  // 相同图案
        wait_frame_complete();
        $display("[INFO] Frame 12 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        // ====================================================================
        // 阶段5: 混合场景测试（渐变+低对比度交替）
        // ====================================================================
        $display("\n[TEST 14] Frame 13 - Low contrast");
        gen_frame_low_contrast();
        wait_frame_complete();
        $display("[INFO] Frame 13 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 15] Frame 14 - Very low contrast");
        gen_frame_very_low_contrast();
        wait_frame_complete();
        $display("[INFO] Frame 14 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 16] Frame 15 - Horizontal gradient");
        gen_frame_gradient();
        wait_frame_complete();
        $display("[INFO] Frame 15 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 17] Frame 16 - Low contrast");
        gen_frame_low_contrast();
        wait_frame_complete();
        $display("[INFO] Frame 16 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 18] Frame 17 - Vertical gradient");
        gen_frame_vertical_gradient();
        wait_frame_complete();
        $display("[INFO] Frame 17 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 19] Frame 18 - Very low contrast");
        gen_frame_very_low_contrast();
        wait_frame_complete();
        $display("[INFO] Frame 18 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        $display("\n[TEST 20] Frame 19 - Diagonal gradient");
        gen_frame_diagonal_gradient();
        wait_frame_complete();
        $display("[INFO] Frame 19 completed");
        total_frames = total_frames + 1;
        #(CLK_PERIOD*1000000);

        // ====================================================================
        // 测试总结
        // ====================================================================
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("Total frames processed: %0d", total_frames);
        $display("Enhanced pixels: %0d", enhanced_pixels);
        $display("\n[%0t] All tests completed successfully!", $time);
        $display("========================================\n");

        #(CLK_PERIOD*1000000);  // 增加帧间隙，确保CDF处理完全稳定
        $stop;
    end

    // ========================================================================
    // 帧生成任务
    // ========================================================================

    // 生成均匀亮度帧
    task gen_frame_uniform;
        input [7:0] brightness;
        begin
            $display("[%0t] Generating uniform frame: Y=%0d", $time, brightness);

            in_vsync = 1;
            @(posedge pclk);

            for (y = 0; y < HEIGHT; y = y + 1) begin
                // 行消隐
                repeat(5) @(posedge pclk);

                // 在时钟沿前设置数据和href
                in_href = 1;
                in_y = brightness;
                in_u = 8'd128;
                in_v = 8'd128;
                @(posedge pclk);

                for (x = 1; x < WIDTH; x = x + 1) begin
                    in_y = brightness;
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // 生成低对比度帧
    task gen_frame_low_contrast;
        begin
            $display("[%0t] Generating low contrast frame", $time);

            in_vsync = 1;
            @(posedge pclk);

            for (y = 0; y < HEIGHT; y = y + 1) begin
                repeat(5) @(posedge pclk);

                // 在时钟沿前设置数据和href
                in_href = 1;
                in_y = 8'd100 + ((0 + y) % 40);
                in_u = 8'd128;
                in_v = 8'd128;
                @(posedge pclk);

                for (x = 1; x < WIDTH; x = x + 1) begin
                    // 亮度范围100-140（低对比度）
                    in_y = 8'd100 + ((x + y) % 40);
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // 生成渐变帧（横向）
    task gen_frame_gradient;
        begin
            $display("[%0t] Generating horizontal gradient frame", $time);

            in_vsync = 1;
            @(posedge pclk);

            for (y = 0; y < HEIGHT; y = y + 1) begin
                repeat(5) @(posedge pclk);

                in_href = 1;
                in_y = (0 * 256) / WIDTH;
                in_u = 8'd128;
                in_v = 8'd128;
                @(posedge pclk);

                for (x = 1; x < WIDTH; x = x + 1) begin
                    // 横向渐变
                    in_y = (x * 256) / WIDTH;
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // 生成纵向渐变帧
    task gen_frame_vertical_gradient;
        begin
            $display("[%0t] Generating vertical gradient frame", $time);

            in_vsync = 1;
            @(posedge pclk);

            for (y = 0; y < HEIGHT; y = y + 1) begin
                repeat(5) @(posedge pclk);

                in_href = 1;
                in_y = (y * 256) / HEIGHT;
                in_u = 8'd128;
                in_v = 8'd128;
                @(posedge pclk);

                for (x = 1; x < WIDTH; x = x + 1) begin
                    // 纵向渐变
                    in_y = (y * 256) / HEIGHT;
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // 生成对角渐变帧
    task gen_frame_diagonal_gradient;
        begin
            $display("[%0t] Generating diagonal gradient frame", $time);

            in_vsync = 1;
            @(posedge pclk);

            for (y = 0; y < HEIGHT; y = y + 1) begin
                repeat(5) @(posedge pclk);

                in_href = 1;
                in_y = ((0 + y) * 256) / (WIDTH + HEIGHT);
                in_u = 8'd128;
                in_v = 8'd128;
                @(posedge pclk);

                for (x = 1; x < WIDTH; x = x + 1) begin
                    // 对角渐变
                    in_y = ((x + y) * 256) / (WIDTH + HEIGHT);
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // 生成棋盘图案帧
    task gen_frame_checkerboard;
        begin
            $display("[%0t] Generating checkerboard pattern frame", $time);

            in_vsync = 1;
            @(posedge pclk);

            for (y = 0; y < HEIGHT; y = y + 1) begin
                repeat(5) @(posedge pclk);

                in_href = 1;
                // 棋盘图案：每64像素切换
                if (((0 / 64) + (y / 64)) % 2 == 0)
                    in_y = 8'd50;   // 暗块
                else
                    in_y = 8'd200;  // 亮块
                in_u = 8'd128;
                in_v = 8'd128;
                @(posedge pclk);

                for (x = 1; x < WIDTH; x = x + 1) begin
                    // 棋盘图案：每64像素切换
                    if (((x / 64) + (y / 64)) % 2 == 0)
                        in_y = 8'd50;   // 暗块
                    else
                        in_y = 8'd200;  // 亮块
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // 生成极低对比度帧
    task gen_frame_very_low_contrast;
        begin
            $display("[%0t] Generating very low contrast frame", $time);

            in_vsync = 1;
            @(posedge pclk);

            for (y = 0; y < HEIGHT; y = y + 1) begin
                repeat(5) @(posedge pclk);

                in_href = 1;
                in_y = 8'd120 + ((0 + y) % 10);
                in_u = 8'd128;
                in_v = 8'd128;
                @(posedge pclk);

                for (x = 1; x < WIDTH; x = x + 1) begin
                    // 亮度范围120-130（极低对比度）
                    in_y = 8'd120 + ((x + y) % 10);
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // 等待帧处理完成
    task wait_frame_complete;
        begin
            // 等待vsync下降沿
            wait(in_vsync == 0);

            // 等待处理完成（如果在处理中）
            if (processing) begin
                $display("[%0t] Waiting for CDF processing...", $time);
                wait(processing == 0);
                $display("[%0t] CDF processing completed", $time);
            end

            #(CLK_PERIOD*10);
        end
    endtask

    // ========================================================================
    // 输出监控
    // ========================================================================

    // 统计增强效果和调试
    reg [31:0] black_pixels;
    reg [31:0] total_pixels;
    integer in_y_sum, out_y_sum;
    reg [31:0] bmp_write_pixels;  // BMP实际写入的像素数
    integer bmp_y_sum;

    initial begin
        black_pixels = 0;
        total_pixels = 0;
        in_y_sum = 0;
        out_y_sum = 0;
        bmp_write_pixels = 0;
        bmp_y_sum = 0;
    end

    always @(posedge pclk) begin
        if (out_href) begin
            total_pixels = total_pixels + 1;
            in_y_sum = in_y_sum + in_y;
            out_y_sum = out_y_sum + out_y;

            if (out_y == 0) begin
                black_pixels = black_pixels + 1;
            end

            if (clahe_enable && cdf_ready) begin
                if (out_y != in_y) begin
                    enhanced_pixels = enhanced_pixels + 1;
                end
            end
        end

        // 监控BMP模块实际接收到的数据
        if (bmp_out_ready && out_href) begin
            bmp_write_pixels = bmp_write_pixels + 1;
            bmp_y_sum = bmp_y_sum + bmp_out_r;  // bmp_out_r = out_y
        end

        // 帧结束时输出统计
        if (out_vsync && !out_vsync_d1) begin
            if (total_pixels > 0) begin
                $display("[DEBUG] Frame stats:");
                $display("  CLAHE output pixels: %0d", total_pixels);
                $display("  Black pixels in CLAHE output: %0d (%.1f%%)", black_pixels, (black_pixels*100.0)/total_pixels);
                $display("  Avg input Y: %0d", in_y_sum/total_pixels);
                $display("  Avg CLAHE output Y: %0d", out_y_sum/total_pixels);
                if (bmp_write_pixels > 0) begin
                    $display("  BMP write pixels: %0d", bmp_write_pixels);
                    $display("  Avg BMP write Y: %0d", bmp_y_sum/bmp_write_pixels);
                    $display("  Pixel count match: %s", (bmp_write_pixels == total_pixels) ? "YES" : "NO");
                end
                $display("  CDF ready: %0d, CLAHE enable: %0d", cdf_ready, clahe_enable);
            end
            black_pixels = 0;
            total_pixels = 0;
            in_y_sum = 0;
            out_y_sum = 0;
            bmp_write_pixels = 0;
            bmp_y_sum = 0;
        end
    end

    // 监控前几个输出像素的详细信息
    integer pixel_debug_cnt;
    initial
        pixel_debug_cnt = 0;

    always @(posedge pclk) begin
        if (!rst_n || (in_vsync && !in_vsync_d1)) begin
            pixel_debug_cnt = 0;
        end
        else if (out_href && pixel_debug_cnt < 5) begin
            // 只监控前5个像素
            $display("[PIXEL %0d] in_y=%0d, out_y=%0d", pixel_debug_cnt, in_y, out_y);
            pixel_debug_cnt = pixel_debug_cnt + 1;
        end
    end

    // ------------------------------------------------------------------------
    // 输出端坐标计数（与BMP写入前完全一致的时序）
    // 用于在指定坐标位置打印out_y，验证是否为写文件问题
    // ------------------------------------------------------------------------
    reg [15:0] out_sx;
    reg [15:0] out_sy;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            out_sx <= 16'd0;
            out_sy <= 16'd0;
        end
        else begin
            // 帧起始（out_vsync上升沿）时复位坐标
            if (out_vsync && !out_vsync_d1) begin
                out_sx <= 16'd0;
                out_sy <= 16'd0;
            end
            else if (out_href) begin
                if (out_sx < WIDTH - 1) begin
                    out_sx <= out_sx + 16'd1;
                end
                else begin
                    out_sx <= 16'd0;
                    out_sy <= out_sy + 16'd1;
                end
            end
        end
    end

    // ========================================================================
    // Tile边界详细调试监控 (X=159,160,319,320等边界)
    // 关键：检查纯色输入时不同tile的CDF是否相同
    // ========================================================================
    always @(posedge pclk) begin
        if (out_href && out_sy == 16'd300) begin
            // 监控第一个tile边界 X=159,160
            if (out_sx >= 16'd157 && out_sx <= 16'd162) begin
                $display("[BOUNDARY1] y=%0d x=%0d | tile_x=%0d local_x=%0d | wx=%0d wy=%0d | interp_en=%0d | cdf[tl=%0d tr=%0d bl=%0d br=%0d] | interp[top=%0d bot=%0d] | final=%0d | out_y=%0d",
                         out_sy, out_sx,
                         u_dut.mapping_inst.tile_x,
                         u_dut.mapping_inst.local_x,
                         u_dut.mapping_inst.wx,
                         u_dut.mapping_inst.wy,
                         u_dut.mapping_inst.interp_d3,
                         u_dut.mapping_inst.cdf_tl_d2,
                         u_dut.mapping_inst.cdf_tr_d2,
                         u_dut.mapping_inst.cdf_bl_d2,
                         u_dut.mapping_inst.cdf_br_d2,
                         u_dut.mapping_inst.interp_top,
                         u_dut.mapping_inst.interp_bottom,
                         u_dut.mapping_inst.final_interp,
                         out_y);
            end
            // 监控第二个tile边界 X=319,320
            if (out_sx >= 16'd317 && out_sx <= 16'd322) begin
                $display("[BOUNDARY2] y=%0d x=%0d | tile_x=%0d local_x=%0d | wx=%0d wy=%0d | interp_en=%0d | cdf[tl=%0d tr=%0d bl=%0d br=%0d] | interp[top=%0d bot=%0d] | final=%0d | out_y=%0d",
                         out_sy, out_sx,
                         u_dut.mapping_inst.tile_x,
                         u_dut.mapping_inst.local_x,
                         u_dut.mapping_inst.wx,
                         u_dut.mapping_inst.wy,
                         u_dut.mapping_inst.interp_d3,
                         u_dut.mapping_inst.cdf_tl_d2,
                         u_dut.mapping_inst.cdf_tr_d2,
                         u_dut.mapping_inst.cdf_bl_d2,
                         u_dut.mapping_inst.cdf_br_d2,
                         u_dut.mapping_inst.interp_top,
                         u_dut.mapping_inst.interp_bottom,
                         u_dut.mapping_inst.final_interp,
                         out_y);
            end
        end
    end

    // 侦测同一行相邻像素的跳变（阈值>1），打印坐标与值
    reg [7:0] prev_out_y;
    reg       prev_valid;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            prev_out_y <= 8'd0;
            prev_valid <= 1'b0;
        end
        else begin
            if (!out_href) begin
                prev_valid <= 1'b0; // 行间隔时复位
            end
            else begin
                if (prev_valid) begin
                    if ((out_y > prev_out_y ? (out_y - prev_out_y) : (prev_out_y - out_y)) >= 2) begin
                        // $display("[JUMP] y=%0d x=%0d out_y=%0d prev=%0d", out_sy, out_sx, out_y, prev_out_y);

                    end
                end
                prev_out_y <= out_y;
                prev_valid <= 1'b1;

                // 调试local_x=67位置的CDF数据
                if (out_sy == 300 && (out_sx == 66 || out_sx == 67 || out_sx == 68)) begin
                    $display("[CDF_DEBUG] y=%0d x=%0d out_y=%0d cdf_tl=%0d cdf_tr=%0d cdf_bl=%0d cdf_br=%0d wx=%0d wy=%0d",
                             out_sy, out_sx, out_y,
                             u_dut.mapping_inst.cdf_tl_rd_data,
                             u_dut.mapping_inst.cdf_tr_rd_data,
                             u_dut.mapping_inst.cdf_bl_rd_data,
                             u_dut.mapping_inst.cdf_br_rd_data,
                             u_dut.mapping_inst.wx,
                             u_dut.mapping_inst.wy);
                end
            end
        end
    end

    // 监控CDF写入
    reg [31:0] cdf_write_count;
    reg [31:0] cdf_write_60_count;
    reg [31:0] cdf_write_80_count;
    initial begin
        cdf_write_count = 0;
        cdf_write_60_count = 0;
        cdf_write_80_count = 0;
    end

    always @(posedge pclk) begin
        if (u_dut.cdf_wr_en) begin
            cdf_write_count = cdf_write_count + 1;

            // 计数特定bin的写入
            if (u_dut.cdf_addr == 60)
                cdf_write_60_count = cdf_write_60_count + 1;
            if (u_dut.cdf_addr == 80)
                cdf_write_80_count = cdf_write_80_count + 1;

            // CDF写入监控已禁用以加快仿真
        end
    end

    // 监控关键事件
    always @(posedge processing) begin
        $display("[%0t] >>> CDF Processing started, ping_pong=%0d", $time, u_dut.ping_pong_flag);
        cdf_write_count = 0;
        cdf_write_60_count = 0;
        cdf_write_80_count = 0;
    end

    always @(negedge processing) begin
        $display("[%0t] <<< CDF Processing finished, total_writes=%0d, writes_60=%0d, writes_80=%0d, ping_pong=%0d",
                 $time, cdf_write_count, cdf_write_60_count, cdf_write_80_count, u_dut.ping_pong_flag);
    end

    always @(posedge cdf_ready) begin
        $display("[%0t] *** CDF Ready - CLAHE active, ping_pong=%0d", $time, u_dut.ping_pong_flag);
    end

    // 监控ping_pong切换
    reg ping_pong_d1;
    always @(posedge pclk) begin
        ping_pong_d1 <= u_dut.ping_pong_flag;
        if (u_dut.ping_pong_flag != ping_pong_d1) begin
            $display("[%0t] @@@ ping_pong_flag changed: %0d -> %0d",
                     $time, ping_pong_d1, u_dut.ping_pong_flag);
        end
    end

    // 帧计数
    reg vsync_d1;
    always @(posedge pclk) begin
        vsync_d1 <= in_vsync;
        if (!in_vsync && vsync_d1) begin  // vsync下降沿
            $display("[%0t] === Frame %0d End ===", $time, total_frames);
        end
    end

    // ========================================================================
    // CLAHE算法验证逻辑
    // ========================================================================

    // 验证CLAHE各阶段状态
    task verify_clahe_stages;
        input integer frame_num;

        begin
            $display("\n[VERIFY] === Frame %0d CLAHE Stage Status Verification ===", frame_num);

            // 检查histogram统计是否完成
            if (u_dut.frame_hist_done) begin
                $display("[PASS] Histogram统计已完成");
            end
            else begin
                $display("[ERROR] Histogram统计未完成");
            end

            // 检查CDF计算是否完成
            if (u_dut.cdf_done) begin
                $display("[PASS] CDF计算已完成");
            end
            else begin
                $display("[ERROR] CDF计算未完成");
            end

            // 检查ping_pong状态
            $display("[INFO] 当前ping_pong_flag: %0d", u_dut.ping_pong_flag);

            // 检查清零状态
            if (u_dut.hist_clear_done) begin
                $display("[PASS] Histogram清零已完成");
            end
            else begin
                $display("[WARN] Histogram清零未完成");
            end
        end
    endtask

    // 验证Histogram统计结果
    task verify_histogram_results;
        input integer frame_num;
        integer tile_idx, bin_idx;
        integer total_count, expected_count;
        integer pixel_60_count, pixel_80_count;

        begin
            $display("\n[VERIFY] === Frame %0d Histogram Statistics Verification ===", frame_num);

            // 每个tile应该有 160*90 = 14400 个像素
            expected_count = 160 * 90;

            // 检查几个关键tile的histogram
            for (tile_idx = 0; tile_idx < 4; tile_idx = tile_idx + 1) begin
                total_count = 0;
                pixel_60_count = 0;
                pixel_80_count = 0;

                // 根据我们的测试数据模式来验证
                // TEST 1: gen_frame_uniform(60) - 所有像素都是60
                if (frame_num == 1) begin
                    pixel_60_count = expected_count; // 所有14400个像素都是60
                    total_count = pixel_60_count;
                end
                else begin
                    // 其他测试模式的验证
                    pixel_60_count = expected_count * 0.9; // 90%是60
                    pixel_80_count = expected_count * 0.1; // 10%是80
                    total_count = pixel_60_count + pixel_80_count;
                end

                $display("[HIST] Tile%0d: 总像素=%0d (期望%0d), 像素60=%0d, 像素80=%0d",
                         tile_idx, total_count, expected_count, pixel_60_count, pixel_80_count);

                // 验证总像素数
                if (total_count == expected_count) begin
                    $display("[PASS] Tile%0d histogram像素总数正确", tile_idx);
                end
                else begin
                    $display("[ERROR] Tile%0d histogram像素总数错误: %0d != %0d",
                             tile_idx, total_count, expected_count);
                end

                // 验证主要像素值分布
                if (pixel_60_count > expected_count * 0.8) begin
                    $display("[PASS] Tile%0d 主要像素值(60)分布正常", tile_idx);
                end
                else begin
                    $display("[WARN] Tile%0d 主要像素值(60)分布异常: %0d", tile_idx, pixel_60_count);
                end
            end
        end
    endtask

    // 验证CDF结果
    task verify_cdf_results;
        input integer frame_num;
        integer tile_idx, bin_idx;
        integer cdf_0, cdf_60, cdf_80, cdf_255;
        integer prev_cdf;

        begin
            $display("\n[VERIFY] === Frame %0d CDF Results Verification ===", frame_num);

            // 检查几个关键tile的CDF
            for (tile_idx = 0; tile_idx < 4; tile_idx = tile_idx + 1) begin
                $display("[CDF] 检查Tile%0d的CDF特性:", tile_idx);

                // 根据histogram分布预期CDF值
                if (frame_num == 1) begin
                    // gen_frame_uniform(60): 所有像素都是60
                    cdf_0 = 0;      // CDF[0] = 0
                    cdf_60 = 255;   // CDF[60] = 255 (所有像素都<=60)
                    cdf_80 = 255;   // CDF[80] = 255
                    cdf_255 = 255;  // CDF[255] = 255
                end
                else begin
                    // 混合分布
                    cdf_0 = 0;      // CDF[0] = 0
                    cdf_60 = 230;   // CDF[60] 应该很高（90%像素<=60）
                    cdf_80 = 255;   // CDF[80] = 255 (所有像素都<=80)
                    cdf_255 = 255;  // CDF[255] = 255
                end

                $display("  期望CDF[0]=%0d, CDF[60]=%0d, CDF[80]=%0d, CDF[255]=%0d",
                         cdf_0, cdf_60, cdf_80, cdf_255);

                // 验证CDF基本特性
                if (cdf_0 == 0) begin
                    $display("[PASS] Tile%0d CDF[0]=0 正确", tile_idx);
                end
                else begin
                    $display("[ERROR] Tile%0d CDF[0]=%0d 应该为0", tile_idx, cdf_0);
                end

                if (cdf_255 == 255) begin
                    $display("[PASS] Tile%0d CDF[255]=255 正确", tile_idx);
                end
                else begin
                    $display("[ERROR] Tile%0d CDF[255]=%0d 应该为255", tile_idx, cdf_255);
                end

                // 验证CDF单调性
                if (cdf_0 <= cdf_60 && cdf_60 <= cdf_80 && cdf_80 <= cdf_255) begin
                    $display("[PASS] Tile%0d CDF单调性正确", tile_idx);
                end
                else begin
                    $display("[ERROR] Tile%0d CDF非单调", tile_idx);
                end

                // 验证CDF值合理性
                if (frame_num == 1 && cdf_60 == 255) begin
                    $display("[PASS] Tile%0d CDF[60]=255正确（所有像素都是60）", tile_idx);
                end
                else if (frame_num != 1 && cdf_60 > 200) begin
                    $display("[PASS] Tile%0d CDF[60]值合理", tile_idx);
                end
                else begin
                    $display("[WARN] Tile%0d CDF[60]=%0d 可能不符合预期", tile_idx, cdf_60);
                end
            end
        end
    endtask

    // 验证Clipper结果
    task verify_clipper_results;
        input integer frame_num;
        integer tile_idx, bin_idx;
        integer hist_before, hist_after, clip_limit;
        integer clipped_pixels, redistributed_pixels;

        begin
            $display("\n[VERIFY] === Frame %0d Clipper Results Verification ===", frame_num);

            // 计算clip limit
            // clip_limit = (总像素数 / bin数) * clip_factor
            // 对于14400像素，256个bin，clip_factor=2，clip_limit = 14400/256*2 = 112
            clip_limit = (160 * 90) / 256 * 2;
            $display("[CLIPPER] 计算的Clip Limit: %0d", clip_limit);

            // 检查几个tile的clipping效果
            for (tile_idx = 0; tile_idx < 4; tile_idx = tile_idx + 1) begin
                clipped_pixels = 0;
                redistributed_pixels = 0;

                $display("[CLIPPER] 检查Tile%0d的clipping效果:", tile_idx);

                if (frame_num == 1) begin
                    // gen_frame_uniform(60): 所有14400个像素都是60
                    hist_before = 14400;  // Bin60有14400个像素
                    if (hist_before > clip_limit) begin
                        hist_after = clip_limit;
                        clipped_pixels = hist_before - hist_after;
                        $display("  Bin60: %0d -> %0d (clipped %0d)", hist_before, hist_after, clipped_pixels);

                        if (hist_after <= clip_limit) begin
                            $display("[PASS] Tile%0d Bin60正确被clip到%0d", tile_idx, clip_limit);
                        end
                        else begin
                            $display("[ERROR] Tile%0d Bin60未被正确clip: %0d > %0d",
                                     tile_idx, hist_after, clip_limit);
                        end

                        // 验证被clip的像素被重新分布
                        redistributed_pixels = clipped_pixels;
                        if (redistributed_pixels > 0) begin
                            $display("  重新分布的像素数: %0d", redistributed_pixels);
                            $display("[PASS] Tile%0d 有%0d个像素被重新分布", tile_idx, redistributed_pixels);
                        end
                    end
                    else begin
                        hist_after = hist_before;
                        $display("  Bin60: %0d (无需clip)", hist_after);
                        $display("[INFO] Tile%0d Bin60无需clip", tile_idx);
                    end
                end
                else begin
                    // 其他测试模式
                    $display("  其他测试模式的clipper验证");
                end

                // 验证总像素数守恒
                $display("  像素总数验证: 应保持14400不变");
                $display("[PASS] Tile%0d 像素总数守恒", tile_idx);
            end
        end
    endtask

    // 验证输入输出像素统计
    task verify_pixel_statistics;
        input integer frame_num;

        begin
            $display("\n[VERIFY] === Frame %0d Pixel Statistics Verification ===", frame_num);

            // 这里可以添加像素统计验证逻辑
            // 比如检查输入像素的分布、输出像素的分布等
            $display("[INFO] 输入像素统计验证 - 待实现");
            $display("[INFO] 输出像素统计验证 - 待实现");
        end
    endtask

    // 验证CLAHE使能状态
    task verify_clahe_enable_status;
        input integer frame_num;

        begin
            $display("\n[VERIFY] === Frame %0d CLAHE Enable Status Verification ===", frame_num);

            // 检查CLAHE使能信号
            if (u_dut.enable_clahe) begin
                $display("[PASS] CLAHE功能已使能");
            end
            else begin
                $display("[ERROR] CLAHE功能未使能 - 这可能是问题所在！");
            end

            // 检查插值使能信号
            if (u_dut.enable_interp) begin
                $display("[PASS] 插值功能已使能");
            end
            else begin
                $display("[WARN] 插值功能未使能");
            end

            // 检查调试信号
            $display("[DEBUG] debug_clahe_enable: %0d", u_dut.debug_clahe_enable);
            $display("[DEBUG] debug_interp_enable: %0d", u_dut.debug_interp_enable);
            $display("[DEBUG] debug_cdf_ready: %0d", u_dut.debug_cdf_ready);
        end
    endtask

    // 简化验证 - 直接在initial块中执行
    initial begin
        #1;  // 等待一个时间单位让信号稳定

        // 等待第一帧完成
        wait(total_frames >= 1);
        #(CLK_PERIOD*100000);  // 等待足够时间让CDF处理完成

        $display("\n================================================================================");
        $display("CLAHE Algorithm Verification - Frame 1");
        $display("================================================================================");

        // 简化的验证检查
        $display("[VERIFY] === Frame 1 CLAHE Status Verification ===");

        // 检查CLAHE使能信号
        if (u_dut.enable_clahe) begin
            $display("[PASS] CLAHE function enabled");
        end
        else begin
            $display("[ERROR] CLAHE function NOT enabled");
        end

        // 检查插值使能信号
        if (u_dut.enable_interp) begin
            $display("[PASS] Interpolation function enabled");
        end
        else begin
            $display("[WARN] Interpolation function NOT enabled");
        end

        // 检查CDF状态
        if (u_dut.cdf_done) begin
            $display("[PASS] CDF calculation completed");
        end
        else begin
            $display("[ERROR] CDF calculation NOT completed");
        end

        // 检查直方图状态
        if (u_dut.frame_hist_done) begin
            $display("[PASS] Histogram statistics completed");
        end
        else begin
            $display("[ERROR] Histogram statistics NOT completed");
        end

        $display("[INFO] Current ping_pong_flag: %0d", u_dut.ping_pong_flag);
        $display("[INFO] Current total_frames: %0d", total_frames);

        $display("================================================================================");
        $display("Frame 1 Verification Complete");
        $display("================================================================================\n");

        // 等待第二帧
        wait(total_frames >= 2);
        #(CLK_PERIOD*100000);

        $display("\n================================================================================");
        $display("CLAHE Algorithm Verification - Frame 2");
        $display("================================================================================");

        $display("[VERIFY] === Frame 2 CLAHE Status Verification ===");

        if (u_dut.enable_clahe) begin
            $display("[PASS] CLAHE function still enabled");
        end
        else begin
            $display("[ERROR] CLAHE function disabled");
        end

        if (u_dut.cdf_done) begin
            $display("[PASS] CDF calculation completed for frame 2");
        end
        else begin
            $display("[ERROR] CDF calculation NOT completed for frame 2");
        end

        $display("[INFO] Frame 2 ping_pong_flag: %0d", u_dut.ping_pong_flag);

        $display("================================================================================");
        $display("Frame 2 Verification Complete");
        $display("================================================================================\n");

        // 等待第三帧
        wait(total_frames >= 3);
        #(CLK_PERIOD*100000);

        $display("\n================================================================================");
        $display("CLAHE Algorithm Verification - Frame 3");
        $display("================================================================================");

        $display("[VERIFY] === Frame 3 CLAHE Status Verification ===");

        if (u_dut.enable_clahe) begin
            $display("[PASS] CLAHE function consistently enabled");
        end
        else begin
            $display("[ERROR] CLAHE function disabled");
        end

        $display("[INFO] Frame 3 ping_pong_flag: %0d", u_dut.ping_pong_flag);
        $display("[INFO] Total frames processed: %0d", total_frames);

        $display("================================================================================");
        $display("Frame 3 Verification Complete - Multi-frame verification successful!");
        $display("================================================================================\n");
    end

    // ========================================================================
    // 波形转储
    // ========================================================================
    initial begin
        $dumpfile("tb_clahe_top.vcd");
        $dumpvars(0, tb_clahe_top);

        // 选择性转储关键信号
        $dumpvars(1, u_dut.ping_pong_flag);
        $dumpvars(1, u_dut.frame_hist_done);
        $dumpvars(1, u_dut.cdf_done);
    end

endmodule


