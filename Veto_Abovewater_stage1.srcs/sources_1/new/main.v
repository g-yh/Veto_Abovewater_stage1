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


    // spi interface
    output wire cs_ad9528,
    output wire sclk_ad9528,
    inout  wire sdio_ad9528,

    // ad9528 reset n
    output wire ad9528_rst_n,

    // ad9528 sysref request p
    output wire ad9528_sysref_req,

    // ext trigger input
    // input   wire            ext_trig_in     ,

    // GT link status LEDs
    output wire gt_link_up_led1,  // all 8 FE gt_link_up high
    output wire gt_link_up_led2,  // BE gt_link_up

    output wire MCX_CLK0,
    output wire MCX_CLK1,

    // fan 	
    output wire FAN_PWM
);

    //--------------------------------
    // FE 侧（8ch）GTX 接口信号前置声明
    //   Verilog 要求先声明后使用。下面 MCX_CLK0/1 与 gt_link_up_led1 会在
    //   100 行以内就引用这些信号，若声明放在 interface_gtx_8ch 例化之前，
    //   综合器会建立宽度为 1 的隐式网络并与之冲突。
    //--------------------------------
    wire [  7:0] rx_pma_rst_n;
    wire [  7:0] clk_txoutclk_bufg;
    wire [  7:0] clk_rxoutclk_bufg;
    wire [127:0] gt_tx_data;
    wire [  7:0] gt_tx_data_valid;
    wire [127:0] gt_rx_data;
    wire [  7:0] gt_rx_data_valid;
    wire [  7:0] gtx_cpll_is_lock;
    wire [  7:0] rx_reset_done;
    wire [  7:0] gt_link_up;
    wire [ 15:0] rx_data_is_comma;
    wire [  7:0] gtx_rx_error;

    assign MCX_CLK0 = clk_rxoutclk_bufg[0];
    assign MCX_CLK1 = clk_txoutclk_bufg[0];

    wire [1:0] cfg_state_ad9528;

    wire       CLK_200M;
    wire       CLK_100M;
    wire       CLK_5M;
    wire       SYSCLK_200M_buff;

    wire       sysrst;
    wire       pll_locked;
    wire       cfg_ad9528;
    wire       ad9253_spi_rst_n;

    assign sysrst          = 1'b0;
    assign FAN_PWM         = 1'b1;
    assign SFP_TX_DISABLE  = 1'b0;
    // assign      LED[4]              = pll_locked;

    // assign gt_link_up_led1 = &gt_link_up;
    assign gt_link_up_led1 = gt_link_up[0];
    // assign gt_link_up_led2 = be_gt_link_up;   // be_gt_link_up 在下方声明后再驱动

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

    wire sysrst_glb_n;

    assign ad9528_rst_n = pll_locked;
    assign ad9253_spi_rst_n = pll_locked;
    assign cfg_ad9528 = pll_locked;

    // assign sysrst_glb_n = pll_locked;
    vio_0 vio_0_inst (
        .clk(CLK_200M),
        .probe_out0(sysrst_glb_n)
    );

    // localparam integer CNT_50MS = 250_000;
    // reg [18:0] cnt;

    // always @(posedge CLK_5M) begin
    //     if (!pll_locked) begin
    //         cnt              <= 0;
    //         ad9253_spi_rst_n <= 1'b0;
    //         cfg_ad9528       <= 1'b0;
    //     end else if (cnt < 2 * CNT_50MS) begin
    //         cnt <= cnt + 1'b1;

    //         if (cnt >= CNT_50MS) ad9253_spi_rst_n <= 1'b1;

    //         if (cnt >= 2 * CNT_50MS) cfg_ad9528 <= 1'b1;
    //     end else begin
    //         ad9253_spi_rst_n <= 1'b1;
    //         cfg_ad9528       <= 1'b1;
    //     end
    // end

    // spi configure adc and clk //
    spi_top spi_top_inst (
        .clk  (CLK_5M),
        .rst_n(ad9253_spi_rst_n),

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

    // FE 侧信号已在前置声明处声明，此处不再重复
    interface_gtx_8ch instance_gtx_interface_8ch_separate (
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
    // 事件长度常量（与 underwater 侧一致）
    localparam TRIG_TOTAL = 16'd57;
    localparam HEAD_LEN = 16'd7;
    localparam EVT_WORDS = TRIG_TOTAL + HEAD_LEN;  // 64 words/event
    localparam ADC_FIFO_FULL_THRESH = 11'd1984;  // 剩余>=1整事件空位(2048-64)，与stage2一致

    // gt user data
    wire [127:0] user_tx_data;
    wire [  7:0] user_tx_data_valid;
    wire [127:0] user_rx_data;
    wire [  7:0] user_rx_data_valid;

    // timestamp
    wire [511:0] ptp_timestamp_tx;
    wire [511:0] ptp_timestamp_rx;

    // ptp control (clk_txoutclk_bufg[ch] domain, from slow_control_manager CDC FIFOs)
    wire [  7:0] ptp_start;
    wire [  7:0] ptp_start_valid;
    wire [127:0] timestamp_rx_delay;
    wire [  7:0] timestamp_rx_delay_valid;

    // ptp uart output (8ch × 8bit)
    wire [ 63:0] ptp_data;
    reg  [  7:0] ptp_read_enable;
    wire [  7:0] ptp_read_empty;
    wire [  7:0] ptp_read_valid;

    // debug
    wire [ 31:0] ptp_flags;

    //--------------------------------
    // BE 侧（stage2 链路）信号前置声明
    //   这些信号由 interface_gtx_1ch 产生，但在此处就要被 generate 内的
    //   FIFO（rd_clk）与 time_sync_manager（clk_uart）引用。
    //   Verilog 要求先声明后使用，否则会被综合器当成隐式 wire（宽度 1、无驱动），
    //   导致 FIFO 的 rd_clk 悬空 -> wr_rst_busy 恒为 1。
    //--------------------------------
    wire be_clk_txoutclk_bufg;
    wire be_clk_rxoutclk_bufg;
    reg  [15:0] be_gt_tx_data;
    reg         be_gt_tx_data_valid;
    wire [15:0] be_gt_rx_data;
    wire        be_gt_rx_data_valid;
    wire        be_gtx_cpll_is_lock;
    wire        be_gt_link_up;
    wire [ 1:0] be_rx_data_is_comma;
    wire        be_gtx_rx_error;

    assign gt_link_up_led2 = be_gt_link_up;

    //--------------------------------
    // 每通道接收返回 FIFO（写侧 clk_rxoutclk_bufg[ch]，读侧 be_clk_txoutclk_bufg）
    //   fifo_sc_tx: 慢控返回（1 word/帧），fifo_adc: ADC 事件（EVT_WORDS words/帧）
    //   fifo_ack_tx: W-packet ack 返回（0xFFF3 + 1 word）
    //--------------------------------
    reg  [  7:0] sc_rd_en;
    wire [  7:0] sc_fifo_empty;
    wire [  7:0] sc_fifo_valid;
    wire [127:0] sc_fifo_dout;

    reg  [  7:0] ack_rd_en;
    wire [  7:0] ack_fifo_empty;
    wire [  7:0] ack_fifo_valid;
    wire [127:0] ack_fifo_dout;

    reg  [  7:0] adc_rd_en;
    wire [  7:0] adc_fifo_empty;
    wire [  7:0] adc_fifo_prog_empty;
    wire [  7:0] adc_fifo_valid;
    wire [127:0] adc_fifo_dout;

    //--------------------------------
    // 每通道接收侧状态（generate 内使用，索引 [ch]）
    //   0..7 对应 gen_time_sync 的 8 个通道
    //--------------------------------
    reg  [  7:0] sc_pend;  // 慢控返回：已收 FFF1，待收 1 个 word
    reg  [  7:0] ack_pend;  // W-packet ack：已收 FFF3，待收 1 个 word
    reg  [ 56:0] evt_pend;  // ADC 事件：已收 FFF0，待收 EVT_WORDS 个 word

    wire [  7:0] sc_wr_this;  // 本拍写 sc FIFO
    wire [  7:0] adc_wr_this;  // 本拍写 adc FIFO

    wire [  7:0] sc_fifo_full;
    wire [  7:0] sc_wr_rst_busy;
    wire [  7:0] sc_rd_rst_busy;
    wire [  7:0] ack_fifo_full;
    wire [  7:0] ack_wr_rst_busy;
    wire [  7:0] ack_rd_rst_busy;
    wire [  7:0] adc_fifo_full;
    wire [  7:0] adc_fifo_prog_full;
    wire [  7:0] adc_wr_rst_busy;
    wire [  7:0] adc_rd_rst_busy;


    genvar ch;
    generate
        for (ch = 0; ch < 8; ch = ch + 1) begin : gen_time_sync
            time_sync_manager instance_time_sync_manager (
                .clk_txoutclk_bufg(clk_txoutclk_bufg[ch]),
                .clk_rxoutclk_bufg(clk_rxoutclk_bufg[ch]),
                .clk_sys_400M     (clk_400M),
                .clk_drp_100M     (CLK_100M),
                .clk_uart         (be_clk_txoutclk_bufg),
                .fifo_rst_n       (sysrst_glb_n),

                // gtx data
                .gt_tx_data         (gt_tx_data[ch*16+:16]),
                .gt_tx_data_valid   (gt_tx_data_valid[ch]),
                .gt_rx_data         (gt_rx_data[ch*16+:16]),
                .gt_rx_data_valid   (gt_rx_data_valid[ch]),
                .gt_rx_data_is_comma(rx_data_is_comma[ch*2+:2]),

                // user data
                .user_tx_data      (user_tx_data[ch*16+:16]),
                .user_tx_data_valid(user_tx_data_valid[ch]),
                .user_rx_data      (user_rx_data[ch*16+:16]),
                .user_rx_data_valid(user_rx_data_valid[ch]),

                // timestamp
                .timestamp_tx   (ptp_timestamp_tx[ch*64+:64]),
                .timestamp_rx   (ptp_timestamp_rx[ch*64+:64]),
                .ptp_start      (ptp_start[ch]),
                .ptp_value      (timestamp_rx_delay[ch*16+:16]),
                .ptp_value_valid(timestamp_rx_delay_valid[ch]),
                .tx_load_value  (64'b0),
                .tx_load        (1'b0),

                // uart interface
                .uart_data_out   (ptp_data[ch*8+:8]),
                .uart_read_enable(ptp_read_enable[ch]),
                .uart_read_empty (ptp_read_empty[ch]),
                .uart_read_valid (ptp_read_valid[ch]),

                // data alignment and pma reset
                .gt_rx_error   (gtx_rx_error[ch]),
                .gt_pma_rst_n  (rx_pma_rst_n[ch]),
                .gt_rx_rst_done(rx_reset_done[ch]),
                .gt_link_up    (gt_link_up[ch]),

                .flags(ptp_flags[ch*4+:4])
            );


            // --------------------------------
            // 接收帧头解析 + FIFO 写入（clk_rxoutclk_bufg[ch] 域）
            //   user_rx_data 为 PTP 剥离后的流：
            //     0xFFF3 -> W-packet ack -> fifo_ack_tx
            //     0xFFF1 -> 1 个慢控返回 word -> fifo_sc_tx
            //     0xFFF0 -> EVT_WORDS 个 ADC word -> fifo_adc
            //     其它(含 bc3c) -> 忽略
            // --------------------------------
            assign sc_wr_this[ch]  = user_rx_data_valid[ch] && sc_pend[ch];
            assign adc_wr_this[ch] = user_rx_data_valid[ch] && (evt_pend[ch*7+:7] != 7'd0);

            always @(posedge clk_rxoutclk_bufg[ch] or negedge sysrst_glb_n) begin
                if (!sysrst_glb_n) begin
                    sc_pend[ch] <= 1'b0;
                    evt_pend[ch*7+:7] <= 7'd0;
                    ack_pend[ch] <= 1'b0;
                end else if (user_rx_data_valid[ch]) begin
                    if (ack_pend[ch]) begin
                        // 上一拍已识别 FFF3，本拍是 ACK 数据字；消费掉标志
                        ack_pend[ch] <= 1'b0;
                    end else if (sc_pend[ch]) begin
                        sc_pend[ch] <= 1'b0;
                    end else if (evt_pend[ch*7+:7] != 7'd0) begin
                        evt_pend[ch*7+:7] <= evt_pend[ch*7+:7] - 7'd1;
                    end else begin
                        // 空闲：识别帧头
                        if (user_rx_data[ch*16+:16] == 16'hFFF3) begin
                            ack_pend[ch] <= 1'b1;
                        end else if (user_rx_data[ch*16+:16] == 16'hFFF1) begin
                            sc_pend[ch]  <= 1'b1;
                            ack_pend[ch] <= 1'b0;
                        end else if (user_rx_data[ch*16+:16] == 16'hFFF0) begin
                            if (~adc_fifo_prog_full[ch]) begin
                                evt_pend[ch*7+:7] <= EVT_WORDS[6:0];
                            end
                            ack_pend[ch] <= 1'b0;
                        end else begin
                            ack_pend[ch] <= 1'b0;
                        end
                    end
                end
            end

            // 慢控返回 FIFO
            fifo_sc_tx u_fifo_sc_tx (
                .rst        (~(gt_link_up[ch] && sysrst_glb_n)),
                .wr_clk     (clk_rxoutclk_bufg[ch]),
                .rd_clk     (be_clk_txoutclk_bufg),
                .din        (user_rx_data[ch*16+:16]),
                .wr_en      (sc_wr_this[ch] && ~sc_fifo_full[ch] && ~sc_wr_rst_busy[ch]),
                .rd_en      (sc_rd_en[ch]),
                .dout       (sc_fifo_dout[ch*16+:16]),
                .full       (sc_fifo_full[ch]),
                .empty      (sc_fifo_empty[ch]),
                .valid      (sc_fifo_valid[ch]),
                .wr_rst_busy(sc_wr_rst_busy[ch]),
                .rd_rst_busy(sc_rd_rst_busy[ch])
            );

            // ack
            fifo_sc_tx u_fifo_ack_tx (
                .rst        (~(gt_link_up[ch] && sysrst_glb_n)),
                .wr_clk     (clk_rxoutclk_bufg[ch]),
                .rd_clk     (be_clk_txoutclk_bufg),
                .din        (user_rx_data[ch*16+:16]),
                .wr_en      (ack_pend[ch] && ~ack_fifo_full[ch] && ~ack_wr_rst_busy[ch]),
                .rd_en      (ack_rd_en[ch]),
                .dout       (ack_fifo_dout[ch*16+:16]),
                .full       (ack_fifo_full[ch]),
                .empty      (ack_fifo_empty[ch]),
                .valid      (ack_fifo_valid[ch]),
                .wr_rst_busy(ack_wr_rst_busy[ch]),
                .rd_rst_busy(ack_rd_rst_busy[ch])
            );

            // ADC 事件 FIFO（prog_empty_thresh = EVT_WORDS, prog_full_thresh = ADC_FIFO_FULL_THRESH）
            fifo_adc u_fifo_adc (
                .rst              (~(gt_link_up[ch] && sysrst_glb_n)),
                .wr_clk           (clk_rxoutclk_bufg[ch]),
                .rd_clk           (be_clk_txoutclk_bufg),
                .din              (user_rx_data[ch*16+:16]),
                .wr_en            (adc_wr_this[ch] && ~adc_fifo_full[ch] && ~adc_wr_rst_busy[ch]),
                .rd_en            (adc_rd_en[ch]),
                .prog_empty_thresh(EVT_WORDS),
                .prog_full_thresh (ADC_FIFO_FULL_THRESH),
                .dout             (adc_fifo_dout[ch*16+:16]),
                .full             (adc_fifo_full[ch]),
                .empty            (adc_fifo_empty[ch]),
                .prog_full        (adc_fifo_prog_full[ch]),
                .prog_empty       (adc_fifo_prog_empty[ch]),
                .valid            (adc_fifo_valid[ch]),
                .wr_rst_busy      (adc_wr_rst_busy[ch]),
                .rd_rst_busy      (adc_rd_rst_busy[ch])
            );
        end
    endgenerate

    //--------------------------------
    // PTP read control
    //--------------------------------
    // BE GT TX 轮询发送状态机（be_clk_txoutclk_bufg 域）
    //   优先级: PTP > W-packet ack > 慢控返回 > ADC 事件 > 空闲(bc3c)
    //   仲裁 round-robin 扫描 rr_idx[0..7]
    //--------------------------------
    localparam BE_TX_IDLE = 4'd0;
    localparam BE_TX_ACK_HDR = 4'd1;
    localparam BE_TX_ACK_DATA = 4'd2;
    localparam BE_TX_SC_HDR = 4'd3;
    localparam BE_TX_SC_DATA = 4'd4;
    localparam BE_TX_AD_HDR = 4'd5;  // FFF0 帧头
    localparam BE_TX_AD_BOARD = 4'd6;  // 板号头
    localparam BE_TX_AD_DATA = 4'd7;  // EVT_WORDS 个数据 word
    localparam BE_TX_PTP_HDR = 4'd8;  // PTP 帧头 FFF2
    localparam BE_TX_PTP_DATA = 4'd9;  // 单个 FFF2 帧携带完整 48 字节
    localparam [5:0] BE_PTP_FRAME_BYTES = 6'd48;
    localparam BE_PTP_WAIT_MAX = 14'd10000;  // 125 MHz 下约 80 us

    reg [3:0] be_tx_state;
    reg [2:0] rr_idx;
    reg [6:0] evt_tx_cnt;
    reg [5:0] ptp_tx_cnt;
    reg [13:0] ptp_wait_cnt;

    always @(posedge be_clk_txoutclk_bufg or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n) begin
            be_tx_state         <= BE_TX_IDLE;
            rr_idx              <= 3'd0;
            evt_tx_cnt          <= 7'd0;
            ptp_tx_cnt          <= 6'd0;
            ptp_wait_cnt        <= 14'd0;
            sc_rd_en            <= 8'd0;
            adc_rd_en           <= 8'd0;
            ack_rd_en           <= 8'd0;
            ptp_read_enable     <= 8'd0;
            be_gt_tx_data       <= 16'hbc3c;
            be_gt_tx_data_valid <= 1'b0;
        end else begin
            case (be_tx_state)
                BE_TX_IDLE: begin
                    sc_rd_en            <= 8'd0;
                    adc_rd_en           <= 8'd0;
                    ptp_read_enable     <= 8'd0;
                    ack_rd_en           <= 8'd0;
                    be_gt_tx_data_valid <= 1'b0;
                    be_gt_tx_data       <= 16'hbc3c;
                    ptp_wait_cnt        <= 14'd0;
                    if (~ptp_read_empty[rr_idx]) begin
                        be_tx_state <= BE_TX_PTP_HDR;
                    end else if (~ack_fifo_empty[rr_idx]) begin
                        be_tx_state <= BE_TX_ACK_HDR;
                    end else if (~sc_fifo_empty[rr_idx]) begin
                        be_tx_state <= BE_TX_SC_HDR;
                    end else if (~adc_fifo_prog_empty[rr_idx]) begin
                        be_tx_state <= BE_TX_AD_HDR;
                    end else begin
                        rr_idx <= rr_idx + 3'd1;
                    end
                end
                // ---- W-packet ack：FFF3 + 1 word ----
                BE_TX_ACK_HDR: begin
                    be_gt_tx_data       <= 16'hFFF3;
                    be_gt_tx_data_valid <= 1'b1;
                    ack_rd_en           <= (8'd1 << rr_idx);
                    be_tx_state         <= BE_TX_ACK_DATA;
                end
                BE_TX_ACK_DATA: begin
                    ack_rd_en <= 8'd0;
                    if (ack_fifo_valid[rr_idx]) begin
                        be_gt_tx_data       <= 16'hFFFF;
                        be_gt_tx_data_valid <= 1'b1;
                        be_tx_state         <= BE_TX_IDLE;
                    end else begin
                        be_gt_tx_data       <= 16'hbc3c;
                        be_gt_tx_data_valid <= 1'b0;
                    end
                end
                // ---- 慢控返回：FFF1 + 1 word ----
                BE_TX_SC_HDR: begin
                    be_gt_tx_data       <= 16'hFFF1;
                    be_gt_tx_data_valid <= 1'b1;
                    sc_rd_en            <= (8'd1 << rr_idx);
                    be_tx_state         <= BE_TX_SC_DATA;
                end
                BE_TX_SC_DATA: begin
                    sc_rd_en <= 8'd0;
                    if (sc_fifo_valid[rr_idx]) begin
                        be_gt_tx_data       <= sc_fifo_dout[rr_idx*16+:16];
                        be_gt_tx_data_valid <= 1'b1;
                        be_tx_state         <= BE_TX_IDLE;
                    end else begin
                        be_gt_tx_data       <= 16'hbc3c;
                        be_gt_tx_data_valid <= 1'b0;
                    end
                end
                // ---- ADC 事件：FFF0 + 板号 + EVT_WORDS ----
                BE_TX_AD_HDR: begin
                    be_gt_tx_data       <= 16'hFFF0;
                    be_gt_tx_data_valid <= 1'b1;
                    be_tx_state         <= BE_TX_AD_BOARD;
                end
                BE_TX_AD_BOARD: begin
                    be_gt_tx_data       <= {8'd0, rr_idx + 8'd1};  // 板号 1~8
                    be_gt_tx_data_valid <= 1'b1;
                    adc_rd_en           <= (8'd1 << rr_idx);
                    evt_tx_cnt          <= 7'd0;
                    be_tx_state         <= BE_TX_AD_DATA;
                end
                BE_TX_AD_DATA: begin
                    adc_rd_en <= (8'd1 << rr_idx);
                    if (adc_fifo_valid[rr_idx]) begin
                        be_gt_tx_data       <= adc_fifo_dout[rr_idx*16+:16];
                        be_gt_tx_data_valid <= 1'b1;
                        if (evt_tx_cnt == EVT_WORDS[6:0] - 7'd1) begin
                            adc_rd_en   <= 8'd0;
                            be_tx_state <= BE_TX_IDLE;
                        end else begin
                            evt_tx_cnt <= evt_tx_cnt + 7'd1;
                        end
                    end else begin
                        be_gt_tx_data       <= 16'hbc3c;
                        be_gt_tx_data_valid <= 1'b0;
                    end
                end
                // ---- PTP：最高优先，FFF2 头 + 完整 48 字节 ----
                BE_TX_PTP_HDR: begin
                    be_gt_tx_data       <= 16'hFFF2;
                    be_gt_tx_data_valid <= 1'b1;
                    ptp_read_enable     <= (8'd1 << rr_idx);
                    ptp_tx_cnt          <= 6'd0;
                    ptp_wait_cnt        <= 14'd0;
                    be_tx_state         <= BE_TX_PTP_DATA;
                end
                BE_TX_PTP_DATA: begin
                    ptp_read_enable <= (8'd1 << rr_idx);
                    if (ptp_read_valid[rr_idx]) begin
                        be_gt_tx_data       <= {8'b0, ptp_data[rr_idx*8+:8]};
                        be_gt_tx_data_valid <= 1'b1;
                        ptp_wait_cnt        <= 14'd0;
                        if (ptp_tx_cnt == BE_PTP_FRAME_BYTES - 6'd1) begin
                            ptp_read_enable <= 8'd0;
                            be_tx_state     <= BE_TX_IDLE;
                        end else begin
                            ptp_tx_cnt <= ptp_tx_cnt + 6'd1;
                        end
                    end else if (ptp_wait_cnt >= BE_PTP_WAIT_MAX) begin
                        // FIFO 中只残留帧头或部分数据时，不能让 BE 上行永久卡死。
                        ptp_wait_cnt        <= 14'd0;
                        ptp_read_enable     <= 8'd0;
                        be_gt_tx_data       <= 16'hbc3c;
                        be_gt_tx_data_valid <= 1'b0;
                        be_tx_state         <= BE_TX_IDLE;
                    end else begin
                        be_gt_tx_data       <= 16'hbc3c;
                        be_gt_tx_data_valid <= 1'b0;
                        ptp_wait_cnt        <= ptp_wait_cnt + 14'd1;
                    end
                end
                default: begin
                    ptp_read_enable     <= 8'd0;
                    be_gt_tx_data       <= 16'hbc3c;
                    be_gt_tx_data_valid <= 1'b0;
                    be_tx_state <= BE_TX_IDLE;
                end
            endcase
        end
    end

    //--------------------------------
    // 1ch GTX interface (BE link to stage2), no clock sync
    //--------------------------------
    // 125M GTX ref clk input
    wire be_clk_gtx_125M;
    IBUFDS_GTE2 instance_ibufgds_gtx_refclk_1ch (
        .I    (gt_refclk4_p),
        .IB   (gt_refclk4_n),
        .O    (be_clk_gtx_125M),
        .CEB  (1'b0),
        .ODIV2()
    );

    // BE 侧信号已在前置声明处（generate 之前）声明，此处不再重复
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
        .rst_n                   (be_gt_link_up && sysrst_glb_n),
        .be_clk_rxoutclk_bufg    (be_clk_rxoutclk_bufg),
        .be_gt_rx_data           (be_gt_rx_data),
        .be_gt_rx_data_valid     (be_gt_rx_data_valid),
        .clk_txoutclk_bufg       (clk_txoutclk_bufg),
        .slow_control_data       (user_tx_data),
        .slow_control_data_valid (user_tx_data_valid),
        .ptp_start               (ptp_start),
        .ptp_start_valid         (ptp_start_valid),
        .timestamp_rx_delay      (timestamp_rx_delay),
        .timestamp_rx_delay_valid(timestamp_rx_delay_valid)
    );

    //--------------------------------
    // Slow-control transfer counters
    //--------------------------------
    // RX counter: slow-control words received from stage2 on the BE GT RX
    //   (be_clk_rxoutclk_bufg domain), addr field = {board(1~8), payload}
    //   detect rising edge of be_gt_rx_data_valid (one per received word)
    reg [15:0] sc_rx_cnt;
    reg        be_gt_rx_data_valid_d;
    always @(posedge be_clk_rxoutclk_bufg or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n) begin
            sc_rx_cnt              <= 16'd0;
            be_gt_rx_data_valid_d  <= 1'b0;
        end else begin
            be_gt_rx_data_valid_d <= be_gt_rx_data_valid;
            if (be_gt_rx_data_valid && !be_gt_rx_data_valid_d)
                sc_rx_cnt <= sc_rx_cnt + 16'd1;
        end
    end

    // TX counter: slow-control words forwarded to underwater on FE TX ch0
    //   (clk_txoutclk_bufg[0] domain); count rising edges of the valid strobe
    reg [15:0] sc_tx_uw_cnt;
    reg        user_tx_data_valid_d;
    always @(posedge clk_txoutclk_bufg[0] or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n) begin
            sc_tx_uw_cnt         <= 16'd0;
            user_tx_data_valid_d <= 1'b0;
        end else begin
            user_tx_data_valid_d <= user_tx_data_valid[0];
            if (user_tx_data_valid[0] && !user_tx_data_valid_d)
                sc_tx_uw_cnt <= sc_tx_uw_cnt + 16'd1;
        end
    end

    // ACK TX counter: W-packet ack frames (FFF3+FFFF) sent to stage2 on the BE GT TX
    //   (be_clk_txoutclk_bufg domain), one per BE_TX_ACK_HDR cycle
    reg [15:0] ack_tx_cnt;
    always @(posedge be_clk_txoutclk_bufg or negedge sysrst_glb_n) begin
        if (!sysrst_glb_n)
            ack_tx_cnt <= 16'd0;
        else if (be_tx_state == BE_TX_ACK_HDR)
            ack_tx_cnt <= ack_tx_cnt + 16'd1;
    end

    //--------------------------------
    // ILA debug (added for board bring-up)
    //--------------------------------
    // ila_be_tx u_ila_be_tx (
    //     .clk   (be_clk_txoutclk_bufg),
    //     .probe0 (be_tx_state[2:0]),
    //     .probe1 (rr_idx[2:0]),
    //     .probe2 (evt_tx_cnt[6:0]),
    //     .probe3 (ptp_tx_cnt[2:0]),
    //     .probe4 (be_gt_tx_data[15:0]),
    //     .probe5 (be_gt_tx_data_valid),
    //     .probe6 (sc_rd_en[0]),
    //     .probe7 (sc_fifo_empty[0]),
    //     .probe8 (sc_fifo_valid[0]),
    //     .probe9 (sc_fifo_dout[15:0]),
    //     .probe10(adc_rd_en[0]),
    //     .probe11(adc_fifo_prog_empty[0]),
    //     .probe12(adc_fifo_valid[0]),
    //     .probe13(adc_fifo_dout[15:0]),
    //     .probe14(ptp_read_enable[0]),
    //     .probe15(ptp_read_empty[0]),
    //     .probe16(ptp_read_valid[0]),
    //     .probe17(ptp_data[7:0])
    // );

    ila_fe_tx u_ila_fe_tx (
        .clk   (clk_txoutclk_bufg[0]),
        .probe0(user_tx_data[15:0]),
        .probe1(user_tx_data_valid[0]),
        .probe2(ptp_start),
        .probe3(ptp_start_valid),
        .probe4(timestamp_rx_delay[15:0]),
        .probe5(timestamp_rx_delay_valid[0]),
        .probe6(gt_tx_data[15:0]),
        .probe7(gt_tx_data_valid[0]),
        .probe8(sc_tx_uw_cnt)
    );

    ila_be_rx u_ila_be_rx (
        .clk   (be_clk_rxoutclk_bufg),
        .probe0(be_gt_rx_data[15:0]),
        .probe1(be_gt_rx_data_valid),
        .probe2(be_rx_data_is_comma[1:0]),
        .probe3(be_gtx_rx_error),
        .probe4(be_gt_link_up),
        .probe5(be_gtx_cpll_is_lock),
        .probe6(sc_rx_cnt)
    );

    ila_be_tx u_ila_be_tx (
        .clk   (be_clk_txoutclk_bufg),
        .probe0(be_tx_state[3:0]),
        .probe1(rr_idx[2:0]),
        .probe2(ack_rd_en[0]),
        .probe3(sc_rd_en[0]),
        .probe4(be_gt_tx_data[15:0]),
        .probe5(be_gt_tx_data_valid),
        .probe6(ack_fifo_empty[0]),
        .probe7(ptp_tx_cnt[5:3]),
        .probe8(sc_fifo_empty[0]),
        .probe9(adc_fifo_prog_empty[0]),
        .probe10(ptp_read_enable[0]),
        .probe11(ptp_tx_cnt[2:0]),
        .probe12(ptp_data[7:0]),
        .probe13(ptp_read_valid[0]),
        .probe14(ptp_read_empty),
        .probe15(ack_tx_cnt)
    );

    //--------------------------------
    // ILA debug: FE RX path, channel 0 only (clk_rxoutclk_bufg[0] domain)
    //--------------------------------
    ila_fe_rx u_ila_fe_rx (
        .clk    (clk_rxoutclk_bufg[0]),
        .probe0 (user_rx_data[15:0]),
        .probe1 (user_rx_data_valid[0]),
        .probe2 (ack_pend[0]),
        .probe3 (sc_pend[0]),
        .probe4 (evt_pend[6:0]),
        .probe5 (ack_pend[0] && ~ack_fifo_full[0] && ~ack_wr_rst_busy[0]),
        .probe6 (ack_fifo_full[0]),
        .probe7 (ack_wr_rst_busy[0]),
        .probe8 (gt_link_up[0]),
        .probe9 (gtx_cpll_is_lock[0]),
        .probe10(sc_wr_rst_busy[0]),
        .probe11(adc_wr_rst_busy[0])
    );
endmodule
