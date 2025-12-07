# Vivado Project Copy Script for CLAHE 64-Tile Version
# usage: source e:/FPGA_codes/CLAHE/projects/64tile/scripts/copy_project_64tile.tcl

set origin_xpr "e:/FPGA_codes/CLAHE/vivado_project/clahe_vivado/clahe_vivado.xpr"
set new_proj_name "clahe_vivado_64t"
# Directory for the new project
set new_proj_dir "e:/FPGA_codes/CLAHE/vivado_project/clahe_vivado_64t"

# 1. Open original project
puts "Opening 16-tile project: $origin_xpr"
open_project $origin_xpr

# 2. Save as new project
puts "Saving as new project: $new_proj_name in $new_proj_dir"
save_project_as $new_proj_name $new_proj_dir -force

# 3. Clean up 16-tile specific files
# Aggressively remove ALL files from sources_1 and sim_1 to ensure a clean slate
puts "Removing ALL existing source and simulation files..."
# Get all files in sources_1
set src_files [get_files -of_objects [get_filesets sources_1] -quiet]
if {[llength $src_files] > 0} {
    remove_files $src_files
}

# Get all files in sim_1
set sim_files [get_files -of_objects [get_filesets sim_1] -quiet]
if {[llength $sim_files] > 0} {
    remove_files $sim_files
}

# 4. Add 64-tile Source Files
puts "Adding 64-tile RTL files..."
add_files -norecurse -scan_for_includes "e:/FPGA_codes/CLAHE/projects/64tile/rtl"

# 5. Add 64-tile Simulation Files
puts "Adding 64-tile TB files..."
add_files -fileset sim_1 -norecurse -scan_for_includes "e:/FPGA_codes/CLAHE/projects/64tile/tb"

# 6. Add back necessary shared files from 16tile/tb
# 'bmp_to_videoStream.sv' was confirmed missing in 64tile/tb but needed
puts "Adding shared TB files..."
add_files -fileset sim_1 -norecurse "e:/FPGA_codes/CLAHE/projects/16tile/tb/bmp_to_videoStream.sv"

# 7. Update Compile Order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project $new_proj_name created successfully!"
puts "Location: $new_proj_dir"
