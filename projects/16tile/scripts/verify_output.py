import numpy as np
from PIL import Image
import os

print("=" * 60)
print("CLAHE Output Image Analysis")
print("=" * 60)

output_dir = "bmp_test_results/output"

for i in range(6):
    filename = f"output_frame {i}.bmp"
    filepath = os.path.join(output_dir, filename)
    
    if not os.path.exists(filepath):
        print(f"\n[Frame {i}] File not found: {filename}")
        continue
    
    try:
        img = Image.open(filepath)
        img_array = np.array(img)
        
        # 统计信息
        if len(img_array.shape) == 3:
            # RGB图像
            r, g, b = img_array[:,:,0], img_array[:,:,1], img_array[:,:,2]
            y = 0.299 * r + 0.587 * g + 0.114 * b  # 转换为亮度
        else:
            # 灰度图像
            y = img_array
        
        total_pixels = y.size
        zero_pixels = np.sum(y == 0)
        nonzero_pixels = total_pixels - zero_pixels
        
        print(f"\n[Frame {i}] {filename}")
        print(f"  Size: {img.size}")
        print(f"  Mode: {img.mode}")
        print(f"  Total pixels: {total_pixels}")
        print(f"  Zero pixels: {zero_pixels} ({100*zero_pixels/total_pixels:.2f}%)")
        print(f"  Non-zero pixels: {nonzero_pixels} ({100*nonzero_pixels/total_pixels:.2f}%)")
        print(f"  Min/Max/Mean: {y.min():.1f} / {y.max():.1f} / {y.mean():.1f}")
        print(f"  Std Dev: {y.std():.2f}")
        
        # 采样几个像素值
        if nonzero_pixels > 0:
            sample_indices = np.where(y > 0)
            if len(sample_indices[0]) > 0:
                sample_y = sample_indices[0][:5]
                sample_x = sample_indices[1][:5]
                print(f"  First 5 non-zero pixels:")
                for sy, sx in zip(sample_y, sample_x):
                    print(f"    ({sy},{sx}): Y={y[sy,sx]:.0f}")
        
    except Exception as e:
        print(f"\n[Frame {i}] Error reading {filename}: {e}")

print("\n" + "=" * 60)
print("Analysis Complete")
print("=" * 60)
