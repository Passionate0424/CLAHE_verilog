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
// 伪双端口RAM模板 - 可直接替换为FPGA厂商IP核
//
// 功能描述:
//   - 伪双端口RAM：1个写端口 + 1个读端口
//   - 适用于 Xilinx BRAM、Intel M10K、Lattice EBR 等
//   - 支持同时读写不同地址
//
// IP核替换说明:
//   Xilinx (Vivado):
//     IP: Block Memory Generator
//     配置: Simple Dual Port RAM
//     - Port A: Write Only
//     - Port B: Read Only
//
//   Intel (Quartus):
//     IP: RAM: 2-PORT
//     配置: Simple Dual Port
//     - Port A: Write
//     - Port B: Read
//
//   Lattice:
//     IP: Distributed RAM
//     配置: Dual Port
//
// 参数:
//   - DATA_WIDTH: 数据位宽，默认16bit（支持直方图16bit和CDF LUT 8bit）
//   - ADDR_WIDTH: 地址位宽，默认8bit（256深度）
//clahe_ram_64tiles_parallel

// 作者: Passionate.Z
// 日期: 2025-10-18
// ============================================================================

`timescale 1ns / 1ps

module clahe_simple_dual_ram_model #(
        parameter DATA_WIDTH = 16,
        parameter ADDR_WIDTH = 8,
        parameter DEPTH = 256
    )(
        // Port A: 写端口
        input  wire                     clk_a,
        input  wire                     we_a,
        input  wire [ADDR_WIDTH-1:0]    addr_a,
        input  wire [DATA_WIDTH-1:0]    din_a,

        // Port B: 读端口
        input  wire                     clk_b,
        input  wire [ADDR_WIDTH-1:0]    addr_b,
        output reg  [DATA_WIDTH-1:0]    dout_b
    );

    // RAM存储阵列
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // Port A: 写操作
    always @(posedge clk_a) begin
        if (we_a) begin
            ram[addr_a] <= din_a;
        end
    end

    // Port B: 读操作
    always @(posedge clk_b) begin
        dout_b <= ram[addr_b];
    end

    // 初始化RAM（可选，用于仿真）
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            ram[i] = {DATA_WIDTH{1'b0}};
        end
    end

endmodule

