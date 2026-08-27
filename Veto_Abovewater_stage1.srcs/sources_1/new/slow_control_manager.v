`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: slow_control_manager
// Description: Stage1 slow-control receive & forward.
//   Receives 16-bit slow-control words from stage2 on the BE 1ch GT RX.
//
//   Protocol (addr[15:8] determines command type):
//     addr 1~8     → slow-control: {ch(1~8), data[7:0]} → forward to underwater board ch
//     addr 0xE1~0xE8 → PTP delay set (2-word):
//                         word1: {0xE1~0xE8, xx}        → select channel (ch = addr[3:0]-1)
//                         word2: {xx, delay[15:0]}      → latch delay value for that channel
//     addr 0xF1~0xF8 → PTP start: {0xF1~0xF8, xx}      → start_ptp[ch] one-cycle pulse
//////////////////////////////////////////////////////////////////////////////////

module slow_control_manager(
    input  wire       rst_n,

    // write side (BE RX domain, from interface_gtx_1ch)
    input  wire       be_clk_rxoutclk_bufg,
    input  wire [15:0] be_gt_rx_data,
    input  wire       be_gt_rx_data_valid,

    // read side (per FE channel TX domain)
    input  wire [7:0] clk_txoutclk_bufg,

    // per-channel slow-control output (into time_sync slow_control_data)
    output wire [127:0] slow_control_data,
    output wire [7:0]   slow_control_data_valid,

    // per-channel PTP start pulse (1 cycle, in be_clk_rxoutclk_bufg domain)
    output reg  [7:0]   start_ptp,

    // per-channel PTP delay value (16-bit per channel, be_clk_rxoutclk_bufg domain)
    output reg  [127:0] timestamp_rx_delay,
    output reg  [7:0]   timestamp_rx_delay_valid
    );

    wire [7:0] addr;
    assign addr = be_gt_rx_data[15:8];

    //--------------------------------
    // Command type decode
    //--------------------------------
    wire is_slow_ctrl;   // addr 1~8
    wire is_ptp_start;   // addr 0xF1~0xF8
    wire is_ptp_delay;   // addr 0xE1~0xE8

    assign is_slow_ctrl = be_gt_rx_data_valid && (addr >= 8'd1) && (addr <= 8'd8);
    assign is_ptp_start = be_gt_rx_data_valid && (addr[7:4] == 4'hF) && (addr[3:0] >= 4'd1) && (addr[3:0] <= 4'd8);
    assign is_ptp_delay = be_gt_rx_data_valid && (addr[7:4] == 4'hE) && (addr[3:0] >= 4'd1) && (addr[3:0] <= 4'd8);

    wire [2:0] ptp_start_ch;
    wire [2:0] ptp_delay_ch;
    assign ptp_start_ch = addr[3:0] - 4'd1;  // 0xF1→ch0, 0xF2→ch1, ..., 0xF8→ch7
    assign ptp_delay_ch = addr[3:0] - 4'd1;  // 0xE1→ch0, 0xE2→ch1, ..., 0xE8→ch7

    //--------------------------------
    // PTP start: single-cycle pulse on rising edge
    //--------------------------------
    reg ptp_start_cmd_d;
    always @(posedge be_clk_rxoutclk_bufg or negedge rst_n) begin
        if (!rst_n)
            ptp_start_cmd_d <= 1'b0;
        else
            ptp_start_cmd_d <= is_ptp_start;
    end

    wire ptp_start_pulse;
    assign ptp_start_pulse = is_ptp_start & ~ptp_start_cmd_d;

    always @(posedge be_clk_rxoutclk_bufg or negedge rst_n) begin
        if (!rst_n)
            start_ptp <= 8'b0;
        else if (ptp_start_pulse)
            start_ptp[ptp_start_ch] <= 1'b1;
        else
            start_ptp <= 8'b0;
    end

    //--------------------------------
    // PTP delay: 2-word protocol
    //   word1 (0xE1~0xE8): select channel, save ch index
    //   word2 (any addr):  latch delay value into saved channel
    //--------------------------------
    reg        ptp_delay_pending;
    reg [2:0]  ptp_delay_ch_saved;

    always @(posedge be_clk_rxoutclk_bufg or negedge rst_n) begin
        if (!rst_n) begin
            ptp_delay_pending  <= 1'b0;
            ptp_delay_ch_saved <= 3'b0;
        end else if (is_ptp_delay && !ptp_delay_pending) begin
            // word1: save channel, wait for word2
            ptp_delay_pending  <= 1'b1;
            ptp_delay_ch_saved <= ptp_delay_ch;
        end else if (ptp_delay_pending && be_gt_rx_data_valid) begin
            // word2: consumed, clear pending
            ptp_delay_pending <= 1'b0;
        end
    end

    // word2 latches delay value
    always @(posedge be_clk_rxoutclk_bufg or negedge rst_n) begin
        if (!rst_n) begin
            timestamp_rx_delay       <= 128'b0;
            timestamp_rx_delay_valid <= 8'b0;
        end else if (ptp_delay_pending && be_gt_rx_data_valid) begin
            // latch 16-bit delay into the selected channel
            timestamp_rx_delay[ptp_delay_ch_saved*16 +: 16] <= be_gt_rx_data;
            timestamp_rx_delay_valid[ptp_delay_ch_saved]     <= 1'b1;
        end
    end

    //--------------------------------
    // Slow control FIFOs (addr 1~8)
    //--------------------------------
    wire [127:0] fifo_dout;
    wire [7:0]   fifo_full;
    wire [7:0]   fifo_empty;
    wire [7:0]   fifo_valid;
    wire [7:0]   fifo_wr_rst_busy;
    wire [7:0]   fifo_rd_rst_busy;
    wire [7:0]   fifo_wr_en;
    wire [7:0]   fifo_rd_en;

    genvar ch;
    generate
        for (ch = 0; ch < 8; ch = ch + 1) begin : gen_fifo
            // only the FIFO matching addr (1~8) is written
            // ptp_delay word2 also has valid addr but doesn't match ch+1 when addr > 8
            assign fifo_wr_en[ch] = is_slow_ctrl &&
                                    (addr == ch + 8'd1) &&
                                    ~fifo_wr_rst_busy[ch];

            fifo_slow_control instance_fifo_slow_control (
                .rst         (~rst_n),
                .wr_clk      (be_clk_rxoutclk_bufg),
                .rd_clk      (clk_txoutclk_bufg[ch]),
                .din         (be_gt_rx_data),
                .wr_en       (fifo_wr_en[ch]),
                .rd_en       (fifo_rd_en[ch]),
                .dout        (fifo_dout[ch*16 +: 16]),
                .full        (fifo_full[ch]),
                .empty       (fifo_empty[ch]),
                .valid       (fifo_valid[ch]),
                .wr_rst_busy (fifo_wr_rst_busy[ch]),
                .rd_rst_busy (fifo_rd_rst_busy[ch])
            );

            // standard mode: rd_en pops (keep draining while data present),
            // valid=1 means dout currently holds valid data to present on the channel.
            assign fifo_rd_en[ch]       = ~fifo_empty[ch] && ~fifo_rd_rst_busy[ch];
            assign slow_control_data_valid[ch] = fifo_valid[ch];
            assign slow_control_data[ch*16 +: 16] = fifo_dout[ch*16 +: 16];
        end
    endgenerate

endmodule
