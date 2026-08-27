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
    output wire [127:0] slow_control_data,
    output wire [7:0]   slow_control_data_valid,

    // per-channel PTP start pulse (1 cycle, in be_clk_rxoutclk_bufg domain)
    output reg  [7:0]   start_ptp
    );

    wire [7:0] addr;
    assign addr = be_gt_rx_data[15:8];

    //--------------------------------
    // PTP command detection
    //   addr 0xF0~0xF7 → start_ptp[ch] one-cycle pulse
    //   addr 0xF0 → ch0, 0xF1 → ch1, ..., 0xF7 → ch7
    //--------------------------------
    wire ptp_cmd_valid;
    assign ptp_cmd_valid = be_gt_rx_data_valid && (addr[7:4] == 4'hF) && (addr[3] == 1'b0);

    reg ptp_cmd_valid_d;
    always @(posedge be_clk_rxoutclk_bufg or negedge rst_n) begin
        if (!rst_n) begin
            ptp_cmd_valid_d <= 1'b0;
        end else begin
            ptp_cmd_valid_d <= ptp_cmd_valid;
        end
    end

    // rising edge → one-cycle pulse
    wire ptp_cmd_pulse;
    assign ptp_cmd_pulse = ptp_cmd_valid & ~ptp_cmd_valid_d;

    always @(posedge be_clk_rxoutclk_bufg or negedge rst_n) begin
        if (!rst_n) begin
            start_ptp <= 8'b0;
        end else begin
            if (ptp_cmd_pulse)
                start_ptp[addr[2:0]] <= 1'b1;
            else
                start_ptp <= 8'b0;
        end
    end

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
