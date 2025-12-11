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
// Testbench for CLAHE Coordinate Counter and Tile Positioning Module
//
// Test Items:
//   1. Basic coordinate counting functionality
//   2. Tile index calculation correctness
//   3. Relative coordinate calculation within tiles
//   4. Boundary condition testing
//
// Simulation Description:
//   - Simulate 1280x720 image pixel stream
//   - Verify 8x8 tiling tile indices
//   - Check coordinate switching at tile boundaries
//
// Author: Passionate.Z
// Date: 2025-10-15
// ============================================================================

`timescale 1ns/1ps

module tb_clahe_coord_counter;

    // ========================================================================
    // Parameter Definition
    // ========================================================================
    parameter WIDTH = 1280;
    parameter HEIGHT = 720;
    parameter CLK_PERIOD = 13.5;  // 74.25MHz clock period

    // ========================================================================
    // Signal Definition
    // ========================================================================
    reg         pclk;
    reg         rst_n;
    reg         in_href;
    reg         in_vsync;

    wire [10:0] x_cnt;
    wire [9:0]  y_cnt;
    wire [2:0]  tile_x;
    wire [2:0]  tile_y;
    wire [5:0]  tile_idx;
    wire [7:0]  local_x;
    wire [6:0]  local_y;

    // Test counters
    integer pixel_count;
    integer line_count;
    integer frame_count;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    clahe_coord_counter #(
                            .WIDTH(WIDTH),
                            .HEIGHT(HEIGHT),
                            .TILE_H_NUM(8),
                            .TILE_V_NUM(8)
                        ) u_dut (
                            .pclk(pclk),
                            .rst_n(rst_n),
                            .in_href(in_href),
                            .in_vsync(in_vsync),
                            .x_cnt(x_cnt),
                            .y_cnt(y_cnt),
                            .tile_x(tile_x),
                            .tile_y(tile_y),
                            .tile_idx(tile_idx),
                            .local_x(local_x),
                            .local_y(local_y)
                        );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        pclk = 0;
        forever
            #(CLK_PERIOD/2) pclk = ~pclk;
    end

    // ========================================================================
    // Reset Sequence
    // ========================================================================
    initial begin
        rst_n = 0;
        #(CLK_PERIOD*10);
        rst_n = 1;
        $display("[%0t] Reset released", $time);
    end

    // ========================================================================
    // Test Stimulus
    // ========================================================================
    initial begin
        in_href = 0;
        in_vsync = 0;
        pixel_count = 0;
        line_count = 0;
        frame_count = 0;

        // Wait for reset completion
        wait(rst_n == 1);
        #(CLK_PERIOD*5);

        // Generate 2 frames
        repeat(2) begin
            gen_one_frame();
            frame_count = frame_count + 1;
            #(CLK_PERIOD*100);  // Frame gap
        end

        #(CLK_PERIOD*100);
        $display("[%0t] Simulation completed successfully!", $time);
        $stop;
    end

    // ========================================================================
    // Generate One Frame
    // ========================================================================
    task gen_one_frame;
        integer x, y;
        begin
            $display("[%0t] Generating frame %0d", $time, frame_count);

            // vsync rising edge
            @(posedge pclk);
            in_vsync = 1;

            // Generate 720 lines
            for (y = 0; y < HEIGHT; y = y + 1) begin
                // Line blanking
                repeat(10) @(posedge pclk);

                // href rising edge
                @(posedge pclk);
                in_href = 1;

                // Generate 1280 pixels
                for (x = 0; x < WIDTH; x = x + 1) begin
                    @(posedge pclk);
                    pixel_count = pixel_count + 1;

                    // Key point verification
                    if (x == 0 && y == 0) begin
                        check_coord(0, 0, 0, 0, 0, 0, 0, "First pixel");
                    end
                    else if (x == 159 && y == 0) begin
                        check_coord(159, 0, 0, 0, 0, 159, 0, "Tile boundary X");
                    end
                    else if (x == 160 && y == 0) begin
                        check_coord(160, 0, 1, 0, 1, 0, 0, "Next tile X");
                    end
                    else if (x == 0 && y == 89) begin
                        check_coord(0, 89, 0, 0, 0, 0, 89, "Tile boundary Y");
                    end
                    else if (x == 0 && y == 90) begin
                        check_coord(0, 90, 0, 1, 8, 0, 0, "Next tile Y");
                    end
                    else if (x == 1279 && y == 719) begin
                        check_coord(1279, 719, 7, 7, 63, 159, 89, "Last pixel");
                    end
                end

                // href falling edge
                // @(posedge pclk);
                in_href = 0;
                line_count = line_count + 1;
            end

            // vsync falling edge
            @(posedge pclk);
            in_vsync = 0;

            $display("[%0t] Frame %0d completed, %0d pixels, %0d lines",
                     $time, frame_count, pixel_count, line_count);
        end
    endtask

    // ========================================================================
    // Coordinate Check Task
    // ========================================================================
    task check_coord;
        input [10:0] exp_x;
        input [9:0]  exp_y;
        input [2:0]  exp_tile_x;
        input [2:0]  exp_tile_y;
        input [5:0]  exp_tile_idx;
        input [7:0]  exp_local_x;
        input [6:0]  exp_local_y;
        input [128*8:1] description;
        begin
            if (x_cnt !== exp_x || y_cnt !== exp_y ||
                    tile_x !== exp_tile_x || tile_y !== exp_tile_y ||
                    tile_idx !== exp_tile_idx ||
                    local_x !== exp_local_x || local_y !== exp_local_y) begin

                $display("[ERROR] %0s", description);
                $display("  Expected: x=%0d, y=%0d, tile_x=%0d, tile_y=%0d, tile_idx=%0d, local_x=%0d, local_y=%0d",
                         exp_x, exp_y, exp_tile_x, exp_tile_y, exp_tile_idx, exp_local_x, exp_local_y);
                $display("  Got:      x=%0d, y=%0d, tile_x=%0d, tile_y=%0d, tile_idx=%0d, local_x=%0d, local_y=%0d",
                         x_cnt, y_cnt, tile_x, tile_y, tile_idx, local_x, local_y);
                $stop;
            end
            else begin
                $display("[PASS] %0s @ (%0d,%0d) -> Tile[%0d,%0d]=%0d, Local(%0d,%0d)",
                         description, exp_x, exp_y, exp_tile_x, exp_tile_y, exp_tile_idx, exp_local_x, exp_local_y);
            end
        end
    endtask

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_clahe_coord_counter.vcd");
        $dumpvars(0, tb_clahe_coord_counter);
    end

endmodule



