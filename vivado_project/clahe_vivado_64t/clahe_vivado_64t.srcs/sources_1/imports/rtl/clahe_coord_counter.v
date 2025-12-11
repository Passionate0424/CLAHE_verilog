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
// CLAHE 坐标计数与Tile定位模块
//
// 功能描述:
//   - 对输入图像进行像素坐标计数，实时跟踪当前像素位置
//   - 根据像素坐标计算所属的tile索引（8×8分块）
//   - 生成tile内部的相对坐标，用于后续直方图统计
//   - 支持1280×720分辨率，64个tiles，每个tile 160×90像素
//
// 工作原理:
//   1. 像素坐标计数：在href有效期间，x_cnt和y_cnt递增
//   2. Tile索引计算：通过除法运算确定当前像素属于哪个tile
//   3. 相对坐标计算：计算像素在tile内的相对位置
//   4. 边界处理：行结束和帧结束时复位计数器
//
// 参数说明:
//   - WIDTH: 图像宽度，默认1280像素
//   - HEIGHT: 图像高度，默认720像素
//   - TILE_H_NUM: 横向tile数量，默认8个
//   - TILE_V_NUM: 纵向tile数量，默认8个
//
// 输出信号:
//   - x_cnt, y_cnt: 全局像素坐标 (0-1279, 0-719)
//   - tile_x, tile_y: tile坐标 (0-7, 0-7)
//   - tile_idx: tile总索引 (0-63)
//   - local_x, local_y: tile内相对坐标 (0-159, 0-89)
//
// 作者: Passionate.Z
// 日期: 2025-10-15
// ============================================================================

