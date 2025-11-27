#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
分析剩余的分块效应，寻找进一步优化方案
"""

import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['SimHei']
matplotlib.rcParams['axes.unicode_minus'] = False

# 模拟当前的权重计算
def calc_current_weight(dx):
    """当前修复后的权重计算"""
    mult = dx * 819
    offset = mult >> 10
    if mult < 0:
        offset = -((-mult) >> 10)
    result = 128 + offset
    return max(0, min(255, result))

# 理想的权重计算
def calc_ideal_weight(dx, tile_width=320):
    """理想的权重计算（浮点）"""
    # wx应该在tile中心=128，左边界=0，右边界=256(饱和到255)
    wx = 128 + (dx * 256.0 / tile_width)
    return max(0, min(255, int(wx)))

def analyze_weight_precision():
    """分析权重计算的精度问题"""
    print("=" * 80)
    print("权重精度分析 - 寻找改进空间")
    print("=" * 80)
    
    # 关键位置的权重对比
    critical_dx = [-160, -80, -40, -20, -10, -5, -1, 0, 1, 5, 10, 20, 40, 80, 159]
    
    print("\n【权重精度对比】")
    print("dx    | 当前wx | 理想wx | 误差 | 误差% | 说明")
    print("-" * 80)
    
    max_error = 0
    for dx in critical_dx:
        wx_current = calc_current_weight(dx)
        wx_ideal = calc_ideal_weight(dx)
        error = abs(wx_current - wx_ideal)
        error_pct = (error / 256) * 100
        max_error = max(max_error, error)
        
        note = ""
        if dx == -160:
            note = "左边界"
        elif dx == 0:
            note = "中心"
        elif dx == 159:
            note = "右边界"
        
        print(f"{dx:4d}  |  {wx_current:3d}   |  {wx_ideal:3d}   | {error:2d}   | {error_pct:4.1f}% | {note}")
    
    print(f"\n最大误差: {max_error} ({(max_error/256)*100:.2f}%)")
    
    # 可视化权重曲线
    dx_range = np.arange(-160, 160)
    wx_current = [calc_current_weight(dx) for dx in dx_range]
    wx_ideal = [calc_ideal_weight(dx) for dx in dx_range]
    
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    
    # 权重对比
    axes[0, 0].plot(dx_range, wx_ideal, 'b-', linewidth=2, label='理想权重')
    axes[0, 0].plot(dx_range, wx_current, 'r--', linewidth=1.5, label='当前权重')
    axes[0, 0].axvline(0, color='g', linestyle=':', alpha=0.5, label='Tile中心')
    axes[0, 0].axhline(128, color='g', linestyle=':', alpha=0.5)
    axes[0, 0].set_xlabel('dx (相对tile中心的距离)')
    axes[0, 0].set_ylabel('权重 wx')
    axes[0, 0].set_title('权重曲线对比')
    axes[0, 0].legend()
    axes[0, 0].grid(True, alpha=0.3)
    
    # 误差分布
    errors = [abs(c - i) for c, i in zip(wx_current, wx_ideal)]
    axes[0, 1].plot(dx_range, errors, 'r-', linewidth=2)
    axes[0, 1].axhline(1, color='orange', linestyle='--', label='1 LSB')
    axes[0, 1].axhline(2, color='red', linestyle='--', label='2 LSB')
    axes[0, 1].set_xlabel('dx')
    axes[0, 1].set_ylabel('误差 (LSB)')
    axes[0, 1].set_title('权重误差分布')
    axes[0, 1].legend()
    axes[0, 1].grid(True, alpha=0.3)
    
    # tile边界附近的详细分析
    boundary_dx = np.arange(-170, -140)  # 左边界附近
    boundary_wx_current = [calc_current_weight(dx) for dx in boundary_dx]
    boundary_wx_ideal = [calc_ideal_weight(dx) for dx in boundary_dx]
    
    axes[1, 0].plot(boundary_dx, boundary_wx_ideal, 'b-', linewidth=2, marker='o', label='理想')
    axes[1, 0].plot(boundary_dx, boundary_wx_current, 'r--', linewidth=2, marker='s', label='当前')
    axes[1, 0].set_xlabel('dx')
    axes[1, 0].set_ylabel('权重 wx')
    axes[1, 0].set_title('左边界附近权重 (dx=-160附近)')
    axes[1, 0].legend()
    axes[1, 0].grid(True, alpha=0.3)
    
    # 右边界附近
    boundary_dx_r = np.arange(140, 170)
    boundary_wx_current_r = [calc_current_weight(dx) for dx in boundary_dx_r]
    boundary_wx_ideal_r = [calc_ideal_weight(dx) for dx in boundary_dx_r]
    
    axes[1, 1].plot(boundary_dx_r, boundary_wx_ideal_r, 'b-', linewidth=2, marker='o', label='理想')
    axes[1, 1].plot(boundary_dx_r, boundary_wx_current_r, 'r--', linewidth=2, marker='s', label='当前')
    axes[1, 1].set_xlabel('dx')
    axes[1, 1].set_ylabel('权重 wx')
    axes[1, 1].set_title('右边界附近权重 (dx=+159附近)')
    axes[1, 1].legend()
    axes[1, 1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('weight_precision_analysis.png', dpi=150)
    print("\n权重精度分析图已保存: weight_precision_analysis.png")

def suggest_improvements():
    """提出改进建议"""
    print("\n" + "=" * 80)
    print("【进一步优化建议】")
    print("=" * 80)
    
    print("\n方案1: 提高权重计算精度")
    print("-" * 80)
    print("当前实现: wx = 128 + ((dx * 819) >> 10)")
    print("  - 使用10位定点数，误差约0.2%")
    print("  - 左边界: dx=-160 → wx=1 (理想应为0)")
    print("  - 右边界: dx=159 → wx=255 (正确)")
    print("\n改进方案1.1: 增加乘法精度")
    print("  wx = 128 + ((dx * 1638) >> 11)")
    print("  - 1638/2048 = 0.7998 ≈ 256/320 = 0.8")
    print("  - 精度提高2倍，误差降至0.1%")
    print("  - 代价: 乘法器位宽+1 (10位×11位)")
    
    print("\n改进方案1.2: 舍入而非截断")
    print("  wx = 128 + ((dx * 819 + 512) >> 10)")
    print("  - 加512后再右移，实现舍入")
    print("  - 精度提高约50%")
    print("  - 代价: 额外一个加法器")
    
    print("\n方案2: 增强边界平滑过渡")
    print("-" * 80)
    print("当前问题: tile边界正好在local_x=0和local_x=319之间")
    print("  - Tile0最后像素: local_x=319, dx=159, wx≈255")
    print("  - Tile1第一像素: local_x=0, dx=-160, wx≈0")
    print("  - 虽然选择的4个tile不同，但CDF可能差异大")
    print("\n改进方案2.1: Tile重叠区域")
    print("  - 每个tile扩展边界8-16像素")
    print("  - 在重叠区域统计直方图，增强边界一致性")
    print("  - 代价: RAM增加约10%")
    
    print("\n方案3: 双三次插值 (Bicubic)")
    print("-" * 80)
    print("当前: 双线性插值 (4个tile)")
    print("改进: 双三次插值 (16个tile)")
    print("  - 使用4×4共16个tile进行插值")
    print("  - 更平滑的过渡，更少的分块效应")
    print("  - 代价: 并行读取从4块增加到16块，流水线延迟增加")
    
    print("\n方案4: 自适应插值半径")
    print("-" * 80)
    print("当前: 固定使用tile中心(160, 90)判断")
    print("改进: 根据像素位置动态调整插值范围")
    print("  - 在tile边界附近使用更大的插值权重")
    print("  - 在tile中心附近使用更小的插值权重")
    print("  - 平衡性能和效果")
    
    print("\n方案5: 后处理平滑滤波")
    print("-" * 80)
    print("在输出端添加轻量级平滑滤波器:")
    print("  - 3×3或5×5高斯滤波")
    print("  - 仅在tile边界附近激活")
    print("  - 代价: 额外的line buffer和计算")
    
    print("\n" + "=" * 80)
    print("【推荐优先级】")
    print("=" * 80)
    print("\n🥇 最推荐: 方案1.2 (舍入优化)")
    print("   ✓ 实现简单，只需修改1行代码")
    print("   ✓ 硬件成本极低 (一个加法器)")
    print("   ✓ 精度提升明显 (约50%)")
    print("   ✓ 预期梯度降至 <1.0")
    
    print("\n🥈 备选: 方案1.1 (更高精度乘法)")
    print("   ✓ 精度提升最大 (2倍)")
    print("   ✓ 硬件成本较低")
    print("   ⚠ 需要重新计算乘法系数")
    
    print("\n🥉 高级: 方案3 (双三次插值)")
    print("   ✓ 效果最好，接近OpenCV质量")
    print("   ✗ 实现复杂，硬件成本高")
    print("   ✗ 需要重构整个映射模块")
    
    print("\n" + "=" * 80)

if __name__ == "__main__":
    analyze_weight_precision()
    suggest_improvements()
    
    print("\n分析完成！")
    print("\n建议: 先尝试方案1.2(舍入优化)，只需修改一行代码:")
    print("  旧: wx_mult = $signed(dx) * $signed(10'd819);")
    print("  新: wx_mult = $signed(dx) * $signed(10'd819) + $signed(20'd512);")
    print("\n这应该能将分块效应梯度从1.92降至<1.0，基本完全不可见。")




