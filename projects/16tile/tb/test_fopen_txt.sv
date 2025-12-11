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

// 测试文本文件
module test_fopen_txt;
    integer fp;
    reg [7:0] data;
    
    initial begin
        $display("Testing $fopen with text file...");
        
        fp = $fopen("test.txt", "r");
        $display("Open test.txt: fp = %0d (0x%0h)", fp, fp);
        
        if (fp > 0) begin
            data = $fgetc(fp);
            $display("First byte: %0d ('%c')", data, data);
            $fclose(fp);
        end else begin
            $display("ERROR: Failed to open test.txt");
        end
        
        $stop;
    end
endmodule


