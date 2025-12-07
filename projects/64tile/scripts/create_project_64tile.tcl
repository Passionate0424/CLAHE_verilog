# Vivado Project Creation Script for CLAHE 64-Tile Version
# usage: vivado -mode batch -source create_project_64tile.tcl

# Set project name and directory
set _xil_proj_name_ "clahe_vivado_64t"
# We create the project in the same parent directory as the 16tile one for consistency, or a new parallel one.
# Let's put it in e:/FPGA_codes/CLAHE/vivado_project/clahe_vivado_64t
set _xil_proj_dir_ "e:/FPGA_codes/CLAHE/vivado_project/clahe_vivado_64t"

# Create project
create_project ${_xil_proj_name_} ${_xil_proj_dir_} -part xc7z020clg400-3 -force

# Set project properties
set obj [get_projects ${_xil_proj_name_}]
set_property -name "default_lib" -value "xil_defaultlib" -objects $obj
set_property -name "sim.ip.auto_export_scripts" -value "1" -objects $obj
set_property -name "simulator_language" -value "Mixed" -objects $obj
set_property -name "target_language" -value "Verilog" -objects $obj

# Add RTL sources
# 64tile RTL files
add_files -norecurse -scan_for_includes "e:/FPGA_codes/CLAHE/projects/64tile/rtl"

# Add XDC constraints
# Using the same simulation-only XDC as 16tile since pinout likely isn't defined yet or is the same
add_files -fileset constrs_1 -norecurse "e:/FPGA_codes/CLAHE/vivado_project/clahe_vivado/clahe_vivado.srcs/constrs_1/imports/clahe_top_sim.xdc"

# Set top module
set_property top clahe_top [current_fileset]

# Set simulation settings (optional, setting sim_1 top)
set_property top tb_clahe_top_bmp_multi [get_filesets sim_1]
# Note: We need to add the testbench files if we want simulation to work out-of-the-box
# The 16tile project uses:
# - tb/bmp_for_videoStream_24bit.sv
# - tb/bmp_to_videoStream.sv
# - tb/tb_clahe_top_bmp_multi.sv
# We'll add these from the common locations or project specific if they differ.
# Assuming 16tile TB files are generic enough or we use the ones from 16tile project for now.
# However, 64tile might have different TB structure.
# Let's check projects/64tile/tb/ first? No, list_dir showed no 'tb' folder in 'projects/64tile'.
# Use 16tile TB for now as reference, user can adjust.
add_files -fileset sim_1 -norecurse "e:/FPGA_codes/CLAHE/projects/16tile/tb/bmp_for_videoStream_24bit.sv"
add_files -fileset sim_1 -norecurse "e:/FPGA_codes/CLAHE/projects/16tile/tb/bmp_to_videoStream.sv"
add_files -fileset sim_1 -norecurse "e:/FPGA_codes/CLAHE/projects/16tile/tb/tb_clahe_top_bmp_multi.sv"

puts "Project ${_xil_proj_name_} created successfully in ${_xil_proj_dir_}"
