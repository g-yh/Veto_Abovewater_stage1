`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/03 14:31:32
// Design Name: 
// Module Name: main
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module main (
    // System
    input wire SYSCLK_200MP_IN,  // From 200MHz Oscillator module
    input wire SYSCLK_200MN_IN,  // From 200MHz Oscillator module
    // jesd204b clk		
    // input   wire            gt_refclk1_p    ,   // 
    // input   wire            gt_refclk1_n    ,
    input wire gt_refclk2_p,     // 
    input wire gt_refclk2_n,
    // input   wire            gt_refclk3_p    ,   // 
    // input   wire            gt_refclk3_n    ,
    input wire gt_refclk4_p,     // REF CLK 125M
    input wire gt_refclk4_n,
    // input	wire			MGT_REF_CLK_P	,
    // input	wire			MGT_REF_CLK_N	,

    // 8 lanes underwater 
    output wire [7:0] FE_SFP_TX_P,
    output wire [7:0] FE_SFP_TX_N,
    input  wire [7:0] FE_SFP_RX_P,
    input  wire [7:0] FE_SFP_RX_N,
    // 1 lane abovewater stage2
    output wire       BE_SFP_TX_P,
    output wire       BE_SFP_TX_N,
    input  wire       BE_SFP_RX_P,
    input  wire       BE_SFP_RX_N,
    output wire       SFP_TX_DISABLE,
    // LED
    // output	wire	[4:1]	LED			    ,
    // spi interface
    output wire       cs_ad9528,
    output wire       sclk_ad9528,
    inout  wire       sdio_ad9528,
    // ad9528 reset n
    output wire       ad9528_rst_n,
    // ad9528 sysref request p
    output wire       ad9528_sysref_req,
    // ext trigger input
    // input   wire            ext_trig_in     ,
    // fan 	
    output wire       FAN_PWM
);

    wire [1:0] cfg_state_ad9528;

    wire       CLK_200M;
    wire       CLK_100M;
    wire       CLK_5M;
    wire       SYSCLK_200M_buff;

    wire       sysrst;
    wire       pll_locked;
    wire       sysrst_glb_n;
    wire       cfg_ad9528;

    wire       aurora_reset_pb;

    assign ad9528_rst_n   = sysrst_glb_n;
    assign sysrst         = 1'b0;
    assign FAN_PWM        = 1'b1;
    assign SFP_TX_DISABLE = 1'b0;
    // assign      LED[4]              = pll_locked;

    // 200M clk input buff
    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE")
    ) IBUFDS_200M (
        .O (SYSCLK_200M_buff),
        .I (SYSCLK_200MP_IN),
        .IB(SYSCLK_200MN_IN)
    );
    BUFG BUFG_200M (
        .O(CLK_200M),
        .I(SYSCLK_200M_buff)
    );

    clk_wiz_aurora clk_wiz_aurora_inst (
        // Clock out ports
        .clk_out1(CLK_100M),    // output clk_out1
        .clk_out2(CLK_5M),      // output clk_out2
        // Status and control signals
        .locked  (pll_locked),  // output locked
        // Clock in ports
        .clk_in1 (CLK_200M)
    );

    rst_dis rst_dis_inst (
        .clk_in      (CLK_5M),
        .sysrst      (sysrst),
        .pll_locked  (pll_locked),
        .cfg_ad9528  (cfg_ad9528),
        .rst_aurura  (aurora_reset_pb),
        .sysrst_glb_n(sysrst_glb_n)
    );

    // spi configure adc and clk //
    spi_top spi_top_inst (
        .clk  (CLK_5M),
        .rst_n(sysrst_glb_n),

        .cs_ad9528  (cs_ad9528),
        .sclk_ad9528(sclk_ad9528),
        .sdio_ad9528(sdio_ad9528),

        .cfg_ad9528(cfg_ad9528),

        .cfg_state_ad9528(cfg_state_ad9528)
    );


    //--------------------------------
    // 8ch GTX interface (FE link to underwater)
    //--------------------------------
    // 125M GTX ref clk input
    wire clk_gtx_125M;
    IBUFDS_GTE2 instance_ibufgds_gtx_refclk (
        .I    (gt_refclk2_p),
        .IB   (gt_refclk2_n),
        .O    (clk_gtx_125M),
        .CEB  (1'b0),
        .ODIV2()
    );

    wire [  7:0] rx_pma_rst_n;
    wire [  7:0] clk_txoutclk_bufg;
    wire [  7:0] clk_rxoutclk_bufg;
    wire [127:0] gt_tx_data;
    wire [  7:0] gt_tx_data_valid;
    wire [127:0] gt_rx_data;
    wire [  7:0] gt_rx_data_valid;
    wire [  7:0] gtx_cpll_is_lock;
    wire [  7:0] rx_reset_done;
    wire [ 15:0] rx_data_is_comma;
    wire [  7:0] gtx_rx_error;

    interface_gtx_8ch instance_gtx_interface_8ch (
        .rx_pma_rst_n     (rx_pma_rst_n),
        .clk_drp_100M     (CLK_100M),
        .clk_gtx_125M     (clk_gtx_125M),
        .gtx_tx_p         (FE_SFP_TX_P),
        .gtx_tx_n         (FE_SFP_TX_N),
        .gtx_rx_p         (FE_SFP_RX_P),
        .gtx_rx_n         (FE_SFP_RX_N),
        .clk_txoutclk_bufg(clk_txoutclk_bufg),
        .clk_rxoutclk_bufg(clk_rxoutclk_bufg),
        .gt_tx_data       (gt_tx_data),
        .gt_tx_data_valid (gt_tx_data_valid),
        .gt_rx_data       (gt_rx_data),
        .gt_rx_data_valid (gt_rx_data_valid),
        .gtx_cpll_is_lock (gtx_cpll_is_lock),
        .rx_reset_done    (rx_reset_done),
        .rx_data_is_comma (rx_data_is_comma),
        .gtx_rx_error     (gtx_rx_error)
    );

    //--------------------------------
    // 400M clock for TDC phase measure
    //--------------------------------
    wire clk_400M;
    wire pll_clk_400M;
    wire pll_feedback_400M;
    PLLE2_BASE #(
        .BANDWIDTH("HIGH"),
        .CLKFBOUT_MULT(8),
        .CLKIN1_PERIOD(5),
        .DIVCLK_DIVIDE(1),
        .CLKOUT0_DIVIDE(4)
    ) PLLE2_400M (
        .CLKIN1  (CLK_200M),
        .CLKOUT0 (pll_clk_400M),
        .CLKOUT1 (),
        .CLKOUT2 (),
        .CLKOUT3 (),
        .CLKOUT4 (),
        .CLKOUT5 (),
        .CLKFBOUT(pll_feedback_400M),
        .CLKFBIN (pll_feedback_400M),
        .LOCKED  (),
        .PWRDWN  (0),
        .RST     (0)
    );
    BUFG instance_bufg_sysclk_400M (
        .I(pll_clk_400M),
        .O(clk_400M)
    );


    //--------------------------------
    // clock sync (time_sync) on each FE GT channel, independent
    //--------------------------------
    // gt user data
    wire [15:0] user_tx_data            [0:7];
    wire        user_tx_data_valid      [0:7];
    wire [15:0] user_rx_data            [0:7];
    wire        user_rx_data_valid      [0:7];

    // timestamp
    wire [63:0] ptp_timestamp_tx        [0:7];
    wire [63:0] ptp_timestamp_rx        [0:7];

    // ptp control
    wire        start_ptp               [0:7];
    wire [15:0] timestamp_rx_delay      [0:7];
    wire        timestamp_rx_delay_valid[0:7];

    // ptp uart output
    wire [ 7:0] uart_ptp_data           [0:7];
    wire        uart_ptp_read_enable    [0:7];
    wire        uart_ptp_read_empty     [0:7];
    wire        uart_ptp_read_valid     [0:7];

    // debug
    wire [ 3:0] ptp_flags               [0:7];

    genvar ch;
    generate
        for (ch = 0; ch < 8; ch = ch + 1) begin : gen_time_sync
            time_sync_manager instance_time_sync_manager (
                .clk_txoutclk_bufg(clk_txoutclk_bufg[ch]),
                .clk_rxoutclk_bufg(clk_rxoutclk_bufg[ch]),
                .clk_sys_400M     (clk_400M),
                .clk_drp_100M     (CLK_100M),
                .clk_uart         (CLK_100M),

                // gtx data
                .gt_tx_data         (gt_tx_data[ch*16+:16]),
                .gt_tx_data_valid   (gt_tx_data_valid[ch]),
                .gt_rx_data         (gt_rx_data[ch*16+:16]),
                .gt_rx_data_valid   (gt_rx_data_valid[ch]),
                .gt_rx_data_is_comma(rx_data_is_comma[ch*2+:2]),

                // user data
                .user_tx_data      (user_tx_data[ch]),
                .user_tx_data_valid(user_tx_data_valid[ch]),
                .user_rx_data      (user_rx_data[ch]),
                .user_rx_data_valid(user_rx_data_valid[ch]),

                // timestamp
                .timestamp_tx   (ptp_timestamp_tx[ch]),
                .timestamp_rx   (ptp_timestamp_rx[ch]),
                .ptp_start      (start_ptp[ch]),
                .ptp_value      (timestamp_rx_delay[ch]),
                .ptp_value_valid(timestamp_rx_delay_valid[ch]),
                .tx_load_value  (64'b0),
                .tx_load        (1'b0),

                // uart interface
                .uart_data_out   (uart_ptp_data[ch]),
                .uart_read_enable(uart_ptp_read_enable[ch]),
                .uart_read_empty (uart_ptp_read_empty[ch]),
                .uart_read_valid (uart_ptp_read_valid[ch]),

                // data alignment and pma reset
                .gt_rx_error   (gtx_rx_error[ch]),
                .gt_pma_rst_n  (rx_pma_rst_n[ch]),
                .gt_rx_rst_done(rx_reset_done[ch]),

                .flags(ptp_flags[ch])
            );
        end
    endgenerate

    //--------------------------------
    // 1ch GTX interface (BE link to stage2), no clock sync
    //--------------------------------
    // 125M GTX ref clk input
    wire be_clk_gtx_125M;
    IBUFDS_GTE2 instance_ibufgds_gtx_refclk_1ch (
        .I   (gt_refclk4_p),
        .IB  (gt_refclk4_n),
        .O   (be_clk_gtx_125M),
        .CEB (1'b0),
        .ODIV2()
    );

    wire        be_clk_txoutclk_bufg;
    wire        be_clk_rxoutclk_bufg;
    wire [15:0] be_gt_tx_data;
    wire        be_gt_tx_data_valid;
    wire [15:0] be_gt_rx_data;
    wire        be_gt_rx_data_valid;
    wire        be_gtx_cpll_is_lock;
    wire        be_gt_link_up;
    wire [ 1:0] be_rx_data_is_comma;
    wire        be_gtx_rx_error;

    // BE data path not built yet
    // assign be_gt_tx_data       = 16'hbc3c;
    // assign be_gt_tx_data_valid = 1'b0;

    interface_gtx_1ch instance_interface_gtx_1ch (
        .clk_drp_100M(CLK_100M),

        // 125MHz GTX ref clock
        .clk_gtx_125M(be_clk_gtx_125M),

        // GTX IO
        .gtx_tx_p(BE_SFP_TX_P),
        .gtx_tx_n(BE_SFP_TX_N),
        .gtx_rx_p(BE_SFP_RX_P),
        .gtx_rx_n(BE_SFP_RX_N),

        // 125MHz TX, RX out clock
        .clk_txoutclk_bufg(be_clk_txoutclk_bufg),
        .clk_rxoutclk_bufg(be_clk_rxoutclk_bufg),

        // GTX data
        .gt_tx_data      (be_gt_tx_data),
        .gt_tx_data_valid(be_gt_tx_data_valid),
        .gt_rx_data      (be_gt_rx_data),
        .gt_rx_data_valid(be_gt_rx_data_valid),

        // states for alignment
        .gtx_cpll_is_lock(be_gtx_cpll_is_lock),
        .gt_link_up      (be_gt_link_up),
        .rx_data_is_comma(be_rx_data_is_comma),
        .gtx_rx_error    (be_gtx_rx_error)
    );

    //--------------------------------
    // Slow control from stage2 -> underwater boards
    //   Receives 16-bit {addr(1~8), data} on the BE 1ch GT RX, routes it into
    //   the fifo_slow_control FIFO of the addressed FE channel, and forwards it
    //   on that channel's user_tx_data (time_sync sends it on the FE GT TX).
    //--------------------------------
    slow_control_manager instance_slow_control_manager (
        .rst_n               (sysrst_glb_n),
        .be_clk_rxoutclk_bufg(be_clk_rxoutclk_bufg),
        .be_gt_rx_data       (be_gt_rx_data),
        .be_gt_rx_data_valid (be_gt_rx_data_valid),
        .clk_txoutclk_bufg   (clk_txoutclk_bufg),
        .slow_control_data        (user_tx_data),
        .slow_control_data_valid  (user_tx_data_valid)
    );

endmodule
