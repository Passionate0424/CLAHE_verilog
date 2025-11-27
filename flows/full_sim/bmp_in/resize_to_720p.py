#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图像缩放到720p脚本
将任意尺寸的图像缩放到1280x720分辨率的24位BMP格式
"""

from PIL import Image
import os
import sys

def resize_to_720p(input_path, output_path=None, target_size=(1280, 720)):
    """
    将图像缩放到指定分辨率并保存为BMP
    
    参数:
        input_path: 输入图像文件路径
        output_path: BMP输出文件路径（可选，默认覆盖原文件）
        target_size: 目标分辨率 (宽, 高)
    
    返回:
        True: 转换成功
        False: 转换失败
    """
    try:
        # 打开图像
        img = Image.open(input_path)
        print(f"打开图像: {input_path}")
        print(f"  原始尺寸: {img.size}")
        print(f"  原始模式: {img.mode}")
        
        # 如果未指定输出路径，则覆盖原文件（改为.bmp扩展名）
        if output_path is None:
            base_name = os.path.splitext(input_path)[0]
            output_path = base_name + '_720p.bmp'
        
        # 缩放图像（使用高质量的Lanczos重采样）
        if img.size != target_size:
            print(f"  缩放: {img.size} -> {target_size}")
            img = img.resize(target_size, Image.Resampling.LANCZOS)
        else:
            print(f"  尺寸已是目标尺寸，无需缩放")
        
        # 转换为RGB模式（如果需要）
        if img.mode == 'L':
            print(f"  转换模式: {img.mode} -> RGB (灰度)")
            img = img.convert('RGB')
        elif img.mode == 'RGBA':
            print(f"  转换模式: {img.mode} -> RGB (去除Alpha通道)")
            background = Image.new('RGB', img.size, (255, 255, 255))
            background.paste(img, mask=img.split()[3])
            img = background
        elif img.mode != 'RGB':
            print(f"  转换模式: {img.mode} -> RGB")
            img = img.convert('RGB')
        
        # 保存为24位BMP
        img.save(output_path, 'BMP')
        print(f"成功保存BMP: {output_path}")
        
        # 验证保存的BMP文件
        bmp_img = Image.open(output_path)
        print(f"  验证BMP尺寸: {bmp_img.size}")
        print(f"  验证BMP模式: {bmp_img.mode}")
        
        return True
        
    except Exception as e:
        print(f"转换失败 ({input_path}): {e}")
        return False

def batch_resize(input_dir, output_dir=None, target_size=(1280, 720), extensions=None):
    """
    批量缩放目录下的所有图像文件
    
    参数:
        input_dir: 输入图像目录
        output_dir: BMP输出目录（可选，默认与输入同目录）
        target_size: 目标分辨率 (宽, 高)
        extensions: 要处理的文件扩展名列表（可选）
    """
    if output_dir is None:
        output_dir = input_dir
    
    # 创建输出目录
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        print(f"创建输出目录: {output_dir}")
    
    # 默认支持的图像格式
    if extensions is None:
        extensions = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tif', '.tiff']
    
    # 查找所有支持的图像文件
    image_files = []
    for ext in extensions:
        image_files.extend([f for f in os.listdir(input_dir) 
                          if f.lower().endswith(ext.lower()) and '_720p' not in f.lower()])
    
    if not image_files:
        print(f"在 {input_dir} 目录下没有找到支持的图像文件")
        print(f"支持的格式: {', '.join(extensions)}")
        return 0
    
    print(f"\n找到 {len(image_files)} 个图像文件:")
    for img_file in image_files:
        print(f"  - {img_file}")
    
    print(f"\n开始缩放到 {target_size[0]}x{target_size[1]}...\n")
    
    success_count = 0
    for i, img_file in enumerate(image_files, 1):
        input_path = os.path.join(input_dir, img_file)
        bmp_file = os.path.splitext(img_file)[0] + '_720p.bmp'
        output_path = os.path.join(output_dir, bmp_file)
        
        print(f"[{i}/{len(image_files)}]", end=" ")
        if resize_to_720p(input_path, output_path, target_size):
            success_count += 1
        print()
    
    print(f"\n转换完成: {success_count}/{len(image_files)} 成功")
    return success_count

def main():
    """主函数：处理命令行参数"""
    
    # 如果提供了命令行参数
    if len(sys.argv) > 1:
        input_arg = sys.argv[1]
        
        # 判断是文件还是目录
        if os.path.isfile(input_arg):
            # 单文件转换
            print("="*60)
            print("单文件缩放模式 -> 1280x720")
            print("="*60)
            output_path = sys.argv[2] if len(sys.argv) > 2 else None
            resize_to_720p(input_arg, output_path)
        elif os.path.isdir(input_arg):
            # 批量转换
            print("="*60)
            print("批量缩放模式 -> 1280x720")
            print("="*60)
            output_dir = sys.argv[2] if len(sys.argv) > 2 else input_arg
            batch_resize(input_arg, output_dir)
        else:
            print(f"错误: {input_arg} 不是有效的文件或目录")
    else:
        # 默认模式：处理脚本所在目录的bmp_in文件夹
        script_dir = os.path.dirname(os.path.abspath(__file__))
        input_dir = os.path.join(script_dir, 'bmp_in')
        
        print("="*60)
        print("图像缩放到720p工具 - 自动批量转换模式")
        print("="*60)
        print(f"输入目录: {input_dir}")
        print(f"输出目录: {input_dir}")
        print(f"目标分辨率: 1280x720")
        print("支持格式: PNG, JPG, JPEG, BMP, GIF, TIF, TIFF")
        print("="*60)
        print()
        
        if os.path.exists(input_dir):
            success = batch_resize(input_dir, input_dir)
            if success > 0:
                print(f"\n✓ 成功处理 {success} 个文件")
                print("输出文件名格式: 原文件名_720p.bmp")
        else:
            print(f"错误: 目录 {input_dir} 不存在")
            print("\n使用方法:")
            print("  1. 无参数: python resize_to_720p.py")
            print("     - 缩放 ./bmp_in/ 目录下的所有图像到1280x720")
            print("  2. 单文件: python resize_to_720p.py input.png [output.bmp]")
            print("  3. 批量: python resize_to_720p.py input_dir/ [output_dir/]")
    
    print("\n处理完成！")

if __name__ == '__main__':
    main()


