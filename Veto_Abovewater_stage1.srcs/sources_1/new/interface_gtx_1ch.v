`timescale 1ns / 1ps

module interface_gtx_1ch(
    // system
    input  wire clk_drp_100M,

    // 125MHz GTX ref clock
    input  wire clk_gtx_125M,

    // GTX IO
    output wire gtx_tx_p,
                gtx_tx_n,
    input  wire gtx_rx_p,
                gtx_rx_n,

    // 125MHz TX, RX out clock
    output wire clk_txoutclk_bufg,
    output wire clk_rxoutclk_bufg,

    // GTX data
    input  wire [15:0] gt_tx_data,
    input  wire gt_tx_data_valid,
    output wire [15:0] gt_rx_data,
    output wire gt_rx_data_valid,

    // states for alignment
    output wire gtx_cpll_is_lock,
    output wire gt_link_up,
    output wire [1:0] rx_data_is_comma,
    output wire gtx_rx_error
    );

    // txoutclk / rxoutclk buffers
    wire clk_txoutclk;
    wire clk_rxoutclk;
    BUFG instance_bufg_txoutclk(
        .I (clk_txoutclk),
        .O (clk_txoutclk_bufg)
    );
    BUFG instance_bufg_rxoutclk(
        .I (clk_rxoutclk),
        .O (clk_rxoutclk_bufg)
    );

    // flags
    wire [1:0] tx_data_is_k;
    assign tx_data_is_k = gt_tx_data_valid ? 2'b00 : 2'b11;
    wire [1:0] rx_data_is_k;
    assign gt_rx_data_valid = (rx_data_is_k == 2'b00) ? 1 : 0;
    wire [1:0] rx_not_in_table;
    assign gtx_rx_error = |rx_not_in_table;
    wire rx_reset_done;

    //------------------------------------------
    // RX data alignment (from 0729_time_sync_125M):
    //   No automatic comma alignment in the IP. Instead, on rx_not_in_table
    //   error keep pulsing pma_rst until the RX has byte-aligned; also check
    //   that when both bytes are comma the received data is the idle 0xbc3c,
    //   otherwise keep resetting until that condition holds.
    //------------------------------------------
    reg rx_pma_rst_n_flag;
    reg rx_pma_rst_n;

    // flag computed in RX out clock domain
    always @(posedge clk_rxoutclk_bufg) begin
        if (~gtx_rx_error) begin
            if (&rx_data_is_comma) begin
                rx_pma_rst_n_flag <= (gt_rx_data == 16'hbc3c);
            end else begin
                rx_pma_rst_n_flag <= 1;
            end
        end else begin
            rx_pma_rst_n_flag <= 0;
        end
    end

    // pma reset driven in DRP clock domain
    always @(posedge clk_drp_100M) begin
        if (rx_reset_done) begin
            rx_pma_rst_n <= rx_pma_rst_n_flag;
        end else begin  // a reset will keep 2 periods
            rx_pma_rst_n <= 1;
        end
    end

    // link up: no decode error AND correct idle received (flag stable 1)
    assign gt_link_up = rx_pma_rst_n_flag;

    gtx_phy_1ch instance_gtx_phy_1ch (
        // system
        .sysclk_in                      (clk_drp_100M),
        .soft_reset_tx_in               (1'b0),
        .soft_reset_rx_in               (1'b0),
        .dont_reset_on_data_error_in    (1'b0),
        .gt0_tx_fsm_reset_done_out      (),
        .gt0_rx_fsm_reset_done_out      (),

        // CPLL ports
        .gt0_cpllfbclklost_out          (),
        .gt0_cplllock_out               (gtx_cpll_is_lock),
        .gt0_cplllockdetclk_in          (clk_drp_100M),
        .gt0_cpllreset_in               (1'b0),
        // Clocking Ports
        .gt0_gtrefclk0_in               (1'b0),
        .gt0_gtrefclk1_in               (clk_gtx_125M),

        // Receive Ports - FPGA RX Interface Ports
        .gt0_rxusrclk_in                (clk_rxoutclk_bufg),
        .gt0_rxusrclk2_in               (clk_rxoutclk_bufg),
        .gt0_rxdata_out                 (gt_rx_data),
        // Receive Ports - RX AFE
        .gt0_gtxrxp_in                  (gtx_rx_p),
        .gt0_gtxrxn_in                  (gtx_rx_n),
        // Receive Ports - RX Fabric Output Control Ports
        .gt0_rxoutclk_out               (clk_rxoutclk),
        .gt0_rxoutclkfabric_out         (),
        // Receive Ports - RX8B/10B Decoder Ports
        .gt0_rxcharisk_out              (rx_data_is_k),
        .gt0_rxchariscomma_out          (rx_data_is_comma),
        // RX byte alignment and clock phase adjust
        .gt0_rxpmareset_in              (~rx_pma_rst_n),    // important

        // Transmit Ports - FPGA TX Interface Ports
        .gt0_txusrclk_in                (clk_txoutclk_bufg),
        .gt0_txusrclk2_in               (clk_txoutclk_bufg),
        // Transmit Ports - TX Data Path interface
        .gt0_txdata_in                  (gt_tx_data),
        .gt0_data_valid_in              (1'b1),
        // Transmit Ports - TX Driver and OOB signaling
        .gt0_gtxtxn_out                 (gtx_tx_n),
        .gt0_gtxtxp_out                 (gtx_tx_p),
        // Transmit Ports - TX Fabric Clock Output Control Ports
        .gt0_txoutclk_out               (clk_txoutclk),
        .gt0_txoutclkfabric_out         (),
        .gt0_txoutclkpcs_out            (),
        // Transmit Ports - TX Gearbox Ports
        .gt0_txcharisk_in               (tx_data_is_k),

        // don't care
            // DRP Ports
            .gt0_drpaddr_in                 (9'b0),
            .gt0_drpclk_in                  (clk_drp_100M),
            .gt0_drpdi_in                   (16'b0),
            .gt0_drpdo_out                  (),
            .gt0_drpen_in                   (1'b0),
            .gt0_drprdy_out                 (),
            .gt0_drpwe_in                   (1'b0),
            // Digital Monitor Ports
            .gt0_dmonitorout_out            (),
            // Power-Down Ports
            .gt0_rxpd_in                    (2'b0),
            .gt0_txpd_in                    (2'b0),

            // RX
            // Receive Ports - RX Initialization and Reset Ports
            .gt0_gtrxreset_in               (1'b0),
            .gt0_rxresetdone_out            (rx_reset_done),
            // RX Initialization and Reset Ports
            .gt0_eyescanreset_in            (1'b0),
            .gt0_rxuserrdy_in               (1'b1),
            // RX Margin Analysis Ports
            .gt0_eyescandataerror_out       (),
            .gt0_eyescantrigger_in          (1'b0),
            // Receive Ports - RX 8B/10B Decoder Ports
            .gt0_rxdisperr_out              (),
            .gt0_rxnotintable_out           (rx_not_in_table),
            // Receive Ports - RX Equalizer Ports
            .gt0_rxdfelpmreset_in           (1'b0),
            .gt0_rxmonitorout_out           (),
            .gt0_rxmonitorsel_in            (2'b0),
            // Receive Ports - RX Buffer Bypass Ports
            .gt0_rxphmonitor_out            (),
            .gt0_rxphslipmonitor_out        (),

            // TX
            // TX Initialization and Reset Ports
            .gt0_gttxreset_in               (1'b0),
            .gt0_txuserrdy_in               (1'b1),
            // Transmit Ports - PCI Express Ports
            .gt0_txelecidle_in              (1'b0),
            // Transmit Ports - TX Initialization and Reset Ports
            .gt0_txresetdone_out            (),

            // QPLL
            .gt0_qplloutclk_in(1'b0),
            .gt0_qplloutrefclk_in(1'b0)
    );
endmodule
