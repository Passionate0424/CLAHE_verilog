#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PNG转BMP脚本
将sim/bmp_in目录下的PNG文件转换为24位BMP格式
"""

from PIL import Image
import os

def convert_png_to_bmp(png_path, bmp_path):
    """
    将PNG图像转换为24位BMP格式
    
    参数:
        png_path: PNG输入文件路径
        bmp_path: BMP输出文件路径
    """
    try:
        # 打开PNG图像
        img = Image.open(png_path)
        print(f"打开图像: {png_path}")
        print(f"  图像模式: {img.mode}")
        print(f"  图像尺寸: {img.size}")
        
        # 转换为RGB模式（如果是灰度或RGBA）
        if img.mode != 'RGB':
            print(f"  转换模式: {img.mode} -> RGB")
            img = img.convert('RGB')
        
        # 保存为24位BMP
        img.save(bmp_path, 'BMP')
        print(f"成功保存BMP: {bmp_path}")
        
        # 验证保存的BMP文件
        bmp_img = Image.open(bmp_path)
        print(f"  BMP尺寸: {bmp_img.size}")
        print(f"  BMP模式: {bmp_img.mode}")
        
        return True
        
    except Exception as e:
        print(f"转换失败: {e}")
        return False

def batch_convert(input_dir, output_dir):
    """
    批量转换目录下的所有PNG文件
    
    参数:
        input_dir: PNG输入目录
        output_dir: BMP输出目录
    """
    # 创建输出目录
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        print(f"创建输出目录: {output_dir}")
    
    # 查找所有PNG文件
    png_files = [f for f in os.listdir(input_dir) if f.lower().endswith('.png')]
    
    if not png_files:
        print(f"在 {input_dir} 目录下没有找到PNG文件")
        return
    
    print(f"\n找到 {len(png_files)} 个PNG文件:")
    for png_file in png_files:
        print(f"  - {png_file}")
    
    print(f"\n开始转换...\n")
    
    success_count = 0
    for png_file in png_files:
        png_path = os.path.join(input_dir, png_file)
        bmp_file = os.path.splitext(png_file)[0] + '.bmp'
        bmp_path = os.path.join(output_dir, bmp_file)
        
        print(f"[{success_count+1}/{len(png_files)}]", end=" ")
        if convert_png_to_bmp(png_path, bmp_path):
            success_count += 1
        print()
    
    print(f"\n转换完成: {success_count}/{len(png_files)} 成功")

if __name__ == '__main__':
    # 获取脚本所在目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 设置输入输出目录
    input_dir = os.path.join(script_dir, 'bmp_in')
    output_dir = os.path.join(script_dir, 'bmp_in')  # 输出到同一目录
    
    print("="*60)
    print("PNG to BMP 转换工具")
    print("="*60)
    print(f"输入目录: {input_dir}")
    print(f"输出目录: {output_dir}")
    print("="*60)
    print()
    
    # 执行批量转换
    batch_convert(input_dir, output_dir)
    
    print("\n转换完成！")

