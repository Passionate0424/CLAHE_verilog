# ????????
$testScript = @"
`timescale 1ns/1ps

module test_yuv2rgb;
    reg [7:0] out_y, out_u, out_v;
    wire [7:0] bmp_out_r, bmp_out_g, bmp_out_b;
    
    wire signed [9:0] u_offset = `$signed({2'b0, out_u}) - 10'sd128;
    wire signed [9:0] v_offset = `$signed({2'b0, out_v}) - 10'sd128;
    
    wire signed [18:0] r_temp = `$signed({11'd0, out_y}) + (19'sd359 * v_offset);
    wire signed [18:0] g_temp = `$signed({11'd0, out_y}) - (19'sd88 * u_offset) - (19'sd183 * v_offset);
    wire signed [18:0] b_temp = `$signed({11'd0, out_y}) + (19'sd454 * u_offset);
    
    function [7:0] saturate;
        input signed [18:0] val;
        reg signed [10:0] shifted;
        begin
            shifted = val >>> 8;
            if (shifted < 0)
                saturate = 8'd0;
            else if (shifted > 255)
                saturate = 8'd255;
            else
                saturate = shifted[7:0];
        end
    endfunction
    
    assign bmp_out_r = saturate(r_temp);
    assign bmp_out_g = saturate(g_temp);
    assign bmp_out_b = saturate(b_temp);
    
    initial begin
        out_y = 100; out_u = 128; out_v = 128;
        #10;
        `$display("Y=%0d, U=%0d, V=%0d => R=%0d, G=%0d, B=%0d", out_y, out_u, out_v, bmp_out_r, bmp_out_g, bmp_out_b);
        
        out_y = 100; out_u = 100; out_v = 150;
        #10;
        `$display("Y=%0d, U=%0d, V=%0d => R=%0d, G=%0d, B=%0d", out_y, out_u, out_v, bmp_out_r, bmp_out_g, bmp_out_b);
        
        `$stop;
    end
endmodule
"@

$testScript | Out-File -Encoding ASCII test_yuv.v
vlog test_yuv.v
vsim -c -do "run -all; quit -f" work.test_yuv2rgb
