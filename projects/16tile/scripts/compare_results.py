#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
对比修复前后的CLAHE图像效果
检查分块效应是否消除
"""

import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['SimHei']
matplotlib.rcParams['axes.unicode_minus'] = False

def load_image(path):
    """加载BMP图像"""
    try:
        img = Image.open(path)
        return np.array(img)
    except Exception as e:
        print(f"无法加载图像 {path}: {e}")
        return None

def detect_blocking_artifacts(img, tile_size=(320, 180)):
    """检测分块效应 - 计算tile边界处的梯度"""
    if len(img.shape) == 3:
        # 转换为灰度
        gray = np.mean(img, axis=2).astype(np.uint8)
    else:
        gray = img
    
    h, w = gray.shape
    tile_w, tile_h = tile_size
    
    # 检测垂直边界 (X方向)
    v_boundaries = []
    for x in range(tile_w, w, tile_w):
        if x < w - 1:
            # 计算边界两侧的梯度
            left = gray[:, max(0, x-2):x]
            right = gray[:, x:min(w, x+2)]
            if left.size > 0 and right.size > 0:
                gradient = np.abs(np.mean(right) - np.mean(left))
                v_boundaries.append((x, gradient))
    
    # 检测水平边界 (Y方向)
    h_boundaries = []
    for y in range(tile_h, h, tile_h):
        if y < h - 1:
            # 计算边界两侧的梯度
            top = gray[max(0, y-2):y, :]
            bottom = gray[y:min(h, y+2), :]
            if top.size > 0 and bottom.size > 0:
                gradient = np.abs(np.mean(bottom) - np.mean(top))
                h_boundaries.append((y, gradient))
    
    return v_boundaries, h_boundaries, gray

def compare_images():
    """对比修复前后的图像"""
    print("=" * 80)
    print("CLAHE分块效应修复效果对比")
    print("=" * 80)
    
    # 加载图像 (使用Frame 1，因为它应用了CLAHE增强)
    output_path = "bmp_test_results/output/output_frame 1.bmp"
    
    img_fixed = load_image(output_path)
    
    if img_fixed is None:
        print("无法加载修复后的图像！")
        return
    
    print(f"\n图像尺寸: {img_fixed.shape}")
    
    # 检测分块效应
    print("\n【修复后图像的分块效应分析】")
    v_bounds, h_bounds, gray = detect_blocking_artifacts(img_fixed)
    
    print(f"\n垂直Tile边界 (X方向):")
    print(f"位置(X) | 边界梯度")
    print("-" * 40)
    avg_v_gradient = 0
    for x, grad in v_bounds:
        print(f"  {x:4d}  |   {grad:6.2f}")
        avg_v_gradient += grad
    if len(v_bounds) > 0:
        avg_v_gradient /= len(v_bounds)
        print(f"\n平均垂直边界梯度: {avg_v_gradient:.2f}")
    
    print(f"\n水平Tile边界 (Y方向):")
    print(f"位置(Y) | 边界梯度")
    print("-" * 40)
    avg_h_gradient = 0
    for y, grad in h_bounds:
        print(f"  {y:4d}  |   {grad:6.2f}")
        avg_h_gradient += grad
    if len(h_bounds) > 0:
        avg_h_gradient /= len(h_bounds)
        print(f"\n平均水平边界梯度: {avg_h_gradient:.2f}")
    
    # 可视化
    fig, axes = plt.subplots(2, 3, figsize=(18, 12))
    
    # 显示完整图像
    axes[0, 0].imshow(img_fixed)
    axes[0, 0].set_title('修复后的输出图像 (Frame 1)', fontsize=14, fontweight='bold')
    axes[0, 0].axis('off')
    
    # 添加tile边界线
    h, w = gray.shape
    for x in range(320, w, 320):
        axes[0, 0].axvline(x, color='r', linewidth=1, alpha=0.5)
    for y in range(180, h, 180):
        axes[0, 0].axhline(y, color='r', linewidth=1, alpha=0.5)
    
    # 显示灰度图
    axes[0, 1].imshow(gray, cmap='gray')
    axes[0, 1].set_title('灰度图 (检查分块效应)', fontsize=14)
    axes[0, 1].axis('off')
    for x in range(320, w, 320):
        axes[0, 1].axvline(x, color='r', linewidth=1, alpha=0.5)
    for y in range(180, h, 180):
        axes[0, 1].axhline(y, color='r', linewidth=1, alpha=0.5)
    
    # 放大显示tile边界区域 (X=320附近)
    x_center = 320
    y_center = 360
    crop_size = 100
    crop = gray[y_center-crop_size:y_center+crop_size, 
                x_center-crop_size:x_center+crop_size]
    axes[0, 2].imshow(crop, cmap='gray')
    axes[0, 2].axvline(crop_size, color='r', linewidth=2, label='Tile边界')
    axes[0, 2].set_title(f'Tile边界放大 (X={x_center})', fontsize=14)
    axes[0, 2].legend()
    axes[0, 2].grid(True, alpha=0.3)
    
    # 绘制X方向的梯度分布 (跨越tile边界)
    if len(gray.shape) == 2:
        row = gray[h//2, :]  # 取中间一行
    else:
        row = gray[h//2, :, 0]
    
    axes[1, 0].plot(row, linewidth=1)
    for x in range(320, w, 320):
        axes[1, 0].axvline(x, color='r', linestyle='--', linewidth=2, alpha=0.7)
    axes[1, 0].set_xlabel('像素X坐标')
    axes[1, 0].set_ylabel('亮度值')
    axes[1, 0].set_title('X方向亮度分布 (中间行)', fontsize=14)
    axes[1, 0].grid(True, alpha=0.3)
    
    # X方向梯度
    gradient_x = np.abs(np.diff(row.astype(float)))
    axes[1, 1].plot(gradient_x, linewidth=1, color='g')
    for x in range(320, w, 320):
        axes[1, 1].axvline(x, color='r', linestyle='--', linewidth=2, alpha=0.7, label='Tile边界' if x == 320 else '')
    axes[1, 1].set_xlabel('像素X坐标')
    axes[1, 1].set_ylabel('梯度 |ΔY|')
    axes[1, 1].set_title('X方向梯度 (检测突变)', fontsize=14)
    axes[1, 1].legend()
    axes[1, 1].grid(True, alpha=0.3)
    
    # 绘制tile边界处的梯度统计
    boundary_pos = [x for x, _ in v_bounds] + [y for y, _ in h_bounds]
    boundary_grad = [g for _, g in v_bounds] + [g for _, g in h_bounds]
    boundary_type = ['垂直']*len(v_bounds) + ['水平']*len(h_bounds)
    
    colors = ['blue' if t == '垂直' else 'green' for t in boundary_type]
    axes[1, 2].bar(range(len(boundary_grad)), boundary_grad, color=colors, alpha=0.7)
    axes[1, 2].set_xlabel('Tile边界序号')
    axes[1, 2].set_ylabel('边界梯度')
    axes[1, 2].set_title('所有Tile边界的梯度统计', fontsize=14)
    axes[1, 2].axhline(10, color='r', linestyle='--', linewidth=2, label='阈值=10')
    axes[1, 2].legend()
    axes[1, 2].grid(True, alpha=0.3, axis='y')
    
    plt.tight_layout()
    plt.savefig('blocking_artifact_analysis.png', dpi=150, bbox_inches='tight')
    print("\n分析结果图已保存: blocking_artifact_analysis.png")
    
    # 评估修复效果
    print("\n" + "=" * 80)
    print("【修复效果评估】")
    print("=" * 80)
    
    avg_gradient = (avg_v_gradient + avg_h_gradient) / 2
    
    print(f"\n平均Tile边界梯度: {avg_gradient:.2f}")
    
    if avg_gradient < 5:
        status = "✓ 优秀 - 分块效应基本消除"
        color = "绿色"
    elif avg_gradient < 10:
        status = "✓ 良好 - 分块效应显著减轻"
        color = "黄色"
    elif avg_gradient < 20:
        status = "⚠ 中等 - 仍有轻微分块效应"
        color = "橙色"
    else:
        status = "✗ 较差 - 分块效应明显"
        color = "红色"
    
    print(f"状态: {status} ({color})")
    print(f"\n说明:")
    print(f"  - 梯度 < 5:  分块效应不可见")
    print(f"  - 梯度 5-10: 分块效应轻微，肉眼难以察觉")
    print(f"  - 梯度 10-20: 分块效应可见但可接受")
    print(f"  - 梯度 > 20:  分块效应明显")
    print("=" * 80)

if __name__ == "__main__":
    compare_images()
    print("\n分析完成！请查看生成的图像文件。")




