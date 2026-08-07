`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: slow_control_manager
// Description: Stage1 slow-control receive & forward.
//   Receives 16-bit slow-control words from stage2 on the BE 1ch GT RX:
//     data[15:8] = underwater board select addr (1~8, maps to FE GT channel)
//     data[7:0]  = slow-control payload
//   Routes each word into the fifo_slow_control FIFO of the channel selected
//   by addr (write side in be_clk_rxoutclk_bufg domain), then reads it out on
//   that channel's clk_txoutclk_bufg domain and drives it onto the channel's
//   slow_control_data so time_sync forwards it on the FE GT TX.
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
    output wire [15:0] slow_control_data       [0:7],
    output wire        slow_control_data_valid [0:7]
    );

    wire [7:0] addr = be_gt_rx_data[15:8];

    wire [15:0] fifo_dout           [0:7];
    wire        fifo_full           [0:7];
    wire        fifo_empty          [0:7];
    wire        fifo_valid          [0:7];
    wire        fifo_wr_rst_busy    [0:7];
    wire        fifo_rd_rst_busy    [0:7];
    wire        fifo_wr_en          [0:7];
    wire        fifo_rd_en          [0:7];

    genvar ch;
    generate
        for (ch = 0; ch < 8; ch = ch + 1) begin : gen_fifo
            // only the FIFO matching addr (1~8) is written
            assign fifo_wr_en[ch] = be_gt_rx_data_valid &&
                                    (addr == ch + 8'd1) &&
                                    ~fifo_wr_rst_busy[ch];

            fifo_slow_control instance_fifo_slow_control (
                .rst         (~rst_n),
                .wr_clk      (be_clk_rxoutclk_bufg),
                .rd_clk      (clk_txoutclk_bufg[ch]),
                .din         (be_gt_rx_data),
                .wr_en       (fifo_wr_en[ch]),
                .rd_en       (fifo_rd_en[ch]),
                .dout        (fifo_dout[ch]),
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
            assign slow_control_data[ch]     = fifo_dout[ch];
        end
    endgenerate

endmodule
