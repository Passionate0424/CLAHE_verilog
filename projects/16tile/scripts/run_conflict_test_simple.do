# 简化的冲突测试脚本
vlib work
vlog clahe_histogram_stat_v2.v
vlog tb/tb_histogram_conflict_test.v
vsim -c work.tb_histogram_conflict_test -do "run -all; quit"

