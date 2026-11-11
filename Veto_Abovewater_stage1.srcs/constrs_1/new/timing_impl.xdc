# Implementation-only CDC clock groups. Every GT recovered RX/TX clock is an
# independent clock tree and is asynchronous to the system/MMCM/PLL clocks.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks SYSCLK_200MP_IN] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt0_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt0_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt1_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt1_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt2_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt2_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt3_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt3_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt4_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt4_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt5_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt5_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt6_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt6_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt7_gtx_phy_8ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_gtx_interface_8ch_separate/instance_gtx_phy_8ch/inst/gtx_phy_8ch_i/gt7_gtx_phy_8ch_i/gtxe2_i/TXOUTCLK}] \
    -group [get_clocks {instance_interface_gtx_1ch/instance_gtx_phy_1ch/inst/gtx_phy_1ch_i/gt0_gtx_phy_1ch_i/gtxe2_i/RXOUTCLK}] \
    -group [get_clocks {instance_interface_gtx_1ch/instance_gtx_phy_1ch/inst/gtx_phy_1ch_i/gt0_gtx_phy_1ch_i/gtxe2_i/TXOUTCLK}]
