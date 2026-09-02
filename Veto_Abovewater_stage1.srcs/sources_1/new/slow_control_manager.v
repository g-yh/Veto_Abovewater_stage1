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

    // per-channel PTP start (clk_txoutclk_bufg[ch] domain, from CDC FIFO)
    output wire [7:0]   ptp_start,
    output wire [7:0]   ptp_start_valid,

    // per-channel PTP delay (clk_txoutclk_bufg[ch] domain, from CDC FIFO)
    output wire [127:0] timestamp_rx_delay,
    output wire [7:0]   timestamp_rx_delay_valid
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
    // PTP start: write 1-bit pulse into FIFO
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

    wire ptp_fifo_wr_en;
    wire ptp_fifo_din;
    wire [2:0] ptp_fifo_wr_ch;
    assign ptp_fifo_wr_en = ptp_start_pulse;
    assign ptp_fifo_din   = 1'b1;
    assign ptp_fifo_wr_ch = ptp_start_ch;

    //--------------------------------
    // PTP delay: 2-word protocol, write into FIFO
    //--------------------------------
    reg        ptp_delay_pending;
    reg [2:0]  ptp_delay_ch_saved;

    always @(posedge be_clk_rxoutclk_bufg or negedge rst_n) begin
        if (!rst_n) begin
            ptp_delay_pending  <= 1'b0;
            ptp_delay_ch_saved <= 3'b0;
        end else if (is_ptp_delay && !ptp_delay_pending) begin
            ptp_delay_pending  <= 1'b1;
            ptp_delay_ch_saved <= ptp_delay_ch;
        end else if (ptp_delay_pending && be_gt_rx_data_valid) begin
            ptp_delay_pending <= 1'b0;
        end
    end

    wire ts_fifo_wr_en;
    wire [15:0] ts_fifo_din;
    wire [2:0]  ts_fifo_wr_ch;
    assign ts_fifo_wr_en = ptp_delay_pending && be_gt_rx_data_valid;
    assign ts_fifo_din   = be_gt_rx_data;
    assign ts_fifo_wr_ch = ptp_delay_ch_saved;

    //--------------------------------
    // Slow control FIFOs (addr 1~8)
    //--------------------------------

    genvar ch;
    generate
        for (ch = 0; ch < 8; ch = ch + 1) begin : gen_fifo

            //--------------------------------
            // Slow control FIFO (addr 1~8)
            //--------------------------------
            wire [15:0] fifo_dout_ch;
            wire        fifo_full_ch;
            wire        fifo_empty_ch;
            wire        fifo_valid_ch;
            wire        fifo_wr_rst_busy_ch;
            wire        fifo_rd_rst_busy_ch;
            wire        fifo_wr_en_ch;
            wire        fifo_rd_en_ch;

            assign fifo_wr_en_ch = is_slow_ctrl &&
                                   (addr == ch + 8'd1) &&
                                   ~fifo_wr_rst_busy_ch;

            fifo_slow_control instance_fifo_slow_control (
                .rst         (~rst_n),
                .wr_clk      (be_clk_rxoutclk_bufg),
                .rd_clk      (clk_txoutclk_bufg[ch]),
                .din         (be_gt_rx_data),
                .wr_en       (fifo_wr_en_ch),
                .rd_en       (fifo_rd_en_ch),
                .dout        (fifo_dout_ch),
                .full        (fifo_full_ch),
                .empty       (fifo_empty_ch),
                .valid       (fifo_valid_ch),
                .wr_rst_busy (fifo_wr_rst_busy_ch),
                .rd_rst_busy (fifo_rd_rst_busy_ch)
            );

            assign fifo_rd_en_ch = ~fifo_empty_ch && ~fifo_rd_rst_busy_ch;
            assign slow_control_data_valid[ch] = fifo_valid_ch;
            assign slow_control_data[ch*16 +: 16] = fifo_dout_ch;

            //--------------------------------
            // PTP start CDC FIFO (1-bit, be_clk_rxoutclk_bufg → clk_txoutclk_bufg)
            //--------------------------------
            wire ptp_fifo_empty;
            wire ptp_fifo_rd_rst_busy;

            fifo_ptp instance_fifo_ptp_start (
                .rst        (~rst_n),
                .wr_clk     (be_clk_rxoutclk_bufg),
                .rd_clk     (clk_txoutclk_bufg[ch]),
                .din        (ptp_fifo_din),
                .wr_en      (ptp_fifo_wr_en && (ptp_fifo_wr_ch == ch[2:0])),
                .rd_en      (~ptp_fifo_empty && ~ptp_fifo_rd_rst_busy),
                .dout       (),
                .full       (),
                .empty      (ptp_fifo_empty),
                .valid      (ptp_start_valid[ch]),
                .wr_rst_busy(),
                .rd_rst_busy(ptp_fifo_rd_rst_busy)
            );

            assign ptp_start[ch] = ptp_start_valid[ch];

            //--------------------------------
            // PTP delay CDC FIFO (16-bit, be_clk_rxoutclk_bufg → clk_txoutclk_bufg)
            //--------------------------------
            wire ts_fifo_empty;
            wire ts_fifo_rd_rst_busy;
            wire [15:0] ts_fifo_dout;

            fifo_timestamp instance_fifo_timestamp_delay (
                .rst        (~rst_n),
                .wr_clk     (be_clk_rxoutclk_bufg),
                .rd_clk     (clk_txoutclk_bufg[ch]),
                .din        (ts_fifo_din),
                .wr_en      (ts_fifo_wr_en && (ts_fifo_wr_ch == ch[2:0])),
                .rd_en      (~ts_fifo_empty && ~ts_fifo_rd_rst_busy),
                .dout       (ts_fifo_dout),
                .full       (),
                .empty      (ts_fifo_empty),
                .valid      (timestamp_rx_delay_valid[ch]),
                .wr_rst_busy(),
                .rd_rst_busy(ts_fifo_rd_rst_busy)
            );

            assign timestamp_rx_delay[ch*16 +: 16] = ts_fifo_dout;
        end
    endgenerate

endmodule
