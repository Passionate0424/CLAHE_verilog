#!/usr/bin/env python3
"""
BMP转十六进制文本文件（for Verilog $readmemh）
将BMP图像的像素数据转换为Verilog可读的十六进制格式
"""

from PIL import Image
import sys

def bmp_to_hex(bmp_path, hex_path):
    """
    将BMP图像转换为十六进制文本文件
    每行格式: BBGGRR (24位，BGR顺序)
    """
    try:
        img = Image.open(bmp_path)
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        width, height = img.size
        print(f"转换BMP: {bmp_path}")
        print(f"  尺寸: {width}x{height}")
        print(f"  总像素: {width*height}")
        
        with open(hex_path, 'w') as f:
            # 写入图像尺寸信息（注释）
            f.write(f"// Image: {bmp_path}\n")
            f.write(f"// Size: {width}x{height}\n")
            f.write(f"// Format: BGR (Blue-Green-Red), 24-bit\n")
            f.write(f"// Total pixels: {width*height}\n")
            f.write(f"//\n")
            
            # 逐像素写入（从上到下，从左到右）
            pixels = img.load()
            for y in range(height):
                for x in range(width):
                    r, g, b = pixels[x, y]
                    # BGR顺序，每个像素24位
                    f.write(f"{b:02X}{g:02X}{r:02X}\n")
        
        print(f"成功生成HEX文件: {hex_path}")
        return True
        
    except Exception as e:
        print(f"转换失败: {e}")
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python bmp_to_hex.py input.bmp [output.hex]")
        sys.exit(1)
    
    bmp_path = sys.argv[1]
    hex_path = sys.argv[2] if len(sys.argv) > 2 else bmp_path.replace('.bmp', '.hex')
    
    bmp_to_hex(bmp_path, hex_path)


