# Simulation-only constraints for CLAHE top
# Use this XDC for RTL/synth simulation when running locally (no board)
# - No physical I/O pin mapping
# - Basic clock/timing constraints only
# - Keeps Vivado happy for Synthesis/Implementation checks without board pin dependencies

# Pixel clock (pclk) 74.25MHz (13.5 ns)
create_clock -period 13.500 -name pclk [get_ports pclk]

# Optional: keep reset pull info for timing checks (not a physical pin mapping)
# set_property PULLUP true [get_ports {rst_n}]

# Optional: Input/output timing (example). Keep conservative values (for timing analysis only)
# set_input_delay -clock pclk -max 3.0 [get_ports {in_y[*] in_u in_v in_href in_vsync}]
# set_input_delay -clock pclk -min -3.0 [get_ports {in_y[*] in_u in_v in_href in_vsync}]
# set_output_delay -clock pclk -max 3.0 [get_ports {out_y[*] out_u out_v out_href out_vsync}]
# set_output_delay -clock pclk -min -3.0 [get_ports {out_y[*] out_u out_v out_href out_vsync}]

# Optional: Keep false/multicycle path comments for reference
# set_false_path -from [get_clocks -of_objects [get_ports {other_clk}]] -to [get_clocks pclk]
# set_multicycle_path -from ... -to ... -setup 2

# End of simulation-only XDC

