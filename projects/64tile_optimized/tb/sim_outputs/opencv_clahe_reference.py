#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenCV标准CLAHE参考实现
用于对比硬件CLAHE实现的正确性

使用与硬件相同的参数：
- Tile Grid: 8x8
- Clip Limit: 3.0
- 图像尺寸: 512x512
"""

import cv2
import numpy as np
import os
from pathlib import Path
from PIL import Image

# 允许读取截断的BMP文件（处理仿真期间可能未完全写入的文件）
from PIL import ImageFile
ImageFile.LOAD_TRUNCATED_IMAGES = True

def process_clahe_opencv(input_path, output_path, clip_limit=3.0, tile_size=(64, 64)):
    """
    使用OpenCV标准CLAHE处理图像
    
    参数:
        input_path: 输入BMP文件路径
        output_path: 输出BMP文件路径
        clip_limit: 裁剪限制（硬件默认为3）
        tile_size: 每个tile的像素尺寸，对于512x512图像和8x8 tiles，每个tile是64x64
    """
    try:
        # 使用PIL读取图像（更好的BMP支持）
        pil_img = Image.open(input_path)
        
        # 转换为灰度图
        if pil_img.mode != 'L':
            pil_img = pil_img.convert('L')
        
        # 转换为numpy数组供OpenCV使用
        img = np.array(pil_img)
        
        # 创建CLAHE对象 (自动计算tile大小)
        # 对于不同的图像尺寸，保持8x8 tiles
        clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=(8, 8))
        
        # 应用CLAHE
        enhanced = clahe.apply(img)
        
        # 保存结果
        enhanced_pil = Image.fromarray(enhanced)
        enhanced_pil.save(output_path)
        
    except Exception as e:
        print(f"❌ 处理图像失败: {input_path}")
        print(f"   错误: {e}")
        return False
    
    # 统计信息
    input_mean = np.mean(img)
    input_std = np.std(img)
    output_mean = np.mean(enhanced)
    output_std = np.std(enhanced)
    
    print(f"✓ {os.path.basename(input_path):25s} -> {os.path.basename(output_path):25s}")
    print(f"  输入: 均值={input_mean:6.2f}, 标准差={input_std:6.2f}, 范围=[{img.min():3d}, {img.max():3d}]")
    print(f"  输出: 均值={output_mean:6.2f}, 标准差={output_std:6.2f}, 范围=[{enhanced.min():3d}, {enhanced.max():3d}]")
    
    return True

def batch_process(input_dir, output_dir, clip_limit=3.0):
    """
    批量处理文件夹中的所有frame_input图像
    """
    input_dir = Path(input_dir)
    output_dir = Path(output_dir)
    
    # 创建opencv_reference子文件夹
    opencv_output_dir = output_dir / "opencv_reference"
    opencv_output_dir.mkdir(parents=True, exist_ok=True)
    
    # 查找所有frame_input图像
    input_files = sorted(input_dir.glob("frame_input*.bmp"))
    
    if not input_files:
        print(f"❌ 在 {input_dir} 中未找到 frame_input*.bmp 文件")
        return
    
    print("=" * 80)
    print(f"OpenCV标准CLAHE参考处理")
    print(f"输入目录: {input_dir}")
    print(f"输出目录: {opencv_output_dir}")
    print(f"Clip Limit: {clip_limit}")
    print(f"Tile Grid: 8x8")
    print("=" * 80)
    print()
    
    success_count = 0
    
    for input_file in input_files:
        # 生成输出文件名（将frame_input替换为frame_opencv）
        output_filename = input_file.name.replace("frame_input", "frame_opencv")
        output_file = opencv_output_dir / output_filename
        
        if process_clahe_opencv(str(input_file), str(output_file), clip_limit):
            success_count += 1
        print()
    
    print("=" * 80)
    print(f"处理完成: {success_count}/{len(input_files)} 个文件")
    print(f"OpenCV输出: {opencv_output_dir}/")
    print(f"硬件输出: {input_dir}/frame_output*.bmp")
    print()
    print("现在可以对比：")
    print("  • frame_input*.bmp           - 原始输入（当前目录）")
    print("  • opencv_reference/*.bmp     - OpenCV标准CLAHE结果")
    print("  • frame_output*.bmp          - 硬件CLAHE结果（当前目录）")
    print("=" * 80)
    
    return opencv_output_dir  # 返回OpenCV输出目录供后续对比使用

def compare_images(opencv_path, hardware_path):
    """
    对比OpenCV结果和硬件结果
    """
    try:
        opencv_pil = Image.open(opencv_path).convert('L')
        hardware_pil = Image.open(hardware_path).convert('L')
        opencv_img = np.array(opencv_pil)
        hardware_img = np.array(hardware_pil)
    except Exception as e:
        print(f"❌ 无法读取对比图像: {e}")
        return
    
    # 计算差异
    diff = cv2.absdiff(opencv_img, hardware_img)
    max_diff = np.max(diff)
    mean_diff = np.mean(diff)
    
    # 统计差异像素
    diff_pixels = np.sum(diff > 0)
    total_pixels = opencv_img.size
    diff_ratio = diff_pixels / total_pixels * 100
    
    print(f"\n对比结果:")
    print(f"  最大差异: {max_diff}")
    print(f"  平均差异: {mean_diff:.2f}")
    print(f"  差异像素: {diff_pixels}/{total_pixels} ({diff_ratio:.2f}%)")
    
    if max_diff == 0:
        print("  ✓ 完全匹配！")
    elif max_diff <= 1:
        print("  ✓ 几乎完全匹配（差异≤1）")
    elif max_diff <= 5:
        print("  ⚠ 小差异（差异≤5）")
    else:
        print("  ❌ 存在明显差异")

if __name__ == "__main__":
    import sys
    
    # 默认使用当前目录（如果在sim_outputs下运行）
    if len(sys.argv) > 1:
        input_dir = sys.argv[1]
    else:
        input_dir = "."  # 当前目录
    
    if len(sys.argv) > 2:
        output_dir = sys.argv[2]
    else:
        output_dir = input_dir  # 输出到同一目录
    
    if len(sys.argv) > 3:
        clip_limit = float(sys.argv[3])
    else:
        clip_limit = 3.0  # 硬件默认值
    
    # 批量处理
    opencv_output_dir = batch_process(input_dir, output_dir, clip_limit)
    
    # 如果存在硬件输出，进行对比
    input_path = Path(input_dir)
    opencv_files = sorted(opencv_output_dir.glob("frame_opencv*.bmp"))
    hardware_files = sorted(input_path.glob("frame_output*.bmp"))
    
    if opencv_files and hardware_files:
        print("\n" + "=" * 80)
        print("对比OpenCV与硬件实现")
        print("=" * 80)
        
        for opencv_file, hardware_file in zip(opencv_files[:3], hardware_files[:3]):  # 只对比前3帧
            print(f"\n帧 {opencv_file.stem.split()[-1]}:")
            compare_images(str(opencv_file), str(hardware_file))

