#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CLAHE CDF Module Golden Reference Verification Script

This script:
1. Reads histogram input data from cdf_input_data.txt
2. Calculates golden CDF values using CLAHE algorithm
3. Reads actual CDF output from cdf_output_data.txt
4. Compares and generates verification report
"""

import numpy as np
import sys
from collections import defaultdict

class CLAHEGoldenModel:
    """CLAHE CDF计算的Golden Reference模型"""
    
    def __init__(self, bins=256, tile_pixels=14400):
        self.bins = bins
        self.tile_pixels = tile_pixels
    
    def calculate_cdf(self, histogram, clip_limit):
        """
        计算CLAHE的CDF值
        
        Args:
            histogram: 输入直方图 (256个bin)
            clip_limit: Clip限制值
            
        Returns:
            归一化的CDF值 (0-255范围)
        """
        # 步骤1: Contrast Limiting (裁剪)
        clipped_hist = np.copy(histogram).astype(np.int32)
        total_excess = 0
        
        for i in range(self.bins):
            if clipped_hist[i] > clip_limit:
                excess = clipped_hist[i] - clip_limit
                total_excess += excess
                clipped_hist[i] = clip_limit
        
        # 步骤2: 重分配超出量（均匀分配到所有bin）
        avg_increment = total_excess // self.bins
        remainder = total_excess % self.bins
        
        for i in range(self.bins):
            clipped_hist[i] += avg_increment
            # 余数分配给前面的bin
            if i < remainder:
                clipped_hist[i] += 1
        
        # 步骤3: 计算CDF（累积分布函数）
        cdf = np.cumsum(clipped_hist)
        
        # 步骤4: 归一化到0-255范围
        # 使用CLAHE标准公式: normalized_cdf = (cdf - cdf_min) * 255 / (total - cdf_min)
        cdf_min = cdf[0]
        
        # 找到第一个非零CDF值
        for i in range(self.bins):
            if cdf[i] > 0:
                cdf_min = cdf[i]
                break
        
        total = cdf[-1]
        
        if total == cdf_min or total == 0:
            # 全零直方图
            normalized_cdf = np.zeros(self.bins, dtype=np.uint8)
        else:
            # 归一化
            normalized_cdf = ((cdf - cdf_min) * 255.0 / (total - cdf_min)).astype(np.uint8)
        
        return normalized_cdf


def read_input_data(filename):
    """
    读取输入直方图数据
    
    Returns:
        dict: {test_id: {tile_id: histogram}}
    """
    data = defaultdict(lambda: defaultdict(lambda: np.zeros(256, dtype=np.int32)))
    
    print(f"Reading input data from {filename}...")
    
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#') or not line:
                continue
            
            parts = line.split()
            if len(parts) != 4:
                continue
            
            try:
                test_id = int(parts[0])
                tile_id = int(parts[1])
                bin_addr = int(parts[2])
                value = int(parts[3])
                
                data[test_id][tile_id][bin_addr] = value
            except ValueError:
                continue
    
    print(f"  Loaded {len(data)} test cases")
    return data


def read_output_data(filename):
    """
    读取实际CDF输出数据
    
    Returns:
        dict: {test_id: {tile_id: {bin_addr: value}}}
    """
    data = defaultdict(lambda: defaultdict(dict))
    
    print(f"Reading output data from {filename}...")
    
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#') or not line:
                continue
            
            parts = line.split()
            if len(parts) != 4:
                continue
            
            try:
                test_id = int(parts[0])
                tile_id = int(parts[1])
                bin_addr = int(parts[2])
                value = int(parts[3])
                
                data[test_id][tile_id][bin_addr] = value
            except ValueError:
                continue
    
    print(f"  Loaded output data for {len(data)} test cases")
    return data


def verify_test(test_id, golden_cdf, actual_output, tile_id=0):
    """
    验证单个测试用例
    
    Returns:
        dict: 验证结果统计
    """
    mismatches = []
    max_error = 0
    
    for bin_addr in range(256):
        golden_val = golden_cdf[bin_addr]
        actual_val = actual_output.get(bin_addr, 0)
        
        if golden_val != actual_val:
            error = abs(int(golden_val) - int(actual_val))
            mismatches.append({
                'bin': bin_addr,
                'golden': golden_val,
                'actual': actual_val,
                'error': error
            })
            max_error = max(max_error, error)
    
    return {
        'total_bins': 256,
        'mismatches': len(mismatches),
        'match_rate': (256 - len(mismatches)) / 256 * 100,
        'max_error': max_error,
        'mismatch_details': mismatches[:10]  # 只保留前10个
    }


def main():
    """主验证流程"""
    
    print("=" * 80)
    print("CLAHE CDF Module - Golden Reference Verification")
    print("=" * 80)
    print()
    
    # 读取数据
    input_data = read_input_data('cdf_input_data.txt')
    output_data = read_output_data('cdf_output_data.txt')
    
    # 创建Golden模型
    golden_model = CLAHEGoldenModel()
    
    # 默认clip_limit (根据testbench)
    clip_limits = {
        1: 500,   # Test 1-6
        2: 500,
        3: 500,
        4: 500,
        5: 500,
        6: 500,
        7: 10000, # Test 7.1: 极高clip_limit
        8: 500,   # Test 8
        9: 500,   # Test 9
    }
    
    # 验证每个测试用例
    total_tests = 0
    passed_tests = 0
    acceptable_tests = 0
    failed_tests = 0
    
    print()
    print("=" * 80)
    print("Verification Results")
    print("=" * 80)
    
    for test_id in sorted(input_data.keys()):
        if test_id not in output_data:
            print(f"\n[WARNING] Test {test_id}: No output data found, skipping...")
            continue
        
        for tile_id in sorted(input_data[test_id].keys()):
            if tile_id not in output_data[test_id]:
                continue
            
            # 获取clip_limit
            clip_limit = clip_limits.get(test_id, 500)
            
            # 计算Golden CDF
            histogram = input_data[test_id][tile_id]
            golden_cdf = golden_model.calculate_cdf(histogram, clip_limit)
            
            # 验证
            result = verify_test(test_id, golden_cdf, output_data[test_id][tile_id], tile_id)
            
            total_tests += 1
            
            # 打印结果
            print(f"\n[Test {test_id}, Tile {tile_id}]")
            print(f"  Clip Limit        : {clip_limit}")
            print(f"  Total bins checked: {result['total_bins']}")
            print(f"  Mismatches found  : {result['mismatches']}")
            print(f"  Match rate        : {result['match_rate']:.2f}%")
            print(f"  Maximum error     : {result['max_error']}")
            
            # 显示不匹配的详细信息
            if result['mismatches'] > 0 and len(result['mismatch_details']) > 0:
                print(f"  First mismatches:")
                for detail in result['mismatch_details'][:5]:
                    print(f"    Bin[{detail['bin']:3d}]: Got {detail['actual']:3d}, "
                          f"Expected {detail['golden']:3d}, Error = {detail['error']:3d}")
            
            # 判定结果
            if result['mismatches'] == 0:
                print(f"  Status            : ✓ PASS - Perfect match!")
                passed_tests += 1
            elif result['max_error'] <= 1:
                print(f"  Status            : ⚠ ACCEPTABLE - Small rounding errors only")
                acceptable_tests += 1
            else:
                print(f"  Status            : ✗ FAIL - Significant errors detected")
                failed_tests += 1
    
    # 总结
    print()
    print("=" * 80)
    print("Final Summary")
    print("=" * 80)
    print(f"Total tests       : {total_tests}")
    print(f"Perfect matches   : {passed_tests} ({passed_tests/total_tests*100:.1f}%)")
    print(f"Acceptable (≤1err): {acceptable_tests} ({acceptable_tests/total_tests*100:.1f}%)")
    print(f"Failed            : {failed_tests} ({failed_tests/total_tests*100:.1f}%)")
    print()
    
    if failed_tests == 0:
        print("✓ ALL TESTS PASSED!")
        print("=" * 80)
        return 0
    else:
        print("✗ SOME TESTS FAILED - Please review the errors above")
        print("=" * 80)
        return 1


if __name__ == '__main__':
    sys.exit(main())

