
#Begin clock constraint
define_clock -name {RAW10toParallel|CSI2_sens_clk} {p:RAW10toParallel|CSI2_sens_clk} -period 4.382 -clockgroup Autoconstr_clkgroup_0 -rise 0.000 -fall 2.191 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {reveal_coretop|jtck_inferred_clock[0]} {n:reveal_coretop|jtck_inferred_clock[0]} -period 4.252 -clockgroup Autoconstr_clkgroup_1 -rise 0.000 -fall 2.126 -route 0.000 
#End clock constraint

#Begin clock constraint
define_clock -name {RAW10toParallel|clk_i} {p:RAW10toParallel|clk_i} -period 6.018 -clockgroup Autoconstr_clkgroup_2 -rise 0.000 -fall 3.009 -route 0.000 
#End clock constraint