module clahe_coord_counter #(
        parameter WIDTH = 1280,
        parameter HEIGHT = 720,
        parameter TILE_H_NUM = 8,      // 横向8个tile
        parameter TILE_V_NUM = 8       // 纵向8个tile
    )(
        input  wire        pclk,       // 像素时钟
        input  wire        rst_n,      // 复位信号，低电平有效

        // 输入同步信号
        input  wire        in_href,    // 行有效信号
        input  wire        in_vsync,   // 帧有效信号

        // 输出坐标信息
        output reg  [10:0] x_cnt,      // 横向像素坐标 (0-1279)
        output reg  [9:0]  y_cnt,      // 纵向像素坐标 (0-719)
        output reg  [2:0]  tile_x,     // tile横向索引 (0-7)
        output reg  [2:0]  tile_y,     // tile纵向索引 (0-7)
        output reg  [5:0]  tile_idx,   // tile总索引 (0-63)
        output reg  [7:0]  local_x,    // tile内横向坐标 (0-159)
        output reg  [6:0]  local_y     // tile内纵向坐标 (0-89)
    );

    // ========================================================================
    // 参数计算
    // ========================================================================
    localparam TILE_WIDTH = WIDTH / TILE_H_NUM;    // 每个tile宽度 = 160像素
    localparam TILE_HEIGHT = HEIGHT / TILE_V_NUM;  // 每个tile高度 = 90像素

    // ========================================================================
    // 像素坐标计数器
    // ========================================================================
    // 功能：在href有效期间递增像素坐标，实现行列扫描
    // 复位：系统复位或帧无效时清零
    // 边界：行结束时x_cnt复位，y_cnt递增；帧结束时全部复位
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            // 系统复位：清零所有计数器
            x_cnt <= 11'd0;  // 横向坐标复位为0
            y_cnt <= 10'd0;  // 纵向坐标复位为0
        end
        else if (in_href) begin
            // 行有效期间：进行像素坐标计数
            if (x_cnt < WIDTH - 1) begin
                // 当前行未结束：横向坐标递增
                x_cnt <= x_cnt + 11'd1;
            end
            else begin
                // 当前行结束：横向坐标复位，纵向坐标递增
                x_cnt <= 11'd0;
                if (y_cnt < HEIGHT - 1) begin
                    // 帧未结束：纵向坐标递增
                    y_cnt <= y_cnt + 10'd1;
                end
                else begin
                    // 帧结束：纵向坐标复位
                    y_cnt <= 10'd0;
                end
            end
        end
        else if (!in_vsync) begin
            // 帧无效期间：复位所有计数器
            x_cnt <= 11'd0;
            y_cnt <= 10'd0;
        end
    end

    // ========================================================================
    // Tile索引计算
    // ========================================================================
    // 功能：根据像素坐标计算所属的tile索引
    // 原理：tile_x = x_cnt / 160, tile_y = y_cnt / 90
    // 优化：使用比较器替代除法器，节省硬件资源

    // 横向tile索引计算（x_cnt除以160）
    // 通过比较x_cnt的范围来确定tile_x的值
    always @(*) begin
        if (x_cnt < 160)        // 0-159像素 -> tile 0
            tile_x = 3'd0;
        else if (x_cnt < 320)   // 160-319像素 -> tile 1
            tile_x = 3'd1;
        else if (x_cnt < 480)   // 320-479像素 -> tile 2
            tile_x = 3'd2;
        else if (x_cnt < 640)   // 480-639像素 -> tile 3
            tile_x = 3'd3;
        else if (x_cnt < 800)   // 640-799像素 -> tile 4
            tile_x = 3'd4;
        else if (x_cnt < 960)   // 800-959像素 -> tile 5
            tile_x = 3'd5;
        else if (x_cnt < 1120)  // 960-1119像素 -> tile 6
            tile_x = 3'd6;
        else                    // 1120-1279像素 -> tile 7
            tile_x = 3'd7;
    end

    // 纵向tile索引计算（y_cnt除以90）
    // 通过比较y_cnt的范围来确定tile_y的值
    always @(*) begin
        if (y_cnt < 90)         // 0-89像素 -> tile 0
            tile_y = 3'd0;
        else if (y_cnt < 180)   // 90-179像素 -> tile 1
            tile_y = 3'd1;
        else if (y_cnt < 270)   // 180-269像素 -> tile 2
            tile_y = 3'd2;
        else if (y_cnt < 360)   // 270-359像素 -> tile 3
            tile_y = 3'd3;
        else if (y_cnt < 450)   // 360-449像素 -> tile 4
            tile_y = 3'd4;
        else if (y_cnt < 540)   // 450-539像素 -> tile 5
            tile_y = 3'd5;
        else if (y_cnt < 630)   // 540-629像素 -> tile 6
            tile_y = 3'd6;
        else                    // 630-719像素 -> tile 7
            tile_y = 3'd7;
    end

    // tile总索引计算
    // tile_idx = tile_y * 8 + tile_x
    // 使用位拼接实现：{tile_y, tile_x}等价于tile_y * 8 + tile_x
    always @(*) begin
        tile_idx = {tile_y, tile_x};  // 6位tile索引，范围0-63
    end

    // ========================================================================
    // Tile内相对坐标计算（优化版 - 使用移位加法替代多个减法器）
    // ========================================================================
    // 功能：计算像素在tile内的相对坐标
    // 原理：local_x = x_cnt % 160, local_y = y_cnt % 90
    //
    // 优化说明：
    //   - 原实现：8个case分支，需要7个11位减法器 + 7个10位减法器
    //   - 新实现：使用移位加法计算偏移量，只需1个减法器
    //   - 预期收益：减少约30%的组合逻辑资源
    //
    // 计算方法：
    //   tile_x_offset = tile_x * 160 = tile_x * (128 + 32)
    //                 = (tile_x << 7) + (tile_x << 5)
    //   tile_y_offset = tile_y * 90 = tile_y * (64 + 16 + 8 + 2)
    //                 = (tile_y << 6) + (tile_y << 4) + (tile_y << 3) + (tile_y << 1)

    // 横向偏移量计算：tile_x * 160
    wire [10:0] tile_x_offset;
    assign tile_x_offset = ({tile_x, 7'd0}) + ({tile_x, 5'd0});  // (tile_x << 7) + (tile_x << 5)

    // 纵向偏移量计算：tile_y * 90
    wire [9:0] tile_y_offset;
    assign tile_y_offset = ({tile_y, 6'd0}) + ({tile_y, 4'd0}) +
           ({tile_y, 3'd0}) + ({tile_y, 1'd0});  // 四项移位加法

    // 横向相对坐标计算（优化：只需1个减法器）
    always @(*) begin
        local_x = x_cnt[7:0] - tile_x_offset[7:0];
    end

    // 纵向相对坐标计算（优化：只需1个减法器）
    always @(*) begin
        local_y = y_cnt[6:0] - tile_y_offset[6:0];
    end

endmodule

