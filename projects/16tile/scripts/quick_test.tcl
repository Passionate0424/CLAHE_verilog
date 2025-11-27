# 快速测试脚本 - 只运行前40ms（约前2帧）
vsim -voptargs=+acc work.tb_clahe_top
run 40ms
quit -f




