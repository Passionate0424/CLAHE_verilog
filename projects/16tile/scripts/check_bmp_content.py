#!/usr/bin/env python3
"""
检查BMP文件内容，验证像素数据是否正常
"""

import struct
import sys

def check_bmp(filename):
    """检查BMP文件的头部信息和前几个像素值"""
    
    try:
        with open(filename, 'rb') as f:
            # 读取BMP文件头（14字节）
            file_header = f.read(14)
            if len(file_header) < 14:
                print(f"❌ 文件太小，不是有效的BMP文件")
                return
            
            # 解析文件头
            signature = file_header[0:2]
            file_size = struct.unpack('<I', file_header[2:6])[0]
            offset = struct.unpack('<I', file_header[10:14])[0]
            
            print(f"📁 文件: {filename}")
            print(f"✓ BMP签名: {signature} (应该是b'BM')")
            print(f"✓ 文件大小: {file_size} 字节 ({file_size/1024/1024:.2f} MB)")
            print(f"✓ 像素数据偏移: {offset} 字节")
            
            if signature != b'BM':
                print(f"❌ 错误：不是有效的BMP文件！")
                return
            
            # 读取信息头（40字节）
            info_header = f.read(40)
            if len(info_header) < 40:
                print(f"❌ 信息头不完整")
                return
            
            header_size = struct.unpack('<I', info_header[0:4])[0]
            width = struct.unpack('<i', info_header[4:8])[0]
            height = struct.unpack('<i', info_header[8:12])[0]
            planes = struct.unpack('<H', info_header[12:14])[0]
            bits_per_pixel = struct.unpack('<H', info_header[14:16])[0]
            
            print(f"✓ 图像宽度: {width}")
            print(f"✓ 图像高度: {height}")
            print(f"✓ 颜色平面: {planes}")
            print(f"✓ 每像素位数: {bits_per_pixel}")
            
            # 计算行宽度（4字节对齐）
            row_size = ((width * bits_per_pixel // 8) + 3) & ~3
            print(f"✓ 每行字节数（对齐后）: {row_size}")
            
            # 跳到像素数据
            f.seek(offset)
            
            # 读取前10个像素（从最后一行开始，因为BMP是倒序存储）
            print(f"\n📊 前10个像素值（BGR格式，最后一行开始）：")
            for i in range(min(10, width)):
                pixel = f.read(3)
                if len(pixel) < 3:
                    break
                b, g, r = pixel[0], pixel[1], pixel[2]
                
                # 计算YUV（使用testbench中的公式）
                y = int((19595 * r + 38470 * g + 7471 * b + 32768) >> 16)
                
                print(f"  像素[{i}]: R={r:3d}, G={g:3d}, B={b:3d} → Y={y:3d}")
            
            # 统计整个图像的亮度分布
            print(f"\n📈 图像统计分析：")
            f.seek(offset)
            
            y_sum = 0
            y_min = 255
            y_max = 0
            zero_count = 0
            total_pixels = width * abs(height)
            
            for row in range(abs(height)):
                for col in range(width):
                    pixel = f.read(3)
                    if len(pixel) < 3:
                        break
                    b, g, r = pixel[0], pixel[1], pixel[2]
                    y = int((19595 * r + 38470 * g + 7471 * b + 32768) >> 16)
                    
                    y_sum += y
                    y_min = min(y_min, y)
                    y_max = max(y_max, y)
                    if y == 0:
                        zero_count += 1
                
                # 跳过行尾填充
                f.seek(offset + row_size * (row + 1))
            
            y_avg = y_sum / total_pixels if total_pixels > 0 else 0
            
            print(f"  总像素数: {total_pixels}")
            print(f"  平均亮度(Y): {y_avg:.1f}")
            print(f"  最小亮度(Y): {y_min}")
            print(f"  最大亮度(Y): {y_max}")
            print(f"  零亮度像素: {zero_count} ({100*zero_count/total_pixels:.2f}%)")
            
            if y_avg < 10:
                print(f"\n⚠️  警告：平均亮度非常低（{y_avg:.1f}），图像可能非常暗或几乎全黑！")
            elif y_avg < 50:
                print(f"\n⚠️  警告：平均亮度较低（{y_avg:.1f}），图像较暗。")
            else:
                print(f"\n✅ 图像亮度正常（平均 {y_avg:.1f}）")
                
    except FileNotFoundError:
        print(f"❌ 文件不存在: {filename}")
    except Exception as e:
        print(f"❌ 读取错误: {e}")

if __name__ == "__main__":
    files = [
        "sim/bmp_in/test_standard.bmp",
        "bmp_test_results/output/output_frame 0.bmp",
        "bmp_test_results/input/input_frame0.bmp"
    ]
    
    for bmp_file in files:
        print("=" * 70)
        check_bmp(bmp_file)
        print()

