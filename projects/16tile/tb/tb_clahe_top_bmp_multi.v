// ============================================================================
// Testbench for CLAHE顶层模块 - 多帧实际BMP图像输入测试
//
// 功能说明:
//   使用实际BMP图像文件作为输入，进行连续多帧CLAHE处理测试
//   支持自定义分辨率和时序参数
//   自动保存输入和输出BMP图像
//
// 测试流程:
//   1. 从bmp_in/目录读取多个BMP文件
//   2. 依次输入到CLAHE模块进行处理
//   3. 保存处理后的结果到sim_outputs/目录
//   4. 支持连续多帧处理，验证乒乓缓存机制
//
// 使用方法:
//   - 将待处理的BMP图像放在 sim/bmp_in/ 目录
//   - 运行仿真，自动读取并处理所有图像
//   - 结果保存在 sim/sim_outputs/ 目录
//
// 作者: Passionate.Z
// 日期: 2025-10-30
// ============================================================================

`timescale 1ns/100ps

module tb_clahe_top_bmp_multi #(
        // ========================================================================
        // 全局参数接口
        // ========================================================================
        parameter ENABLE_CLAHE  = 1,     // CLAHE功能使能：1=启用，0=禁用
        parameter ENABLE_INTERP = 1,     // 插值功能使能：1=启用，0=禁用
        parameter CLIP_THRESHOLD = 600, // Clip限制值
        parameter NUM_FRAMES = 3,        // 要处理的帧数

        // 图像分辨率参数（根据实际BMP调整）
        parameter IMAGE_WIDTH = 1280,
        parameter IMAGE_HEIGHT = 720
    ) ();

    // ========================================================================
    // 时序参数定义
    // ========================================================================
    parameter CLK_PERIOD = 13.5;  // 74.25MHz

    // 1280x720 分辨率时序参数
    parameter H_SYNC   = 11'd40;
    parameter H_BACK   = 11'd220;
    parameter H_DISP   = IMAGE_WIDTH;
    parameter H_FRONT  = 11'd110;
    parameter H_TOTAL  = 11'd1650;

    parameter V_SYNC   = 11'd5;
    parameter V_BACK   = 11'd20;
    parameter V_DISP   = IMAGE_HEIGHT;
    parameter V_FRONT  = 11'd5;
    parameter V_TOTAL  = 11'd750;

    // ========================================================================
    // 信号定义
    // ========================================================================
    reg         pclk;
    reg         rst_n;
    reg         clahe_enable;
    reg         interp_enable;
    reg  [15:0] clip_threshold;

    // CLAHE模块接口
    wire        in_href;
    wire        in_vsync;
    wire [7:0]  in_y;
    wire [7:0]  in_u;
    wire [7:0]  in_v;

    wire        out_href;
    wire        out_vsync;
    wire [7:0]  out_y;
    wire [7:0]  out_u;
    wire [7:0]  out_v;

    // CLAHE内部状态信号（必须在initial块之前定义）
    wire        processing;
    wire        cdf_ready;
    wire        ping_pong_flag;

    // Frame 0调试变量（必须在initial块之前定义）
    integer debug_pixel_count;
    integer debug_nonzero_count;
    integer debug_y_sum;
    integer debug_y_max;

    // BMP读取模块信号
    wire [2:0][7:0] bmp_in_data;  // RGB数据
    wire            bmp_in_valid;
    wire            bmp_in_hsync;
    wire            bmp_in_vsync;
    wire            bmp_in_done;
    wire [15:0]     bmp_in_xres;
    wire [15:0]     bmp_in_yres;

    reg             bmp_begin;     // BMP开始读取信号

    // BMP保存模块信号 - 输出
    wire        bmp_out_ready;
    wire [7:0]  bmp_out_b, bmp_out_g, bmp_out_r;
    wire        bmp_out_frame_sync_n;
    wire [15:0] bmp_xres;
    wire [15:0] bmp_yres;

    // BMP保存模块信号 - 输入捕获
    wire        bmp_in_save_ready;
    wire [7:0]  bmp_in_save_b, bmp_in_save_g, bmp_in_save_r;
    wire        bmp_in_save_frame_sync_n;

    // 测试控制
    integer frame_count;

    // ========================================================================
    // 时钟生成
    // ========================================================================
    initial begin
        pclk = 0;
        forever
            #(CLK_PERIOD/2) pclk = ~pclk;
    end

    // ========================================================================
    // DUT实例化 - CLAHE顶层模块
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
    // BMP读取模块 - 将BMP文件转换为视频流
    // ========================================================================
    bmp_to_videoStream #(
                           .H_SYNC(H_SYNC),
                           .H_BACK(H_BACK),
                           .H_DISP(H_DISP),
                           .H_FRONT(H_FRONT),
                           .H_TOTAL(H_TOTAL),
                           .V_SYNC(V_SYNC),
                           .V_BACK(V_BACK),
                           .V_DISP(V_DISP),
                           .V_FRONT(V_FRONT),
                           .V_TOTAL(V_TOTAL),
                           .iBMP_FILE_PATH("E:/FPGA_codes/CLAHE/projects/16tile/sim/bmp_in/"),
                           .iBMP_FILE_NAME("test_standard.bmp")  // 使用绝对路径（正斜杠）
                       ) u_bmp_reader (
                           .clk(pclk),
                           .rst_n(rst_n),
                           .vout_vsync(bmp_in_vsync),
                           .vout_hsync(bmp_in_hsync),
                           .vout_dat(bmp_in_data),
                           .vout_valid(bmp_in_valid),
                           .vout_begin(bmp_begin),
                           .vout_done(bmp_in_done),
                           .vout_xres(bmp_in_xres),
                           .vout_yres(bmp_in_yres)
                       );

    // ========================================================================
    // RGB到YUV转换（高精度版本 ITU-R BT.601）
    // ========================================================================
    // RGB到YUV转换公式（更高精度系数）：
    //   Y = 0.299*R + 0.587*G + 0.114*B
    //   U = -0.147*R - 0.289*G + 0.436*B + 128
    //   V = 0.615*R - 0.515*G - 0.100*B + 128
    //
    // 高精度定点数近似（使用更大的系数，右移更多位）：
    //   Y = (19595*R + 38470*G + 7471*B) >> 16
    //   U = ((-9642*R - 18964*G + 28606*B) >> 16) + 128
    //   V = ((40304*R - 33750*G - 6554*B) >> 16) + 128
    //
    // 精度：16位定点数（Q16格式），误差 < 0.5 LSB
    // vout_dat[0]=B, vout_dat[1]=G, vout_dat[2]=R

    wire [31:0] y_temp;
    wire signed [31:0] u_temp;
    wire signed [31:0] v_temp;

    assign y_temp = (19595 * bmp_in_data[2] + 38470 * bmp_in_data[1] + 7471 * bmp_in_data[0]);
    assign u_temp = (-9642 * $signed({1'b0, bmp_in_data[2]}) - 18964 * $signed({1'b0, bmp_in_data[1]}) + 28606 * $signed({1'b0, bmp_in_data[0]}));
    assign v_temp = (40304 * $signed({1'b0, bmp_in_data[2]}) - 33750 * $signed({1'b0, bmp_in_data[1]}) - 6554 * $signed({1'b0, bmp_in_data[0]}));

    // 带饱和和舍入的转换
    function [7:0] saturate_uv;
        input signed [31:0] val;
        reg signed [31:0] shifted_val;
        reg signed [31:0] result;
        begin
            shifted_val = (val + 32'sd32768) >>> 16;  // 加0.5后算术右移16位（舍入）
            result = shifted_val + 32'sd128;  // 加128偏移
            if (result < 0)
                saturate_uv = 8'd0;
            else if (result > 255)
                saturate_uv = 8'd255;
            else
                saturate_uv = result[7:0];
        end
    endfunction

    function [7:0] saturate_y;
        input [31:0] val;
        reg [31:0] shifted_val;
        begin
            shifted_val = (val + 32'd32768) >> 16;  // 加0.5后右移16位（舍入）
            if (shifted_val > 255)
                saturate_y = 8'd255;
            else
                saturate_y = shifted_val[7:0];
        end
    endfunction

    assign in_y = saturate_y(y_temp);
    assign in_u = saturate_uv(u_temp);
    assign in_v = saturate_uv(v_temp);
    assign in_href = bmp_in_valid;
    assign in_vsync = bmp_in_vsync;

    // ========================================================================
    // BMP保存模块 - 保存输入图像
    // ========================================================================
    bmp_for_videoStream_24bit #(
                                  .iREADY(10),
                                  .iBMP_FILE_PATH("bmp_test_results/input/"),
                                  .iBMP_FILE_NAME("input_frame")
                              ) u_bmp_input_writer (
                                  .clk(pclk),
                                  .rst_n(rst_n),
                                  .frame_sync_n(bmp_in_save_frame_sync_n),
                                  .vin_ready(bmp_in_save_ready),
                                  .vin_dat({bmp_in_save_r, bmp_in_save_g, bmp_in_save_b}),
                                  .vin_valid(in_href),
                                  .vin_xres(bmp_xres),
                                  .vin_yres(bmp_yres)
                              );

    // ========================================================================
    // BMP保存模块 - 保存输出图像
    // ========================================================================
    bmp_for_videoStream_24bit #(
                                  .iREADY(10),
                                  .iBMP_FILE_PATH("bmp_test_results/output/"),
                                  .iBMP_FILE_NAME("output_frame")
                              ) u_bmp_output_writer (
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
    // YUV到RGB转换
    // ========================================================================
    // 输入图像保存 - 保留原始RGB颜色
    assign bmp_in_save_r = bmp_in_data[2];  // 原始R通道
    assign bmp_in_save_g = bmp_in_data[1];  // 原始G通道
    assign bmp_in_save_b = bmp_in_data[0];  // 原始B通道

    // 输出图像保存 - YUV到RGB转换（高精度版本）
    // 标准YUV到RGB转换公式（ITU-R BT.601）：
    //   R = Y + 1.402 * (V - 128)
    //   G = Y - 0.344 * (U - 128) - 0.714 * (V - 128)
    //   B = Y + 1.772 * (U - 128)
    //
    // 高精度定点数近似（Q16格式，右移16位）：
    //   R = Y + ((91881 * (V - 128)) >> 16)
    //   G = Y - ((22554 * (U - 128)) >> 16) - ((46802 * (V - 128)) >> 16)
    //   B = Y + ((116130 * (U - 128)) >> 16)
    //
    // 精度：16位定点数，误差 < 0.5 LSB

    wire signed [16:0] u_offset = $signed({9'd0, out_u}) - 17'sd128;
    wire signed [16:0] v_offset = $signed({9'd0, out_v}) - 17'sd128;

    wire signed [33:0] r_temp = ($signed({26'd0, out_y}) << 16) + (34'sd91881 * v_offset);
    wire signed [33:0] g_temp = ($signed({26'd0, out_y}) << 16) - (34'sd22554 * u_offset) - (34'sd46802 * v_offset);
    wire signed [33:0] b_temp = ($signed({26'd0, out_y}) << 16) + (34'sd116130 * u_offset);

    // 饱和处理并右移16位（带舍入）
    function [7:0] saturate_rgb;
        input signed [33:0] val;
        reg signed [33:0] shifted;
        begin
            shifted = (val + 34'sd32768) >>> 16;  // 加0.5后算术右移16位（舍入）
            if (shifted < 0)
                saturate_rgb = 8'd0;
            else if (shifted > 255)
                saturate_rgb = 8'd255;
            else
                saturate_rgb = shifted[7:0];
        end
    endfunction

    assign bmp_out_r = saturate_rgb(r_temp);
    assign bmp_out_g = saturate_rgb(g_temp);
    assign bmp_out_b = saturate_rgb(b_temp);

    // ========================================================================
    // BMP写入控制信号生成
    // ========================================================================
    // 输入BMP控制信号
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
    assign bmp_in_save_frame_sync_n = !(in_vsync_d1 && !in_vsync_d2);

    // 输出BMP控制信号
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

    assign bmp_xres = IMAGE_WIDTH;
    assign bmp_yres = IMAGE_HEIGHT;

    // ========================================================================
    // 测试主流程
    // ========================================================================
    initial begin
        // 创建输出目录
        $system("if not exist bmp_test_results mkdir bmp_test_results");
        $system("if not exist bmp_test_results\\input mkdir bmp_test_results\\input");
        $system("if not exist bmp_test_results\\output mkdir bmp_test_results\\output");

        // 初始化信号
        rst_n = 0;
        clahe_enable = ENABLE_CLAHE;
        interp_enable = ENABLE_INTERP;
        clip_threshold = CLIP_THRESHOLD;
        bmp_begin = 0;
        frame_count = 0;

        // 显示测试信息
        $display("\n========================================");
        $display("  CLAHE BMP Multi-Frame Test");
        $display("========================================");
        $display("  Image Resolution: %0dx%0d", IMAGE_WIDTH, IMAGE_HEIGHT);
        $display("  Number of Image Sets: %0d", NUM_FRAMES);
        $display("  Total Frames: %0d (each image input twice)", NUM_FRAMES*2);
        $display("  CLAHE Enable:     %0d", ENABLE_CLAHE);
        $display("  Interp Enable:    %0d", ENABLE_INTERP);
        $display("  Clip Threshold:   %0d", CLIP_THRESHOLD);
        $display("  Input Path:       sim/bmp_in/");
        $display("  Output Path:      bmp_test_results/");
        $display("    - Input images:  bmp_test_results/input/");
        $display("    - Output images: bmp_test_results/output/");
        $display("");
        $display("  Note: Each image is input twice:");
        $display("    1st pass: Build histogram (output enhanced)");
        $display("    2nd pass: Apply CLAHE enhancement");
        $display("========================================\n");

        // 复位
        #(CLK_PERIOD*20);
        rst_n = 1;
        $display("[%0t] Reset released", $time);

        // 等待RAM清零完成
        // 清零需要512周期（256地址 × 2轮初始化）
        $display("[%0t] Waiting for RAM initialization...", $time);
        #(CLK_PERIOD*600);  // 等待600周期，确保清零完全完成
        $display("[%0t] RAM initialization complete", $time);

        #(CLK_PERIOD*10);

        // ====================================================================
        // 连续处理多帧 - 每个图像输入两次
        // 第一次：统计直方图（输出为bypass）
        // 第二次：应用CLAHE增强
        // ====================================================================
        for (frame_count = 0; frame_count < NUM_FRAMES; frame_count = frame_count + 1) begin
            $display("\n[%0t] ========================================", $time);
            $display("[%0t] Image Set %0d - Frame Pair (%0d, %0d)", $time, frame_count, frame_count*2, frame_count*2+1);
            $display("[%0t] ========================================", $time);

            // 第一次输入：统计直方图，输出使用全0 CDF（预期全黑或很暗）
            $display("\n[%0t] --- Frame %0d: Histogram Building (CDF all zeros) ---", $time, frame_count*2);
            clahe_enable = ENABLE_CLAHE;  // 保持CLAHE启用
            #(CLK_PERIOD*100);
            $display("[%0t] Setting bmp_begin=1", $time);
            bmp_begin = 1;
            #(CLK_PERIOD);
            $display("[%0t] Setting bmp_begin=0", $time);
            bmp_begin = 0;
            $display("[%0t] Waiting for bmp_in_done...", $time);

            wait(bmp_in_done);
            $display("[%0t] Frame %0d input complete (histogram collected)", $time, frame_count*2);

            // 等待CDF处理完成
            wait(processing == 0);
            $display("[%0t] Frame %0d CDF processing complete (ready for enhancement)", $time, frame_count*2);

            // Frame 0特殊统计
            if (frame_count == 0) begin
                #(CLK_PERIOD*1000);  // 等待输出完成
                $display("\n========== FRAME 0 STATISTICS ==========");
                $display("Total output pixels: %0d", debug_pixel_count);
                $display("Non-zero pixels: %0d", debug_nonzero_count);
                if (debug_pixel_count > 0)
                    $display("Average out_y: %0d", debug_y_sum / debug_pixel_count);
                $display("Max out_y: %0d", debug_y_max);
                $display("=======================================\n");
            end

            #(CLK_PERIOD*100000);  // 增加帧间隔到10000周期，确保CDF完全稳定

            // 第二次输入：应用CLAHE增强（使用前一帧的CDF）
            $display("\n[%0t] --- Frame %0d: CLAHE Enhancement Applied ---", $time, frame_count*2+1);
            #(CLK_PERIOD*100);
            bmp_begin = 1;
            #(CLK_PERIOD);
            bmp_begin = 0;

            wait(bmp_in_done);
            $display("[%0t] Frame %0d input complete (enhanced output)", $time, frame_count*2+1);

            // 等待输出完成
            wait(processing == 0);
            $display("[%0t] Frame %0d processing complete", $time, frame_count*2+1);

            #(CLK_PERIOD*100000);  // 增加帧间隔到10000周期
        end

        // ====================================================================
        // 测试完成
        // ====================================================================
        #(CLK_PERIOD*100000);
        $display("\n========================================");
        $display("  Test Complete!");
        $display("========================================");
        $display("  Total Image Sets: %0d", NUM_FRAMES);
        $display("  Total Frames Processed: %0d (each image input twice)", frame_count*2);
        $display("  Output files saved to:");
        $display("    - Input:  bmp_test_results/input/");
        $display("    - Output: bmp_test_results/output/");
        $display("");
        $display("  Frame pairs (same input, progressive enhancement):");
        $display("    - input_frame 0.bmp -> output_frame 0.bmp (1st CDF)");
        $display("    - input_frame 1.bmp -> output_frame 1.bmp (using CDF from frame 0)");
        $display("    - input_frame 2.bmp -> output_frame 2.bmp (2nd CDF)");
        $display("    - input_frame 3.bmp -> output_frame 3.bmp (using CDF from frame 2)");
        $display("    - input_frame 4.bmp -> output_frame 4.bmp (3rd CDF)");
        $display("    - input_frame 5.bmp -> output_frame 5.bmp (using CDF from frame 4)");
        $display("========================================\n");

        $stop;
    end

    // // ========================================================================
    // // 监控和统计（已简化以加快仿真速度）
    // // ========================================================================

    // ========================================================================
    // 关键信号监控
    // ========================================================================

    // 连接CDF处理状态信号（必须保留，testbench依赖这些信号）
    assign processing = u_dut.cdf_processing;
    assign cdf_ready = u_dut.cdf_done;
    assign ping_pong_flag = u_dut.ping_pong_flag;

    // 关键事件监控（简化版）
    always @(posedge processing) begin
        $display("[%0t] >>> CDF Processing started (ping_pong=%0d)", $time, ping_pong_flag);
    end

    always @(negedge processing) begin
        $display("[%0t] <<< CDF Processing finished (ping_pong=%0d)", $time, ping_pong_flag);
    end

    always @(posedge cdf_ready) begin
        $display("[%0t] *** CDF Ready - CLAHE active", $time);
    end

    // 调试：统计Frame 0的输出值分布
    reg out_vsync_d1_debug;
    integer debug_in_y_sum;
    integer debug_in_y_max;

    initial begin
        debug_pixel_count = 0;
        debug_nonzero_count = 0;
        debug_y_sum = 0;
        debug_y_max = 0;
        debug_in_y_sum = 0;
        debug_in_y_max = 0;
    end

    always @(posedge pclk) begin
        out_vsync_d1_debug <= out_vsync;

        if (out_href && frame_count == 0) begin
            debug_pixel_count = debug_pixel_count + 1;
            debug_y_sum = debug_y_sum + out_y;
            debug_in_y_sum = debug_in_y_sum + in_y;
            if (out_y > debug_y_max)
                debug_y_max = out_y;
            if (in_y > debug_in_y_max)
                debug_in_y_max = in_y;
            if (out_y != 0) begin
                debug_nonzero_count = debug_nonzero_count + 1;
                // 显示前10个非零像素
                if (debug_nonzero_count <= 10) begin
                    $display("[FRAME0 NONZERO #%0d] pixel#%0d: in_y=%0d, out_y=%0d, RGB=(%0d,%0d,%0d)",
                             debug_nonzero_count, debug_pixel_count, in_y, out_y, bmp_out_r, bmp_out_g, bmp_out_b);
                end
            end
            // 显示前5个像素的in_y值
            if (debug_pixel_count <= 5) begin
                $display("[FRAME0 PIXEL#%0d] RGB=(%0d,%0d,%0d) valid=%0d in_y=%0d, out_y=%0d",
                         debug_pixel_count, bmp_in_data[2], bmp_in_data[1], bmp_in_data[0], bmp_in_valid, in_y, out_y);
            end
        end

        // Frame切换时统计
        if (frame_count == 1 && debug_pixel_count > 0) begin
            $display("\n[FRAME0 SUMMARY]");
            $display("  Total pixels: %0d", debug_pixel_count);
            $display("  Non-zero pixels: %0d", debug_nonzero_count);
            if (debug_pixel_count > 0) begin
                $display("  Avg in_y: %0d", debug_in_y_sum / debug_pixel_count);
                $display("  Avg out_y: %0d", debug_y_sum / debug_pixel_count);
            end
            $display("  Max in_y: %0d", debug_in_y_max);
            $display("  Max out_y: %0d\n", debug_y_max);
            debug_pixel_count = -1;  // 标记已输出
        end
    end

    // // ========================================================================
    // // 波形转储
    // // ========================================================================
    // initial begin
    //     $dumpfile("tb_clahe_top_bmp_multi.vcd");
    //     $dumpvars(0, tb_clahe_top_bmp_multi);
    // end

endmodule

