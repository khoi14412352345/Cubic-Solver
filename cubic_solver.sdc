# Set the current design
current_design cubic_solver

# Primary clock: 8.0 ns period, 50% duty cycle
create_clock -name "clk" -add -period 8.0 -waveform {0.0 4.0} [get_ports clk]

# External input arrival times, excluding the clock port
set_input_delay -clock [get_clocks clk] -add_delay 4.0 [remove_from_collection [all_inputs] [get_ports clk]]

# External output required times
set_output_delay -clock [get_clocks clk] -add_delay 4.0 [all_outputs]

# Design-wide implementation limits from the synthesis lab template
set_max_fanout 15.000 [current_design]
set_max_transition 1.2 [current_design]
