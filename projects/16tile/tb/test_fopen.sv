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

// 简单的$fopen测试
module test_fopen;
    integer fp;
    
    initial begin
        $display("Testing $fopen...");
        
        // 测试1：相对路径
        fp = $fopen("test_input.bmp", "r");
        $display("Test 1 (relative path, r): fp = %0d (0x%0h)", fp, fp);
        if (fp > 0) $fclose(fp);
        
        // 测试2：绝对路径反斜杠
        fp = $fopen("E:\\FPGA_codes\\CLAHE\\16tile\\test_input.bmp", "r");
        $display("Test 2 (absolute backslash, r): fp = %0d (0x%0h)", fp, fp);
        if (fp > 0) $fclose(fp);
        
        // 测试3：绝对路径正斜杠
        fp = $fopen("E:/FPGA_codes/CLAHE/16tile/test_input.bmp", "r");
        $display("Test 3 (absolute forward slash, r): fp = %0d (0x%0h)", fp, fp);
        if (fp > 0) $fclose(fp);
        
        // 测试4：rb模式
        fp = $fopen("test_input.bmp", "rb");
        $display("Test 4 (relative path, rb): fp = %0d (0x%0h)", fp, fp);
        if (fp > 0) $fclose(fp);
        
        $display("All tests complete");
        $stop;
    end
endmodule


