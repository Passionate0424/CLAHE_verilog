// 简化的CLAHE testbench - 使用readmemh读取HEX格式图像数据
// 避免使用有问题的$fopen
`timescale 1ns/1ps

module tb_clahe_simple_hex;

    // 参数
    parameter H_DISP = 1280;
    parameter V_DISP = 720;
    parameter CLK_PERIOD = 10;  // 100MHz

    // 信号
    reg pclk, rst_n;
    reg [23:0] pixel_mem [0:H_DISP*V_DISP-1];  // 像素内存
    integer pixel_idx;

    // CLAHE输入输出
    wire [7:0] in_y, in_u, in_v;
    wire in_href, in_vsync;
    wire [7:0] out_y, out_u, out_v;
    wire out_href, out_vsync;

    // 时钟生成
    initial begin
        pclk = 0;
        forever
            #(CLK_PERIOD/2) pclk = ~pclk;
    end

    // 读取HEX文件
    initial begin
        $display("Loading pixel data from HEX file...");
        $readmemh("test_input.hex", pixel_mem);
        $display("Pixel data loaded: %0d pixels", H_DISP*V_DISP);
        $display("First pixel: %06h", pixel_mem[0]);
        $display("Last pixel: %06h", pixel_mem[H_DISP*V_DISP-1]);
    end

    // RGB to YUV conversion
    wire [7:0] pixel_b = pixel_mem[pixel_idx][23:16];
    wire [7:0] pixel_g = pixel_mem[pixel_idx][15:8];
    wire [7:0] pixel_r = pixel_mem[pixel_idx][7:0];

    wire [31:0] y_temp = (19595 * pixel_r + 38470 * pixel_g + 7471 * pixel_b);
    assign in_y = (y_temp + 32768) >> 16;
    assign in_u = 128;  // 暂时固定
    assign in_v = 128;

    // 测试流程
    reg test_running;
    integer x_cnt, y_cnt;

    assign in_href = test_running && (x_cnt < H_DISP) && (y_cnt < V_DISP);
    assign in_vsync = (y_cnt < V_DISP);

    initial begin
        rst_n = 0;
        test_running = 0;
        pixel_idx = 0;
        x_cnt = 0;
        y_cnt = 0;

        repeat(100) @(posedge pclk);
        rst_n = 1;

        repeat(100) @(posedge pclk);
        $display("\n[%0t] Starting test...", $time);
        test_running = 1;

        // 发送一帧图像
        for (y_cnt = 0; y_cnt < V_DISP; y_cnt = y_cnt + 1) begin
            for (x_cnt = 0; x_cnt < H_DISP; x_cnt = x_cnt + 1) begin
                pixel_idx = y_cnt * H_DISP + x_cnt;
                if (pixel_idx < 10) begin
                    $display("[Pixel %0d] RGB=(%0d,%0d,%0d) -> Y=%0d",
                             pixel_idx, pixel_r, pixel_g, pixel_b, in_y);
                end
                @(posedge pclk);
            end
        end

        test_running = 0;
        $display("\n[%0t] Test complete!", $time);

        repeat(1000) @(posedge pclk);
        $stop;
    end

    // DUT实例化
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
                  .clahe_enable(1'b1),
                  .enable_interp(1'b1),
                  .clip_threshold(12'd600)
              );

    // 监控输出
    integer out_pixel_count;
    initial begin
        out_pixel_count = 0;
        forever begin
            @(posedge pclk);
            if (out_href) begin
                out_pixel_count = out_pixel_count + 1;
                if (out_pixel_count <= 10 || out_y > 0) begin
                    if (out_pixel_count <= 20) begin
                        $display("[Out %0d] Y=%0d U=%0d V=%0d",
                                 out_pixel_count, out_y, out_u, out_v);
                    end
                end
            end
        end
    end

endmodule


