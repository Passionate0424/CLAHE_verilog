from PIL import Image
import numpy as np

for i in range(6):
    inp = Image.open(f'bmp_test_results/input/input_frame {i}.bmp')
    out = Image.open(f'bmp_test_results/output/output_frame {i}.bmp')
    inp_arr = np.array(inp)
    out_arr = np.array(out)
    print(f'Frame {i}: Input Mean={inp_arr.mean():.1f}, Output Mean={out_arr.mean():.1f}, Ratio={out_arr.mean()/inp_arr.mean():.3f}')


