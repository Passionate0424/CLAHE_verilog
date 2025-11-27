#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CLAHE插值权重验证脚本
检查权重计算和插值效果
"""

import numpy as np
import matplotlib.pyplot as plt

# 常量定义
TILE_WIDTH = 320
TILE_HEIGHT = 180
TILE_CENTER_X = 160
TILE_CENTER_Y = 90

def calc_weight_verilog(local_coord, is_x_axis):
    """
    模拟Verilog中的权重计算
    """
    if is_x_axis:
        # wx = (local_x * 819) >> 10
        mult = local_coord * 819
        wx = (mult >> 10) & 0xFF
        return wx
    else:
        # wy = (local_y * 1456) >> 10
        mult = local_coord * 1456
        wy = (mult >> 10) & 0xFF
        return wy

def calc_weight_ideal(local_coord, tile_size):
    """
    理想的权重计算 (浮点)
    """
    return int((local_coord * 256) / tile_size)

def analyze_weights():
    """分析权重计算的精度"""
    print("=" * 80)
    print("CLAHE插值权重分析")
    print("=" * 80)
    
    # X方向权重分析
    print("\n【X方向权重 (wx)】")
    print(f"Tile宽度: {TILE_WIDTH}, 中心: {TILE_CENTER_X}")
    print(f"公式: wx = (local_x * 819) >> 10")
    print(f"\nlocal_x | Verilog wx | 理想 wx | 误差 | 相对误差")
    print("-" * 60)
    
    x_samples = [0, 40, 80, 120, 160, 200, 240, 280, 319]
    max_x_error = 0
    
    for local_x in x_samples:
        wx_verilog = calc_weight_verilog(local_x, True)
        wx_ideal = calc_weight_ideal(local_x, TILE_WIDTH)
        error = abs(wx_verilog - wx_ideal)
        rel_error = (error / 256) * 100 if wx_ideal > 0 else 0
        max_x_error = max(max_x_error, error)
        print(f"  {local_x:3d}   |    {wx_verilog:3d}    |   {wx_ideal:3d}   |  {error:2d}  | {rel_error:5.2f}%")
    
    print(f"\n最大误差: {max_x_error}, 相对误差: {(max_x_error/256)*100:.2f}%")
    
    # Y方向权重分析
    print("\n【Y方向权重 (wy)】")
    print(f"Tile高度: {TILE_HEIGHT}, 中心: {TILE_CENTER_Y}")
    print(f"公式: wy = (local_y * 1456) >> 10")
    print(f"\nlocal_y | Verilog wy | 理想 wy | 误差 | 相对误差")
    print("-" * 60)
    
    y_samples = [0, 30, 60, 90, 120, 150, 179]
    max_y_error = 0
    
    for local_y in y_samples:
        wy_verilog = calc_weight_verilog(local_y, False)
        wy_ideal = calc_weight_ideal(local_y, TILE_HEIGHT)
        error = abs(wy_verilog - wy_ideal)
        rel_error = (error / 256) * 100 if wy_ideal > 0 else 0
        max_y_error = max(max_y_error, error)
        print(f"  {local_y:3d}   |    {wy_verilog:3d}    |   {wy_ideal:3d}   |  {error:2d}  | {rel_error:5.2f}%")
    
    print(f"\n最大误差: {max_y_error}, 相对误差: {(max_y_error/256)*100:.2f}%")

def visualize_weights():
    """可视化权重分布"""
    # X方向权重
    local_x = np.arange(0, TILE_WIDTH)
    wx_verilog = np.array([calc_weight_verilog(x, True) for x in local_x])
    wx_ideal = np.array([calc_weight_ideal(x, TILE_WIDTH) for x in local_x])
    
    # Y方向权重
    local_y = np.arange(0, TILE_HEIGHT)
    wy_verilog = np.array([calc_weight_verilog(y, False) for y in local_y])
    wy_ideal = np.array([calc_weight_ideal(y, TILE_HEIGHT) for y in local_y])
    
    # 绘图
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    
    # X方向权重曲线
    axes[0, 0].plot(local_x, wx_ideal, 'b-', label='理想权重', linewidth=2)
    axes[0, 0].plot(local_x, wx_verilog, 'r--', label='Verilog权重', linewidth=1)
    axes[0, 0].axvline(TILE_CENTER_X, color='g', linestyle=':', label='Tile中心')
    axes[0, 0].set_xlabel('local_x')
    axes[0, 0].set_ylabel('wx')
    axes[0, 0].set_title('X方向插值权重')
    axes[0, 0].legend()
    axes[0, 0].grid(True)
    
    # X方向权重误差
    axes[0, 1].plot(local_x, wx_verilog - wx_ideal, 'r-', linewidth=2)
    axes[0, 1].axhline(0, color='k', linestyle='-', linewidth=0.5)
    axes[0, 1].axvline(TILE_CENTER_X, color='g', linestyle=':', label='Tile中心')
    axes[0, 1].set_xlabel('local_x')
    axes[0, 1].set_ylabel('误差')
    axes[0, 1].set_title('X方向权重误差')
    axes[0, 1].grid(True)
    
    # Y方向权重曲线
    axes[1, 0].plot(local_y, wy_ideal, 'b-', label='理想权重', linewidth=2)
    axes[1, 0].plot(local_y, wy_verilog, 'r--', label='Verilog权重', linewidth=1)
    axes[1, 0].axvline(TILE_CENTER_Y, color='g', linestyle=':', label='Tile中心')
    axes[1, 0].set_xlabel('local_y')
    axes[1, 0].set_ylabel('wy')
    axes[1, 0].set_title('Y方向插值权重')
    axes[1, 0].legend()
    axes[1, 0].grid(True)
    
    # Y方向权重误差
    axes[1, 1].plot(local_y, wy_verilog - wy_ideal, 'r-', linewidth=2)
    axes[1, 1].axhline(0, color='k', linestyle='-', linewidth=0.5)
    axes[1, 1].axvline(TILE_CENTER_Y, color='g', linestyle=':', label='Tile中心')
    axes[1, 1].set_xlabel('local_y')
    axes[1, 1].set_ylabel('误差')
    axes[1, 1].set_title('Y方向权重误差')
    axes[1, 1].grid(True)
    
    plt.tight_layout()
    plt.savefig('weight_analysis.png', dpi=150)
    print("\n权重分析图已保存到: weight_analysis.png")

def test_bilinear_interp():
    """测试双线性插值效果"""
    print("\n" + "=" * 80)
    print("双线性插值测试")
    print("=" * 80)
    
    # 模拟4个tile的CDF值（假设不同的增强程度）
    cdf_tl = 100  # 左上tile
    cdf_tr = 150  # 右上tile
    cdf_bl = 120  # 左下tile
    cdf_br = 180  # 右下tile
    
    print(f"\n假设4个tile的CDF值:")
    print(f"  左上(TL): {cdf_tl}")
    print(f"  右上(TR): {cdf_tr}")
    print(f"  左下(BL): {cdf_bl}")
    print(f"  右下(BR): {cdf_br}")
    
    # 测试不同位置的插值结果
    test_positions = [
        (0, 0, "左上角"),
        (160, 90, "Tile中心"),
        (319, 179, "右下角"),
        (80, 45, "左上象限"),
        (240, 135, "右下象限"),
    ]
    
    print(f"\n位置测试:")
    print(f"local_x, local_y | wx  | wy  | 插值结果 | 说明")
    print("-" * 70)
    
    for local_x, local_y, desc in test_positions:
        wx = calc_weight_verilog(local_x, True)
        wy = calc_weight_verilog(local_y, False)
        
        # 横向插值
        interp_top = ((256 - wx) * cdf_tl + wx * cdf_tr) >> 8
        interp_bottom = ((256 - wx) * cdf_bl + wx * cdf_br) >> 8
        
        # 纵向插值
        result = ((256 - wy) * interp_top + wy * interp_bottom) >> 8
        
        print(f"  ({local_x:3d}, {local_y:3d})  | {wx:3d} | {wy:3d} |   {result:5.1f}   | {desc}")

def check_tile_boundary():
    """检查tile边界附近的插值效果"""
    print("\n" + "=" * 80)
    print("Tile边界插值检查")
    print("=" * 80)
    
    # 检查X=320边界(tile 0和tile 1的交界)
    print("\n【X方向边界 (local_x = 319 -> 0)】")
    print("位置 | tile_x | local_x | wx  | 说明")
    print("-" * 60)
    
    positions_x = [
        (318, 0, 318),
        (319, 0, 319),
        (320, 1, 0),
        (321, 1, 1),
    ]
    
    for pixel_x, tile_x, local_x in positions_x:
        wx = calc_weight_verilog(local_x, True)
        print(f" {pixel_x:4d} |   {tile_x}    |  {local_x:3d}   | {wx:3d} | {'边界前' if local_x > 310 else '边界后' if local_x < 10 else '正常'}")
    
    # 检查Y=180边界
    print("\n【Y方向边界 (local_y = 179 -> 0)】")
    print("位置 | tile_y | local_y | wy  | 说明")
    print("-" * 60)
    
    positions_y = [
        (178, 0, 178),
        (179, 0, 179),
        (180, 1, 0),
        (181, 1, 1),
    ]
    
    for pixel_y, tile_y, local_y in positions_y:
        wy = calc_weight_verilog(local_y, False)
        print(f" {pixel_y:4d} |   {tile_y}    |  {local_y:3d}   | {wy:3d} | {'边界前' if local_y > 170 else '边界后' if local_y < 10 else '正常'}")

if __name__ == "__main__":
    analyze_weights()
    check_tile_boundary()
    test_bilinear_interp()
    visualize_weights()
    
    print("\n" + "=" * 80)
    print("分析完成！")
    print("=" * 80)

