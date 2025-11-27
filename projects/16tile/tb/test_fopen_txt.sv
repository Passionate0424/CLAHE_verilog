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


