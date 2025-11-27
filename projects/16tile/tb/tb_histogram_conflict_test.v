// ============================================================================
// Histogram Statistics Conflict Handling Verification Test - Enhanced
//
// Test Scenarios:
//   1. Adjacent Same (AAA): Verify increment +2
//   2. Interval Conflict (ABA): Verify bypass logic
//   3. Continuous Interval (ABABAB): Verify continuous bypass
//   4. Mixed Scenario (ABAABC): Verify complex scenarios
//   5. Long Sequence Test: Random patterns with validation
//   6. Boundary Conditions: Edge cases and stress tests
//   7. Full Frame Simulation: Realistic workload
//
// Author: Passionate.Z
// Date: 2025-10-31
// ============================================================================

`timescale 1ns / 1ps

module tb_histogram_conflict_test;

    // 时钟和复位
    reg pclk;
    reg rst_n;

    // 输入信号
    reg [7:0]  in_y;
    reg        in_href;
    reg        in_vsync;
    reg [3:0]  tile_idx;

    // 乒乓控制
    reg        ping_pong_flag;

    // 清零控制
    wire       clear_start;
    reg        clear_done;

    // RAM接口
    wire [3:0] ram_rd_tile_idx;
    wire [3:0] ram_wr_tile_idx;
    wire [7:0] ram_wr_addr_a;
    wire [15:0] ram_wr_data_a;
    wire       ram_wr_en_a;
    wire [7:0] ram_rd_addr_b;
    reg [15:0] ram_rd_data_b;

    // 帧完成标志
    wire       frame_hist_done;

    // 实例化被测模块
    clahe_histogram_stat_v2 u_hist_stat (
                                .pclk               (pclk),
                                .rst_n              (rst_n),
                                .in_y               (in_y),
                                .in_href            (in_href),
                                .in_vsync           (in_vsync),
                                .tile_idx           (tile_idx),
                                .ping_pong_flag     (ping_pong_flag),
                                .clear_start        (clear_start),
                                .clear_done         (clear_done),
                                .ram_rd_tile_idx    (ram_rd_tile_idx),
                                .ram_wr_tile_idx    (ram_wr_tile_idx),
                                .ram_wr_addr_a      (ram_wr_addr_a),
                                .ram_wr_data_a      (ram_wr_data_a),
                                .ram_wr_en_a        (ram_wr_en_a),
                                .ram_rd_addr_b      (ram_rd_addr_b),
                                .ram_rd_data_b      (ram_rd_data_b),
                                .frame_hist_done    (frame_hist_done)
                            );

    // RAM模型（简化）
    reg [15:0] ram_model [0:255];

    // RAM读取模拟（1周期延迟）
    always @(posedge pclk) begin
        ram_rd_data_b <= ram_model[ram_rd_addr_b];
    end

    // RAM写入模拟
    always @(posedge pclk) begin
        if (ram_wr_en_a) begin
            ram_model[ram_wr_addr_a] <= ram_wr_data_a;
        end
    end

    // 时钟生成：100MHz
    initial begin
        pclk = 0;
        forever
            #5 pclk = ~pclk;
    end

    // Test counters
    integer error_count;
    integer test_count;
    integer i, j, k;

    // Golden reference model
    reg [15:0] golden_ram [0:255];

    // Random test variables
    reg [7:0] rand_addr;
    integer rand_seed;

    // Main test program
    initial begin
        error_count = 0;
        test_count = 0;
        rand_seed = 12345;

        $display("========================================");
        $display("Histogram Conflict Handling Test Suite");
        $display("Enhanced with Long Sequence Tests");
        $display("========================================");

        // Initialization
        rst_n = 0;
        in_y = 0;
        in_href = 0;
        in_vsync = 0;
        tile_idx = 0;
        ping_pong_flag = 0;
        clear_done = 1;

        // Clear RAM and golden model
        for (i = 0; i < 256; i = i + 1) begin
            ram_model[i] = 0;
            golden_ram[i] = 0;
        end

        // Reset sequence
        repeat(10) @(posedge pclk);
        rst_n = 1;
        repeat(5) @(posedge pclk);

        // Start testing
        in_vsync = 1;
        @(posedge pclk);

        // ====================================================================
        // Test 1: Adjacent Same (AAA) - Verify increment +2
        // ====================================================================
        $display("\n[Test 1] Adjacent Same Pattern (AAA)");
        $display("Expected: RAM[100] = 0+2 = 2 (first and second A write +2)");

        ram_model[100] = 0;  // Initial value

        send_pixel(100, 0);  // A(1)
        send_pixel(100, 0);  // A(2) - Adjacent same, increment +2

        // Flush pipeline by ending href
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        test_count = test_count + 1;
        if (ram_model[100] == 2) begin
            $display("[PASS] Test 1: RAM[100] = %0d (expected 2)", ram_model[100]);
        end
        else begin
            $display("[FAIL] Test 1: RAM[100] = %0d (expected 2)", ram_model[100]);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test 2: Interval Conflict (ABA) - Verify bypass logic
        // ====================================================================
        $display("\n[Test 2] Interval Conflict Pattern (ABA)");
        $display("Expected: RAM[50] = 5+1+1 = 7 (bypass returns new value 6, then +1)");

        ram_model[50] = 5;   // Initial value
        ram_model[60] = 10;  // Initial value

        send_pixel(50, 0);   // A(1) - Read RAM[50]=5, write RAM[50]=6
        send_pixel(60, 0);   // B - Read RAM[60]=10, write RAM[60]=11
        send_pixel(50, 0);   // A(2) - Read RAM[50], should get 6 via bypass, write RAM[50]=7

        // Flush pipeline by ending href
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        test_count = test_count + 1;
        if (ram_model[50] == 7) begin
            $display("[PASS] Test 2: RAM[50] = %0d (expected 7)", ram_model[50]);
        end
        else begin
            $display("[FAIL] Test 2: RAM[50] = %0d (expected 7)", ram_model[50]);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test 3: Continuous Interval (ABABAB) - Verify continuous bypass
        // ====================================================================
        $display("\n[Test 3] Continuous Interval Pattern (ABABAB)");
        $display("Expected: RAM[80] = 15+3 = 18, RAM[90] = 20+3 = 23");

        ram_model[80] = 15;  // Initial value
        ram_model[90] = 20;  // Initial value

        send_pixel(80, 0);   // A(1) - Write RAM[80]=16
        send_pixel(90, 0);   // B(1) - Write RAM[90]=21
        send_pixel(80, 0);   // A(2) - Bypass gets 16, write RAM[80]=17
        send_pixel(90, 0);   // B(2) - Bypass gets 21, write RAM[90]=22
        send_pixel(80, 0);   // A(3) - Bypass gets 17, write RAM[80]=18
        send_pixel(90, 0);   // B(3) - Bypass gets 22, write RAM[90]=23

        // Flush pipeline by ending href
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        test_count = test_count + 2;
        if (ram_model[80] == 18) begin
            $display("[PASS] Test 3a: RAM[80] = %0d (expected 18)", ram_model[80]);
        end
        else begin
            $display("[FAIL] Test 3a: RAM[80] = %0d (expected 18)", ram_model[80]);
            error_count = error_count + 1;
        end

        if (ram_model[90] == 23) begin
            $display("[PASS] Test 3b: RAM[90] = %0d (expected 23)", ram_model[90]);
        end
        else begin
            $display("[FAIL] Test 3b: RAM[90] = %0d (expected 23)", ram_model[90]);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test 4: Mixed Scenario (AAB + ABA)
        // ====================================================================
        $display("\n[Test 4] Mixed Pattern (AABABA)");
        $display("Expected: RAM[120] = 30+4 = 34, RAM[130] = 40+2 = 42");

        ram_model[120] = 30;  // Initial value
        ram_model[130] = 40;  // Initial value

        send_pixel(120, 0);   // A(1)
        send_pixel(120, 0);   // A(2) - Adjacent, increment +2
        send_pixel(130, 0);   // B(1) - Write RAM[120]=32
        send_pixel(120, 0);   // A(3) - Bypass gets 32, write RAM[120]=33
        send_pixel(130, 0);   // B(2) - Adjacent, increment +2
        send_pixel(120, 0);   // A(4) - Bypass gets 33, write RAM[120]=34

        // Flush pipeline by ending href
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        test_count = test_count + 2;
        if (ram_model[120] == 34) begin
            $display("[PASS] Test 4a: RAM[120] = %0d (expected 34)", ram_model[120]);
        end
        else begin
            $display("[FAIL] Test 4a: RAM[120] = %0d (expected 34)", ram_model[120]);
            error_count = error_count + 1;
        end

        if (ram_model[130] == 42) begin
            $display("[PASS] Test 4b: RAM[130] = %0d (expected 42)", ram_model[130]);
        end
        else begin
            $display("[FAIL] Test 4b: RAM[130] = %0d (expected 42)", ram_model[130]);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test 5: Long Sequence Test - Random Pattern (100 pixels)
        // ====================================================================
        $display("\n[Test 5] Long Sequence Random Pattern Test (100 pixels)");
        $display("Testing random access patterns with validation");

        // Restart with new frame to ensure clean state
        in_vsync = 0;
        repeat(5) @(posedge pclk);
        in_vsync = 1;
        repeat(5) @(posedge pclk);

        // Clear RAM for this test
        for (i = 0; i < 256; i = i + 1) begin
            ram_model[i] = 0;
            golden_ram[i] = 0;
        end

        // Generate 100 random pixels (use only 0-63 range to keep test clean)
        for (i = 0; i < 100; i = i + 1) begin
            j = $random(rand_seed);
            rand_addr = ((j < 0) ? -j : j) % 64;  // Use absolute value then mod 64
            send_pixel(rand_addr, 0);
            golden_ram[rand_addr] = golden_ram[rand_addr] + 1;
        end

        // Flush pipeline by ending href (no more pixels)
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        // Verify results
        test_count = test_count + 1;
        k = 0;
        for (i = 0; i < 256; i = i + 1) begin
            if (ram_model[i] != golden_ram[i]) begin
                if (k < 5) begin  // Only show first 5 errors
                    $display("  Mismatch at addr %0d: RAM=%0d, Expected=%0d",
                             i, ram_model[i], golden_ram[i]);
                end
                k = k + 1;
            end
        end

        if (k == 0) begin
            $display("[PASS] Test 5: All 100 random pixels processed correctly");
        end
        else begin
            $display("[FAIL] Test 5: %0d addresses have mismatches", k);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test 6: Boundary Conditions - All Same Address
        // ====================================================================
        $display("\n[Test 6] Boundary Test - 50 Consecutive Same Address");

        // Clear RAM
        for (i = 0; i < 256; i = i + 1) begin
            ram_model[i] = 0;
        end

        // Send 50 pixels to address 128
        for (i = 0; i < 50; i = i + 1) begin
            send_pixel(128, 0);
        end

        // Flush pipeline by ending href
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        test_count = test_count + 1;
        if (ram_model[128] == 50) begin
            $display("[PASS] Test 6: RAM[128] = %0d (expected 50)", ram_model[128]);
        end
        else begin
            $display("[FAIL] Test 6: RAM[128] = %0d (expected 50)", ram_model[128]);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test 7: Alternating Pattern Stress Test (200 pixels)
        // ====================================================================
        $display("\n[Test 7] Stress Test - Alternating Pattern (200 pixels)");

        // Clear RAM
        for (i = 0; i < 256; i = i + 1) begin
            ram_model[i] = 0;
        end

        // Alternating between 4 addresses: 10, 20, 30, 40
        for (i = 0; i < 200; i = i + 1) begin
            case (i % 4)
                0:
                    send_pixel(10, 0);
                1:
                    send_pixel(20, 0);
                2:
                    send_pixel(30, 0);
                3:
                    send_pixel(40, 0);
            endcase
        end

        // Flush pipeline by ending href
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        test_count = test_count + 4;
        if (ram_model[10] == 50) begin
            $display("[PASS] Test 7a: RAM[10] = %0d (expected 50)", ram_model[10]);
        end
        else begin
            $display("[FAIL] Test 7a: RAM[10] = %0d (expected 50)", ram_model[10]);
            error_count = error_count + 1;
        end

        if (ram_model[20] == 50) begin
            $display("[PASS] Test 7b: RAM[20] = %0d (expected 50)", ram_model[20]);
        end
        else begin
            $display("[FAIL] Test 7b: RAM[20] = %0d (expected 50)", ram_model[20]);
            error_count = error_count + 1;
        end

        if (ram_model[30] == 50) begin
            $display("[PASS] Test 7c: RAM[30] = %0d (expected 50)", ram_model[30]);
        end
        else begin
            $display("[FAIL] Test 7c: RAM[30] = %0d (expected 50)", ram_model[30]);
            error_count = error_count + 1;
        end

        if (ram_model[40] == 50) begin
            $display("[PASS] Test 7d: RAM[40] = %0d (expected 50)", ram_model[40]);
        end
        else begin
            $display("[FAIL] Test 7d: RAM[40] = %0d (expected 50)", ram_model[40]);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test 8: Sequential Address Pattern (256 pixels)
        // ====================================================================
        $display("\n[Test 8] Sequential Address Pattern (all 256 addresses)");

        // Clear RAM
        for (i = 0; i < 256; i = i + 1) begin
            ram_model[i] = 0;
        end

        // Send one pixel to each address
        for (i = 0; i < 256; i = i + 1) begin
            send_pixel(i[7:0], 0);
        end

        // Flush pipeline by ending href
        @(posedge pclk);
        in_href = 0;
        repeat(10) @(posedge pclk);

        test_count = test_count + 1;
        k = 0;
        for (i = 0; i < 256; i = i + 1) begin
            if (ram_model[i] != 1) begin
                k = k + 1;
            end
        end

        if (k == 0) begin
            $display("[PASS] Test 8: All 256 addresses = 1");
        end
        else begin
            $display("[FAIL] Test 8: %0d addresses do not equal 1", k);
            error_count = error_count + 1;
        end

        // ====================================================================
        // Test Summary
        // ====================================================================
        $display("\n========================================");
        $display("Test Completed!");
        $display("Total Tests: %0d", test_count);
        $display("Failed Tests: %0d", error_count);
        if (error_count == 0) begin
            $display("Result: ALL TESTS PASSED!");
        end
        else begin
            $display("Result: %0d TEST(S) FAILED", error_count);
        end
        $display("========================================");

        repeat(20) @(posedge pclk);
        $finish;
    end

    // 发送像素任务
    task send_pixel(input [7:0] pixel, input [3:0] tile);
        begin
            @(posedge pclk);
            in_href = 1;
            in_y = pixel;
            tile_idx = tile;
        end
    endtask

    // Waveform monitoring
    initial begin
        $display("\nTime | href | in_y | s1   | s2   | s3   | conflict | bypass_valid | RAM_RdAddr | RAM_WrEn | RAM_WrAddr | RAM_WrData |");
        $display("-----|------|------|------|------|------|----------|--------------|------------|----------|------------|------------|");
    end

    always @(posedge pclk) begin
        if (in_href || ram_wr_en_a) begin
            //             $display("%4t | %1b    | %3d  | %3d  | %3d  | %3d  | %1b        | %1b            | %3d      | %1b        | %3d      | %5d    |"
            // ,
            //                      $time,
            //                      in_href,
            //                      in_y,
            //                      u_hist_stat.pixel_s1,
            //                      u_hist_stat.pixel_s2,
            //                      u_hist_stat.pixel_s3,
            //                      u_hist_stat.conflict,
            //                      u_hist_stat.bypass_valid,
            //                      ram_rd_addr_b,
            //                      ram_wr_en_a,
            //                      ram_wr_addr_a,
            //                      ram_wr_data_a
            //                     );
        end
    end

    // Generate waveform file (uncomment if needed)
    // initial begin
    //     $dumpfile("tb_histogram_conflict_test.vcd");
    //     $dumpvars(0, tb_histogram_conflict_test);
    // end

endmodule

