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
// Testbench for CLAHE像素映射模块（标准插值版本）
//
// 测试项目:
//   1. Bypass模式测试 - CLAHE禁用时直通输出
//   2. CLAHE映射模式测试 - 单tile CDF映射
//   3. 多tile映射测试 - 不同tile的CDF映射
//   4. 插值模式测试 - 四tile双线性插值
//   5. U/V通道延迟匹配测试 - 8级流水线延迟验证
//
// 流水线说明:
//   - mapping模块有9级流水线
//   - 总延迟为9个时钟周期
//   - U/V通道自动延迟匹配
//
// 作者: Passionate.Z
// 日期: 2025-10-18
// ============================================================================

`timescale 1ns/1ps

module tb_clahe_mapping;

    // ========================================================================
    // 参数定义
    // ========================================================================
    parameter CLK_PERIOD = 13.5;
    parameter WIDTH = 1280;
    parameter HEIGHT = 720;

    // ========================================================================
    // 信号定义
    // ========================================================================
    reg         pclk;
    reg         rst_n;
    reg         in_href;
    reg         in_vsync;
    reg  [7:0]  in_y;
    reg  [7:0]  in_u;
    reg  [7:0]  in_v;
    reg  [5:0]  tile_idx;
    reg         clahe_enable;
    reg         interp_enable;
    reg         cdf_ready;
    reg  [10:0] pixel_x;
    reg  [9:0]  pixel_y;

    wire [5:0]  cdf_rd_tile_idx;
    wire [7:0]  cdf_rd_bin_addr;
    reg  [15:0] cdf_rd_data;
    wire [1:0]  read_stage_out;

    wire        out_href;
    wire        out_vsync;
    wire [7:0]  out_y;
    wire [7:0]  out_u;
    wire [7:0]  out_v;

    // CDF LUT模拟
    reg  [7:0]  cdf_lut [0:16383];

    integer x, y, i;

    // ========================================================================
    // DUT实例化
    // ========================================================================
    clahe_mapping u_dut (
                      .pclk(pclk),
                      .rst_n(rst_n),
                      .in_href(in_href),
                      .in_vsync(in_vsync),
                      .in_y(in_y),
                      .in_u(in_u),
                      .in_v(in_v),
                      .tile_idx(tile_idx),
                      .pixel_x(pixel_x),
                      .pixel_y(pixel_y),
                      .clahe_enable(clahe_enable),
                      .interp_enable(interp_enable),
                      .cdf_ready(cdf_ready),
                      .cdf_rd_tile_idx(cdf_rd_tile_idx),
                      .cdf_rd_bin_addr(cdf_rd_bin_addr),
                      .cdf_rd_data(cdf_rd_data),
                      .read_stage_out(read_stage_out),
                      .out_href(out_href),
                      .out_vsync(out_vsync),
                      .out_y(out_y),
                      .out_u(out_u),
                      .out_v(out_v)
                  );

    // ========================================================================
    // 时钟生成
    // ========================================================================
    initial begin
        pclk = 0;
        forever
            #(CLK_PERIOD/2) pclk = ~pclk;
    end

    // ========================================================================
    // CDF LUT模拟读取（64块RAM架构）
    // ========================================================================
    always @(posedge pclk) begin
        cdf_rd_data <= {8'd0, cdf_lut[{cdf_rd_tile_idx, cdf_rd_bin_addr}]};
    end

    // ========================================================================
    // 测试激励
    // ========================================================================
    initial begin
        // 初始化
        rst_n = 0;
        in_href = 0;
        in_vsync = 0;
        in_y = 0;
        in_u = 128;
        in_v = 128;
        tile_idx = 0;
        pixel_x = 0;
        pixel_y = 0;
        clahe_enable = 0;
        interp_enable = 0;
        cdf_ready = 0;

        // 初始化CDF LUT（简单映射：增强对比度）
        for (i = 0; i < 16384; i = i + 1) begin
            // 默认映射：y_out = (y_in * 1.2) 限制到255
            cdf_lut[i] = (i[7:0] * 12 / 10 > 255) ? 8'd255 : (i[7:0] * 12 / 10);
        end

        // 复位
        #(CLK_PERIOD*10);
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        #(CLK_PERIOD*5);

        // ====================================================================
        // 测试1: Bypass模式（CLAHE禁用）
        // ====================================================================
        $display("\n[TEST 1] Bypass mode (CLAHE disabled)");
        clahe_enable = 0;
        cdf_ready = 0;

        gen_test_frame(8'd100, 8'd80, 8'd90);  // Y=100, U=80, V=90

        #(CLK_PERIOD*100);
        $display("[INFO] Bypass mode test completed");

        // ====================================================================
        // 测试2: CLAHE映射模式
        // ====================================================================
        $display("\n[TEST 2] CLAHE mapping mode");
        clahe_enable = 1;
        cdf_ready = 1;

        gen_test_frame(8'd50, 8'd100, 8'd120);  // 低亮度输入

        #(CLK_PERIOD*100);
        $display("[INFO] CLAHE mapping mode test completed");

        // ====================================================================
        // 测试3: 不同tile的映射
        // ====================================================================
        $display("\n[TEST 3] Different tile mapping");

        // 为不同tile设置不同的CDF映射
        for (i = 0; i < 256; i = i + 1) begin
            cdf_lut[0*256 + i] = i;              // tile 0: 线性映射
            cdf_lut[1*256 + i] = (i > 127) ? 255 : 0;  // tile 1: 二值化
            cdf_lut[2*256 + i] = 255 - i;        // tile 2: 反转
        end

        gen_multi_tile_frame();

        #(CLK_PERIOD*100);
        $display("[INFO] Multi-tile mapping test completed");

        // ====================================================================
        // 测试4: 插值模式测试（功能性测试）
        // ====================================================================
        $display("\n[TEST 4] Interpolation mode test (functional)");
        clahe_enable = 1;
        interp_enable = 1;
        cdf_ready = 1;

        gen_interp_test_frame();

        #(CLK_PERIOD*100);
        $display("[INFO] Interpolation mode test completed");

        // ====================================================================
        // 测试5: 插值计算正确性验证（精确验证）
        // ====================================================================
        $display("\n[TEST 5] Interpolation calculation correctness");

        // 复位以清除之前测试的CDF缓存
        rst_n = 0;
        #(CLK_PERIOD*5);
        rst_n = 1;
        #(CLK_PERIOD*5);

        verify_interp_calculation();

        #(CLK_PERIOD*100);
        $display("[INFO] Interpolation calculation verification completed");

        // ====================================================================
        // 测试6: U/V通道延迟验证
        // ====================================================================
        $display("\n[TEST 6] U/V channel delay matching");
        verify_uv_delay();

        #(CLK_PERIOD*100);
        $display("\n[%0t] All tests completed!", $time);
        $stop;
    end

    // ========================================================================
    // 生成测试帧任务
    // ========================================================================
    task gen_test_frame;
        input [7:0] y_val;
        input [7:0] u_val;
        input [7:0] v_val;
        begin
            $display("[%0t] Generating frame: Y=%0d, U=%0d, V=%0d", $time, y_val, u_val, v_val);

            @(posedge pclk);
            in_vsync = 1;

            // 只生成几行用于测试
            for (y = 0; y < 10; y = y + 1) begin
                tile_idx = 0;  // 使用tile 0

                @(posedge pclk);
                in_href = 1;

                for (x = 0; x < 100; x = x + 1) begin
                    in_y = y_val;
                    in_u = u_val;
                    in_v = v_val;
                    @(posedge pclk);
                end

                in_href = 0;
                @(posedge pclk);
            end

            in_vsync = 0;
            @(posedge pclk);
        end
    endtask

    // ========================================================================
    // 生成插值测试帧
    // ========================================================================
    task gen_interp_test_frame;
        begin
            $display("[%0t] Generating interpolation test frame", $time);

            @(posedge pclk);
            in_vsync = 1;

            for (y = 0; y < 20; y = y + 1) begin
                @(posedge pclk);
                in_href = 1;

                for (x = 0; x < 320; x = x + 1) begin
                    // 计算像素坐标
                    pixel_x = x;
                    pixel_y = y;

                    // 根据位置确定tile
                    tile_idx = (y / 90) * 8 + (x / 160);

                    // 测试不同位置的像素
                    if (x < 80) begin
                        in_y = 8'd50;   // 低亮度
                    end
                    else if (x < 160) begin
                        in_y = 8'd128;  // 中等亮度
                    end
                    else if (x < 240) begin
                        in_y = 8'd200;  // 高亮度
                    end
                    else begin
                        in_y = 8'd100;  // 混合亮度
                    end

                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
                @(posedge pclk);
            end

            in_vsync = 0;
        end
    endtask

    // ========================================================================
    // 生成多tile测试帧
    // ========================================================================
    task gen_multi_tile_frame;
        begin
            $display("[%0t] Generating multi-tile frame", $time);

            @(posedge pclk);
            in_vsync = 1;

            for (y = 0; y < 30; y = y + 1) begin
                @(posedge pclk);
                in_href = 1;

                for (x = 0; x < 480; x = x + 1) begin
                    // 根据x位置确定tile_idx
                    if (x < 160)
                        tile_idx = 0;
                    else if (x < 320)
                        tile_idx = 1;
                    else
                        tile_idx = 2;

                    in_y = 8'd128;  // 中间灰度
                    in_u = 8'd128;
                    in_v = 8'd128;
                    @(posedge pclk);
                end

                in_href = 0;
                @(posedge pclk);
            end

            in_vsync = 0;
        end
    endtask

    // ========================================================================
    // 验证插值计算正确性
    // ========================================================================
    task verify_interp_calculation;
        reg [7:0] test_y;
        reg [7:0] cdf_tl_val, cdf_tr_val, cdf_bl_val, cdf_br_val;
        reg [10:0] test_x;
        reg [9:0] test_y_coord;
        integer local_x, local_y;
        integer wx_calc, wy_calc;
        integer interp_result_expected;
        integer tile_x_pos, tile_y_pos;
        integer error_margin;
        begin
            $display("[%0t] Verifying interpolation calculation correctness", $time);

            // 设置已知的CDF映射值
            // 为了简化验证，设置4个相邻tile的特定CDF值
            // 像素在tile(1,1)，4个相邻tile为：
            //   TL: tile(0,0) = 0
            //   TR: tile(1,0) = 1
            //   BL: tile(0,1) = 8
            //   BR: tile(1,1) = 9
            cdf_lut[0*256 + 100] = 8'd50;   // tile_tl (0,0)的CDF
            cdf_lut[1*256 + 100] = 8'd150;  // tile_tr (1,0)的CDF
            cdf_lut[8*256 + 100] = 8'd50;   // tile_bl (0,1)的CDF
            cdf_lut[9*256 + 100] = 8'd150;  // tile_br (1,1)的CDF

            // 测试用例：在tile边界附近的像素（非边界tile）
            // 位置: x=200 (在tile 1和2之间), y=100 (在tile 1内)
            test_x = 11'd200;       // 200像素位置
            test_y_coord = 10'd100; // 第100行（tile 1）
            test_y = 8'd100;        // Y亮度值=100

            // 计算期望的插值结果
            // tile_x = 200 / 160 = 1, local_x = 200 - 160 = 40
            // tile_y = 100 / 90 = 1, local_y = 100 - 90 = 10
            tile_x_pos = 1;
            tile_y_pos = 1;
            local_x = 40;
            local_y = 10;

            // 计算插值权重 (Q8格式)
            // 标准CLAHE权重公式：
            // wx = (local_x * 256) / TILE_WIDTH
            // wy = (local_y * 256) / TILE_HEIGHT
            wx_calc = (local_x * 256) / 160;  // local_x=40 → wx = 64
            wy_calc = (local_y * 256) / 90;   // local_y=10 → wy = 28

            // 双线性插值计算
            // result = (cdf_tl * (256-wx) * (256-wy) +
            //           cdf_tr * wx * (256-wy) +
            //           cdf_bl * (256-wx) * wy +
            //           cdf_br * wx * wy) / 65536
            cdf_tl_val = 8'd50;
            cdf_tr_val = 8'd150;
            cdf_bl_val = 8'd50;
            cdf_br_val = 8'd150;

            interp_result_expected = (cdf_tl_val * (256-wx_calc) * (256-wy_calc) +
                                      cdf_tr_val * wx_calc * (256-wy_calc) +
                                      cdf_bl_val * (256-wx_calc) * wy_calc +
                                      cdf_br_val * wx_calc * wy_calc) / 65536;

            $display("  Test configuration:");
            $display("    Position: (%0d, %0d)", test_x, test_y_coord);
            $display("    Input Y: %0d", test_y);
            $display("    Tile position: (%0d, %0d)", tile_x_pos, tile_y_pos);
            $display("    Local position: (%0d, %0d)", local_x, local_y);
            $display("    Weights: wx=%0d/256, wy=%0d/256", wx_calc, wy_calc);
            $display("    CDF values: TL=%0d, TR=%0d, BL=%0d, BR=%0d",
                     cdf_tl_val, cdf_tr_val, cdf_bl_val, cdf_br_val);
            $display("    Expected interpolated result: %0d", interp_result_expected);

            // 发送测试数据前先停止输入
            @(posedge pclk);
            in_vsync = 0;
            in_href = 0;
            clahe_enable = 1;  // 保持CLAHE使能
            interp_enable = 1;  // 保持插值使能
            cdf_ready = 1;      // 保持CDF就绪
            repeat(15) @(posedge pclk);  // 等待流水线清空

            // 开始测试 - 发送连续的像素以支持插值模式的read_stage循环
            @(posedge pclk);
            in_vsync = 1;
            in_href = 1;

            // 发送至少4个像素，让read_stage完整循环0-1-2-3
            // 第1个像素：测试目标像素
            pixel_x = test_x;
            pixel_y = test_y_coord;
            tile_idx = 6'd9;  // 设置tile索引为9 (1,1)
            in_y = test_y;
            in_u = 8'd128;
            in_v = 8'd128;
            @(posedge pclk);

            // 第2个像素
            pixel_x = test_x;
            pixel_y = test_y_coord;
            in_y = test_y;
            @(posedge pclk);

            // 第3个像素
            pixel_x = test_x;
            pixel_y = test_y_coord;
            in_y = test_y;
            @(posedge pclk);

            // 第4个像素
            pixel_x = test_x;
            pixel_y = test_y_coord;
            in_y = test_y;
            @(posedge pclk);

            // 等待流水线延迟（9级流水线）
            // 第1个像素在输入后需要9个周期到达输出
            repeat(9) @(posedge pclk);

            // 验证第1个像素的输出结果（允许±2的误差，因为定点运算的舍入）
            error_margin = 2;
            if ((out_y >= (interp_result_expected - error_margin)) &&
                    (out_y <= (interp_result_expected + error_margin))) begin
                $display("[PASS] Interpolation calculation correct!");
                $display("  Expected: %0d", interp_result_expected);
                $display("  Got: %0d", out_y);
                $display("  Error: %0d (within margin: ±%0d)",
                         $signed(out_y - interp_result_expected), error_margin);
            end
            else begin
                $display("[FAIL] Interpolation calculation mismatch!");
                $display("  Expected: %0d (±%0d)", interp_result_expected, error_margin);
                $display("  Got: %0d", out_y);
                $display("  Error: %0d", $signed(out_y - interp_result_expected));
                $display("  Note: Check bilinear interpolation formula");
            end

            in_href = 0;
            in_vsync = 0;
        end
    endtask

    // ========================================================================
    // 验证U/V延迟匹配
    // ========================================================================
    // 说明：mapping模块有9级流水线，所以需要等待10个周期（9级+1）
    task verify_uv_delay;
        reg [7:0] expected_u, expected_v;
        integer delay_cnt;
        begin
            $display("[%0t] Verifying U/V delay matching (9-stage pipeline)", $time);

            delay_cnt = 0;
            expected_u = 8'd200;
            expected_v = 8'd210;

            @(posedge pclk);
            in_vsync = 1;
            in_href = 1;
            tile_idx = 0;
            pixel_x = 11'd100;  // 设置像素坐标
            pixel_y = 10'd50;

            // 输入特定的U/V值
            in_y = 8'd100;
            in_u = expected_u;
            in_v = expected_v;
            @(posedge pclk);

            // 等待流水线延迟：9级流水线需要等待10个周期
            // Stage 1-9 + 1个输出周期 = 10个周期
            repeat(10) @(posedge pclk);

            // 检查输出的U/V是否匹配
            if (out_u == expected_u && out_v == expected_v) begin
                $display("[PASS] U/V channels correctly delayed (10 cycles)");
                $display("  Input: U=%0d, V=%0d", expected_u, expected_v);
                $display("  Output: U=%0d, V=%0d", out_u, out_v);
                $display("  Pipeline delay verified: 9 stages");
            end
            else begin
                $display("[FAIL] U/V delay mismatch");
                $display("  Expected: U=%0d, V=%0d", expected_u, expected_v);
                $display("  Got: U=%0d, V=%0d", out_u, out_v);
                $display("  Note: This may indicate incorrect pipeline delay");
            end

            in_href = 0;
            in_vsync = 0;
        end
    endtask

    // ========================================================================
    // 监控输出
    // ========================================================================
    reg [7:0] y_prev;

    always @(posedge pclk) begin
        if (out_href && out_y != y_prev) begin
            if (clahe_enable && cdf_ready) begin
                // CLAHE模式：输出应该是映射后的值
                if (out_y != in_y) begin
                    // $display("[%0t] Y mapped: %0d -> %0d", $time, in_y, out_y);
                end
            end
            else begin
                // Bypass模式：输出应该等于输入
                if (out_y != in_y) begin
                    $display("[WARNING] Bypass mode but Y changed: %0d -> %0d", in_y, out_y);
                end
            end
            y_prev = out_y;
        end
    end

    // ========================================================================
    // 波形转储
    // ========================================================================
    initial begin
        $dumpfile("tb_clahe_mapping.vcd");
        $dumpvars(0, tb_clahe_mapping);
    end

endmodule
