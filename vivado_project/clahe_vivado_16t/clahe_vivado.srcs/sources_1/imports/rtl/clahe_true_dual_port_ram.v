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
// True Dual Port RAM - 可综合为 Block RAM
//
// 功能：提供2个独立的读写端口，支持同时读写操作
// 特性：
//   - 每个端口都支持读写
//   - READ_FIRST模式：读取旧数据（写入前的值）
//   - 1周期读延迟
//   - 可被综合工具推断为BRAM，也可用Xilinx IP替代
//
// 作者: Passionate.Z
// 日期: 2025-10-28
// ============================================================================

module clahe_true_dual_port_ram #(
        parameter DATA_WIDTH = 16,
        parameter ADDR_WIDTH = 8,
        parameter DEPTH = 256
    )(
        input  wire                     clk,

        // 端口A（支持读写）
        input  wire                     ena,
        input  wire                     wea,
        input  wire [ADDR_WIDTH-1:0]    addra,
        input  wire [DATA_WIDTH-1:0]    dina,
        output reg  [DATA_WIDTH-1:0]    douta,

        // 端口B（支持读写）
        input  wire                     enb,
        input  wire                     web,
        input  wire [ADDR_WIDTH-1:0]    addrb,
        input  wire [DATA_WIDTH-1:0]    dinb,
        output reg  [DATA_WIDTH-1:0]    doutb
    );

    // RAM存储阵列
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // 端口A操作
    always @(posedge clk) begin
        if (ena) begin
            if (wea) begin
                ram[addra] <= dina;      // 写操作
            end
            douta <= ram[addra];         // 读操作（READ_FIRST模式）
        end
    end

    // 端口B操作
    always @(posedge clk) begin
        if (enb) begin
            if (web) begin
                ram[addrb] <= dinb;      // 写操作
            end
            doutb <= ram[addrb];         // 读操作（READ_FIRST模式）
        end
    end

endmodule
