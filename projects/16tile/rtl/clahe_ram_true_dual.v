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
// 真双端口RAM模型 - 用于CLAHE仿真
//
// 功能描述:
//   - 真双端口RAM，支持同时读写不同地址
//   - Port A: 写端口，用于清零和直方图统计写入
//   - Port B: 读端口，用于直方图统计读取
//   - 支持256深度 × 16bit宽度
//   - 用于测试64块RAM架构
//
// 接口说明:
//   - clka/clkb: 时钟信号
//   - wea: Port A写使能
//   - addra: Port A地址
//   - dina: Port A写数据
//   - douta: Port A读数据（可选）
//   - web: Port B写使能（通常为0）
//   - addrb: Port B地址
//   - dinb: Port B写数据（通常为0）
//   - doutb: Port B读数据
//
// 作者: Passionate.Z
// 日期: 2025-01-17
// ============================================================================

`timescale 1ns / 1ps

module clahe_tile_ram_true_dual (
        // Port A (写端口)
        input  wire        clka,
        input  wire        wea,
        input  wire [7:0]  addra,      // 256个bin
        input  wire [15:0] dina,
        output reg  [15:0] douta,

        // Port B (读端口)
        input  wire        clkb,
        input  wire        web,
        input  wire [7:0]  addrb,      // 256个bin
        input  wire [15:0] dinb,
        output reg  [15:0] doutb
    );

    // RAM存储
    reg [15:0] ram [0:255];

    // Port A操作
    always @(posedge clka) begin
        if (wea) begin
            ram[addra] <= dina;
        end
        douta <= ram[addra];  // Port A读操作
    end

    // Port B操作
    always @(posedge clkb) begin
        if (web) begin
            ram[addrb] <= dinb;
        end
        doutb <= ram[addrb];  // Port B读操作
    end

endmodule

// ============================================================================
// 64块真双端口RAM集成模块 - 用于CLAHE仿真
//
// 功能描述:
//   - 集成64块真双端口RAM
//   - 每块RAM对应一个tile
//   - 支持乒乓操作和清零控制
//   - 用于测试完整的CLAHE系统
//
// 作者: Passionate.Z
// 日期: 2025-01-17
// ============================================================================

module clahe_ram_64tiles_sim (
        input  wire        pclk,
        input  wire        rst_n,

        // 乒乓控制
        input  wire        ping_pong_flag,  // 0=使用RAM_A, 1=使用RAM_B

        // 清零控制
        input  wire        clear_start,     // 清零开始信号
        output wire        clear_done,      // 清零完成信号

        // 读写接口 - 真双端口设计
        input  wire [5:0]  tile_idx,        // tile索引 (0-63)

        // Port A: 写端口（清零和直方图统计写入）
        input  wire [7:0]  wr_addr_a,       // 写地址A (0-255)
        input  wire [15:0] wr_data_a,       // 写数据A
        input  wire        wr_en_a,         // 写使能A

        // Port B: 读端口（直方图统计读取）
        input  wire [7:0]  rd_addr_b,      // 读地址B (0-255)
        output wire [15:0] rd_data_b       // 读数据B
    );

    // ========================================================================
    // 参数定义
    // ========================================================================
    localparam TILE_NUM = 64;
    localparam BINS = 256;

    // ========================================================================
    // 清零控制逻辑
    // ========================================================================
    reg        clear_busy;
    reg [7:0]  clear_addr;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            clear_busy <= 1'b0;
            clear_addr <= 8'd0;
        end
        else if (clear_start) begin
            clear_busy <= 1'b1;
            clear_addr <= 8'd0;
        end
        else if (clear_busy) begin
            if (clear_addr < BINS - 1) begin
                clear_addr <= clear_addr + 8'd1;
            end
            else begin
                clear_busy <= 1'b0;
            end
        end
    end

    assign clear_done = !clear_busy;

    // ========================================================================
    // 64块RAM_A (ping_pong_flag=0时使用) - 真双端口设计
    // ========================================================================
    wire [15:0] ram_a_data_b [0:63];    // Port B读数据
    wire        ram_a_wr_en_a [0:63];   // Port A写使能
    wire [7:0]  ram_a_addr_a [0:63];    // Port A地址
    wire [15:0] ram_a_wr_data_a [0:63]; // Port A写数据
    wire [7:0]  ram_a_addr_b [0:63];    // Port B地址

    // 生成64块RAM_A
    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : gen_ram_a
            // Port A写控制逻辑（清零和直方图统计写入）
            assign ram_a_wr_en_a[i] = (clear_busy && ping_pong_flag) ? 1'b1 :
                   (wr_en_a && !ping_pong_flag && tile_idx == i) ? 1'b1 : 1'b0;

            assign ram_a_addr_a[i] = (clear_busy && ping_pong_flag) ? clear_addr :
                   (wr_en_a && !ping_pong_flag && tile_idx == i) ? wr_addr_a : 8'd0;

            assign ram_a_wr_data_a[i] = (clear_busy && ping_pong_flag) ? 16'd0 :
                   (wr_en_a && !ping_pong_flag && tile_idx == i) ? wr_data_a : 16'd0;

            // Port B读控制逻辑（直方图统计读取）
            assign ram_a_addr_b[i] = (rd_addr_b && !ping_pong_flag && tile_idx == i) ? rd_addr_b : 8'd0;

            // 真双端口RAM实例
            clahe_tile_ram_true_dual ram_a_inst (
                                         // Port A (写端口)
                                         .clka(pclk),
                                         .wea(ram_a_wr_en_a[i]),
                                         .addra(ram_a_addr_a[i]),
                                         .dina(ram_a_wr_data_a[i]),
                                         .douta(),  // Port A不用于读

                                         // Port B (读端口)
                                         .clkb(pclk),
                                         .web(1'b0),  // Port B不用于写
                                         .addrb(ram_a_addr_b[i]),
                                         .dinb(16'd0),  // Port B不用于写
                                         .doutb(ram_a_data_b[i])
                                     );
        end
    endgenerate

    // ========================================================================
    // 64块RAM_B (ping_pong_flag=1时使用) - 真双端口设计
    // ========================================================================
    wire [15:0] ram_b_data_b [0:63];    // Port B读数据
    wire        ram_b_wr_en_a [0:63];   // Port A写使能
    wire [7:0]  ram_b_addr_a [0:63];    // Port A地址
    wire [15:0] ram_b_wr_data_a [0:63]; // Port A写数据
    wire [7:0]  ram_b_addr_b [0:63];    // Port B地址

    // 生成64块RAM_B
    generate
        for (i = 0; i < 64; i = i + 1) begin : gen_ram_b
            // Port A写控制逻辑（清零和直方图统计写入）
            assign ram_b_wr_en_a[i] = (clear_busy && !ping_pong_flag) ? 1'b1 :
                   (wr_en_a && ping_pong_flag && tile_idx == i) ? 1'b1 : 1'b0;

            assign ram_b_addr_a[i] = (clear_busy && !ping_pong_flag) ? clear_addr :
                   (wr_en_a && ping_pong_flag && tile_idx == i) ? wr_addr_a : 8'd0;

            assign ram_b_wr_data_a[i] = (clear_busy && !ping_pong_flag) ? 16'd0 :
                   (wr_en_a && ping_pong_flag && tile_idx == i) ? wr_data_a : 16'd0;

            // Port B读控制逻辑（直方图统计读取）
            assign ram_b_addr_b[i] = (rd_addr_b && ping_pong_flag && tile_idx == i) ? rd_addr_b : 8'd0;

            // 真双端口RAM实例
            clahe_tile_ram_true_dual ram_b_inst (
                                         // Port A (写端口)
                                         .clka(pclk),
                                         .wea(ram_b_wr_en_a[i]),
                                         .addra(ram_b_addr_a[i]),
                                         .dina(ram_b_wr_data_a[i]),
                                         .douta(),  // Port A不用于读

                                         // Port B (读端口)
                                         .clkb(pclk),
                                         .web(1'b0),  // Port B不用于写
                                         .addrb(ram_b_addr_b[i]),
                                         .dinb(16'd0),  // Port B不用于写
                                         .doutb(ram_b_data_b[i])
                                     );
        end
    endgenerate

    // ========================================================================
    // 读数据选择：根据乒乓标志选择对应的RAM数据
    // ========================================================================
    assign rd_data_b = (!ping_pong_flag) ? ram_a_data_b[tile_idx] : ram_b_data_b[tile_idx];

endmodule
