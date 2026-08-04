// # time sync manager
module time_sync_manager(
    input  wire clk_txoutclk_bufg,
    input  wire clk_rxoutclk_bufg,
    input  wire clk_sys_400M,
    input  wire clk_drp_100M,
    input  wire clk_uart,               // ptp output results by fifo

    // gtx data
    output reg  [15:0] gt_tx_data,
    output reg  gt_tx_data_valid,
    input  wire [15:0] gt_rx_data,
    input  wire gt_rx_data_valid,
    input  wire [ 1:0] gt_rx_data_is_comma,

    // *user data*
    input  wire [15:0] user_tx_data,
    input  wire user_tx_data_valid,
    output wire [15:0] user_rx_data,
    output wire user_rx_data_valid,

    // timestamp
    output wire [63:0] timestamp_tx,
    output wire [63:0] timestamp_rx,
    input  wire ptp_start,              // rising edge trigger
    input  wire [15:0] ptp_value,       // delay value
    input  wire ptp_value_valid,
    input  wire [63:0] tx_load_value,
    input  wire tx_load,

    // output by uart, fifo interface
    output wire [7:0] uart_data_out,
    input  wire uart_read_enable,
    output wire uart_read_empty,
    output wire uart_read_valid,

    // data alignment and pma reset
    input  wire gt_rx_error,
    output reg  gt_pma_rst_n,
    input  wire gt_rx_rst_done,

    // debug
    output wire [3:0] flags
    );

    // ## 1. data alignment
    // pma reset to ensure the received data is valid
    reg  gt_pma_rst_n_flag;
    always @(posedge clk_rxoutclk_bufg) begin
        if (~gt_rx_error) begin
            if (&gt_rx_data_is_comma) begin
                gt_pma_rst_n_flag <= (gt_rx_data == 16'hbc3c);
            end else begin
                gt_pma_rst_n_flag <= 1;
            end
        end else begin
            gt_pma_rst_n_flag <= 0;
        end
    end

    // if reset done, update reset, else set to high
    always @(posedge clk_drp_100M) begin
        if (gt_rx_rst_done) begin
            gt_pma_rst_n <= gt_pma_rst_n_flag;
        end else begin  // a reset will keep 2 periods
            gt_pma_rst_n <= 1;
        end
    end


    // ## 2. time stamp alignment
    wire ptp_working;
    wire ptp_data_is_k;
    wire rx_data_is_ptp;
    wire [15:0] tx_data_ptp;
    ptp_manager instance_ptp_manager (
        .clk_txoutclk_bufg  (clk_txoutclk_bufg),
        .clk_rxoutclk_bufg  (clk_rxoutclk_bufg),
        .clk_sys_400M       (clk_sys_400M),
        .clk_uart           (clk_uart),

        .ptp_start          (ptp_start),
        .ptp_value          (ptp_value),
        .ptp_value_valid    (ptp_value_valid),

        // gt data
        .gt_rx_data         (gt_rx_data),
        .gt_rx_data_valid   (gt_rx_data_valid),
        .tx_data_ptp        (tx_data_ptp),
        .ptp_working        (ptp_working),
        .ptp_data_is_k      (ptp_data_is_k),
        .rx_data_is_ptp     (rx_data_is_ptp),
    
        .timestamp_tx       (timestamp_tx),
        .timestamp_rx       (timestamp_rx),
        .tx_load_value      (tx_load_value),
        .tx_load            (tx_load),

        // uart output
        .uart_data_out      (uart_data_out),
        .uart_read_enable   (uart_read_enable),
        .uart_read_empty    (uart_read_empty),
        .uart_read_valid    (uart_read_valid),

        // debug
        .flags              (flags)
    );


    // tx data assign
    always @(posedge clk_txoutclk_bufg) begin
        if (ptp_working) begin
            gt_tx_data <= tx_data_ptp;
            gt_tx_data_valid <= ~ptp_data_is_k;
        end else begin
            gt_tx_data <= user_tx_data_valid ? user_tx_data : 16'hbc3c;
            gt_tx_data_valid <= user_tx_data_valid;
        end
    end

    // rx data assign
    assign user_rx_data = gt_rx_data;
    assign user_rx_data_valid = gt_rx_data_valid & ~rx_data_is_ptp;
endmodule

module ptp_manager (
    input  wire clk_txoutclk_bufg,
    input  wire clk_rxoutclk_bufg,
    input  wire clk_sys_400M,
    input  wire clk_uart,

    input  wire ptp_start,
    input  wire [63:0] ptp_value,
    input  wire ptp_value_valid,

    // gt data
    input  wire [15:0] gt_rx_data,
    input  wire gt_rx_data_valid,
    output reg  [15:0] tx_data_ptp,
    output reg  ptp_working,
    output reg  ptp_data_is_k,
    output reg  rx_data_is_ptp,
    
    output reg  [63:0] timestamp_tx,
    output reg  [63:0] timestamp_rx,
    input  wire [63:0] tx_load_value,
    input  wire tx_load,

    // uart output
    output wire [7:0] uart_data_out,
    input  wire uart_read_enable,
    output wire uart_read_empty,
    output wire uart_read_valid,

    // debug
    output wire [3:0] flags
    );

    // TX states
    reg  [1:0] states_ptp_tx;
    reg  [3:0] counter_ptp_tx;

    reg  ptp_start_reg;
    reg  ptp_start_delay;
    reg  ptp_value_valid_reg;
    
    always @(posedge clk_txoutclk_bufg) begin
        ptp_start_reg <= ptp_start;
        ptp_start_delay <= ptp_start_reg;
        ptp_value_valid_reg <= ptp_value_valid;
    end

    // RX states
    reg  [1:0] states_ptp_rx;
    reg  [4:0] counter_ptp_rx;

    wire fifo_t2_t3_valid;  // rx write, tx read

    // PTP data
    reg  [63:0] timestamp_t1_data;  // tx
    reg  ptp_t1_valid;
    reg  [63:0] timestamp_t2_data;  // rx
    reg  ptp_t2_valid;
    reg  [63:0] timestamp_t2_received;  // rx
    reg  [63:0] timestamp_t3_data;  // tx
    reg  [63:0] timestamp_t3_received;  // rx
    reg  ptp_t3_valid;
    reg  flag_rcv;
    reg  [63:0] timestamp_t4_data;  // rx
    reg  ptp_t4_valid;
    reg  [63:0] timestamp_t5_data;  // tx
    reg  [63:0] timestamp_t5_update;// rx
    reg  timestamp_t5_valid;
    
    // tx timestamp
    always @(posedge clk_txoutclk_bufg) begin
        if (tx_load) begin
            timestamp_tx <= tx_load_value;
        end else begin
            timestamp_tx <= timestamp_tx + 1;
        end
    end

    // rx timestamp
    always @(posedge clk_rxoutclk_bufg) begin
        if (timestamp_t5_valid) begin
            timestamp_rx <= timestamp_t5_update;
        end else begin
            timestamp_rx <= timestamp_rx + 1;
        end
    end

    // TDC results
    wire [63:0] tdc_phase_results;  // 300MHz clock
    tdc_phase_measure instance_tdc_phase_measure (
        .clk    (clk_sys_400M),
        .clk_tx (flags[0]|flags[1]),
        .clk_rx (flags[2]|flags[3]),
        .tdc_phase_results  (tdc_phase_results)
    );

    reg  [3:0] counter_tdc_fifo_write;
    wire [63:0] tdc_phase_results_tx;
    reg  [63:0] tdc_phase_results_tx_data;
    fifo_64b_async_64b instance_fifo_tdc_phase_measure_tx (
        .wr_clk (clk_sys_400M),
        .rd_clk (clk_txoutclk_bufg),
        .din    (tdc_phase_results),
        .wr_en  (&counter_tdc_fifo_write),
        .rd_en  (1),
        .dout   (tdc_phase_results_tx),
        .full   (),
        .empty  (),
        .valid  ()
    );
    wire [63:0] tdc_phase_results_rx;
    reg  [63:0] tdc_phase_results_rx_data;
    reg  [63:0] tdc_phase_results_rx_rcv;
    fifo_64b_async_64b instance_fifo_tdc_phase_measure_rx (
        .wr_clk (clk_sys_400M),
        .rd_clk (clk_rxoutclk_bufg),
        .din    (tdc_phase_results),
        .wr_en  (&counter_tdc_fifo_write),
        .rd_en  (1),
        .dout   (tdc_phase_results_rx),
        .full   (),
        .empty  (),
        .valid  ()
    );
    always @(posedge clk_sys_400M) begin
        counter_tdc_fifo_write <= counter_tdc_fifo_write + 1;
    end

    // timestamp buffers
    wire [63:0] timestamp_t2_buffer;    // rx in, tx out
    wire buffer_t2_valid;
    wire [63:0] timestamp_t3_buffer;    // rx in, tx out
    wire [63:0] timestamp_t4_buffer;    // tx in, rx out
    
    buffer_timestamps instance_buffer_timestamps (
        .clk_txoutclk_bufg  (clk_txoutclk_bufg),
        .clk_rxoutclk_bufg  (clk_rxoutclk_bufg),

        // t2
        .timestamp_t2_data  (timestamp_t2_data),
        .fifo_t2_wren       (ptp_t2_valid),
        .timestamp_t2_buffer(timestamp_t2_buffer),
        .fifo_t2_valid      (buffer_t2_valid),

        // t3
        .timestamp_rx       (timestamp_rx),
        .timestamp_t3_buffer(timestamp_t3_buffer),
        
        // t4
        .timestamp_tx       (timestamp_tx),
        .timestamp_t4_buffer(timestamp_t4_buffer)
    );

    // uart readout
    reg  [63:0] data_output_tx;
    reg  data_output_tx_valid;
    reg  [63:0] data_output_rx;
    reg  data_output_rx_valid;
    buffer_timestamp_to_uart instance_buffer_timestamp_to_uart (
        .clk_txoutclk_bufg  (clk_txoutclk_bufg),
        .clk_rxoutclk_bufg  (clk_rxoutclk_bufg),
        .clk_uart           (clk_uart),

        .data_tx            (data_output_tx),
        .data_tx_valid      (data_output_tx_valid),
        .data_rx            (data_output_rx),
        .data_rx_valid      (data_output_rx_valid),

        .data_out   (uart_data_out),
        .rd_en      (uart_read_enable),
        .valid      (uart_read_valid),
        .empty      (uart_read_empty)
    );

    // TX mainloop
    always @(posedge clk_txoutclk_bufg) begin
        case (states_ptp_tx)
            // idle, wait to send t1 or t5 or t2 t3
            0 : begin
                if (ptp_start_reg & ~ptp_start_delay) begin
                    if (~ptp_value_valid_reg) begin
                        // t1, master
                        states_ptp_tx <= 1;
                        timestamp_t1_data <= timestamp_tx;
                    end else begin
                        // t5, master
                        states_ptp_tx <= 3;
                        timestamp_t5_data <= timestamp_tx + ptp_value;
                    end
                end else if (buffer_t2_valid) begin
                    // t2 t3, slave
                    states_ptp_tx <= 2;
                    timestamp_t3_data <= timestamp_t3_buffer;
                    // tdc_phase_results_tx_data <= tdc_phase_results_tx;
                end
                // idle
                counter_ptp_tx <= 0;
                ptp_working <= 0;
                tx_data_ptp <= 16'hbc3c;
                ptp_data_is_k <= 1;
                data_output_tx_valid <= 0;
                ptp_t1_valid <= 0;
                ptp_t3_valid <= 0;
            end
            // send t1 flag
            1 : begin
                // ptp t1
                ptp_working <= 1;
                tx_data_ptp <= 16'h1cf7;
                ptp_data_is_k <= 1;
                states_ptp_tx <= 0;
                data_output_tx <= timestamp_t1_data;
                data_output_tx_valid <= 1;
                ptp_t1_valid <= 1;
            end
            // send t2 and t3 data
            2 : begin
                ptp_working <= 1;
                counter_ptp_tx <= counter_ptp_tx + 1;
                ptp_t3_valid <= 1;
                tdc_phase_results_tx_data <= tdc_phase_results_tx;
                case (counter_ptp_tx)
                    0 : begin
                        tx_data_ptp <= 16'h3cf7;
                        ptp_data_is_k <= 1;
                    end
                    1 : begin
                        tx_data_ptp <= timestamp_t2_buffer[63:48];
                        ptp_data_is_k <= 0;
                    end
                    2 : begin
                        tx_data_ptp <= timestamp_t2_buffer[47:32];
                        ptp_data_is_k <= 0;
                    end
                    3 : begin
                        tx_data_ptp <= timestamp_t2_buffer[31:16];
                        ptp_data_is_k <= 0;
                    end
                    4 : begin
                        tx_data_ptp <= timestamp_t2_buffer[15: 0];
                        ptp_data_is_k <= 0;
                    end
                    5 : begin
                        tx_data_ptp <= timestamp_t3_data[63:48];
                        ptp_data_is_k <= 0;
                    end
                    6 : begin
                        tx_data_ptp <= timestamp_t3_data[47:32];
                        ptp_data_is_k <= 0;
                    end
                    7 : begin
                        tx_data_ptp <= timestamp_t3_data[31:16];
                        ptp_data_is_k <= 0;
                    end
                    8 : begin
                        tx_data_ptp <= timestamp_t3_data[15: 0];
                        ptp_data_is_k <= 0;
                    end
                    9 : begin
                        tx_data_ptp <= tdc_phase_results_tx_data[63:48];
                        ptp_data_is_k <= 0;
                    end
                    10: begin
                        tx_data_ptp <= tdc_phase_results_tx_data[47:32];
                        ptp_data_is_k <= 0;
                    end
                    11: begin
                        tx_data_ptp <= tdc_phase_results_tx_data[31:16];
                        ptp_data_is_k <= 0;
                    end
                    12: begin
                        tx_data_ptp <= tdc_phase_results_tx_data[15: 0];
                        ptp_data_is_k <= 0;
                        states_ptp_tx <= 0;
                    end
                endcase
            end
            // send t5 data
            3 : begin
                ptp_working <= 1;
                counter_ptp_tx <= counter_ptp_tx + 1;
                case (counter_ptp_tx)
                    0 : begin
                        tx_data_ptp <= 16'h5cf7;
                        ptp_data_is_k <= 1;
                    end
                    1 : begin
                        tx_data_ptp <= timestamp_t5_data[63:48];
                        ptp_data_is_k <= 0;
                    end
                    2 : begin
                        tx_data_ptp <= timestamp_t5_data[47:32];
                        ptp_data_is_k <= 0;
                    end
                    3 : begin
                        tx_data_ptp <= timestamp_t5_data[31:16];
                        ptp_data_is_k <= 0;
                    end
                    4 : begin
                        tx_data_ptp <= timestamp_t5_data[15: 0];
                        ptp_data_is_k <= 0;
                        states_ptp_tx <= 0;
                    end
                endcase
            end
        endcase
    end

    // RX mainloop
    always @(posedge clk_rxoutclk_bufg) begin
        case (states_ptp_rx)
            // idle, wait to receive t1 or t5 or t2 t3
            0 : begin
                if (~gt_rx_data_valid) begin
                    if (gt_rx_data == 16'h1cf7) begin
                        // t1, slave
                        states_ptp_rx <= 1;
                        timestamp_t2_data <= timestamp_rx;
                        rx_data_is_ptp <= 0;
                    end else if (gt_rx_data == 16'h3cf7) begin
                        // t2 t3, master
                        states_ptp_rx <= 2;
                        timestamp_t4_data <= timestamp_t4_buffer;
                        rx_data_is_ptp <= 1;
                        // tdc_phase_results_rx_data <= tdc_phase_results_rx;
                    end else if (gt_rx_data == 16'h5cf7) begin
                        // t5, slave
                        states_ptp_rx <= 3;
                        rx_data_is_ptp <= 1;
                    end else begin
                        rx_data_is_ptp <= 0;
                    end
                end else begin
                    rx_data_is_ptp <= 0;
                end
                // idle
                counter_ptp_rx <= 0;
                ptp_t2_valid <= 0;
                timestamp_t5_valid <= 0;
                data_output_rx_valid <= 0;
                ptp_t4_valid <= 0;
            end
            // receive t1, let tx send t2 t3
            1 : begin
                states_ptp_rx <= 0;
                ptp_t2_valid <= 1;
            end
            // receive t2 t3, send out
            2 : begin
                counter_ptp_rx <= counter_ptp_rx + 1;
                rx_data_is_ptp <= 1;
                ptp_t4_valid <= 1;
                tdc_phase_results_rx_data <= tdc_phase_results_rx;
                case (counter_ptp_rx)
                    0 : timestamp_t2_received[63:48] <= gt_rx_data;
                    1 : timestamp_t2_received[47:32] <= gt_rx_data;
                    2 : timestamp_t2_received[31:16] <= gt_rx_data;
                    3 : timestamp_t2_received[15: 0] <= gt_rx_data;
                    4 : timestamp_t3_received[63:48] <= gt_rx_data;
                    5 : timestamp_t3_received[47:32] <= gt_rx_data;
                    6 : timestamp_t3_received[31:16] <= gt_rx_data;
                    7 : timestamp_t3_received[15: 0] <= gt_rx_data;
                    8 : tdc_phase_results_rx_rcv[63:48] <= gt_rx_data;
                    9 : tdc_phase_results_rx_rcv[47:32] <= gt_rx_data;
                    10: tdc_phase_results_rx_rcv[31:16] <= gt_rx_data;
                    11: tdc_phase_results_rx_rcv[15: 0] <= gt_rx_data;
                    12: begin
                        data_output_rx_valid <= 1;
                        data_output_rx <= timestamp_t2_received;
                    end
                    13: begin
                        data_output_rx_valid <= 1;
                        data_output_rx <= timestamp_t3_received;
                    end
                    14: begin
                        data_output_rx_valid <= 1;
                        data_output_rx <= timestamp_t4_data;
                    end
                    15: begin
                        data_output_rx_valid <= 1;
                        data_output_rx <= tdc_phase_results_rx_data;
                    end
                    16: begin
                        data_output_rx_valid <= 1;
                        data_output_rx <= tdc_phase_results_rx_rcv;
                        states_ptp_rx <= 0;
                    end
                endcase
            end
            // receive t5, update
            3 : begin
                counter_ptp_rx <= counter_ptp_rx + 1;
                rx_data_is_ptp <= 1;
                case (counter_ptp_rx)
                    0 : timestamp_t5_update[63:48] <= gt_rx_data;
                    1 : timestamp_t5_update[47:32] <= gt_rx_data;
                    2 : timestamp_t5_update[31:16] <= gt_rx_data;
                    3 : timestamp_t5_update[15: 0] <= gt_rx_data;
                    4 : begin
                        timestamp_t5_valid <= 1;
                        states_ptp_rx <= 0;
                    end
                endcase
            end
        endcase
    end

    // debug
    assign flags = {
        ptp_t4_valid,
        ptp_t3_valid,
        ptp_t2_valid,
        ptp_t1_valid
    };
endmodule

module buffer_timestamps (
    input  wire clk_txoutclk_bufg,
    input  wire clk_rxoutclk_bufg,

    // t2
    input  wire [63:0] timestamp_t2_data,
    input  wire fifo_t2_wren,
    output wire [63:0] timestamp_t2_buffer,
    output wire fifo_t2_valid,

    // t3
    input  wire [63:0] timestamp_rx,
    output wire [63:0] timestamp_t3_buffer,
    
    // t4
    input  wire [63:0] timestamp_tx,
    output wire [63:0] timestamp_t4_buffer
    );

    // T2 buffer, rx in, tx out
    reg  fifo_t2_rden;
    wire fifo_t2_empty;
    fifo_64b_async_64b instance_fifo_timestamp_t2 (
        .wr_clk (clk_rxoutclk_bufg),
        .rd_clk (clk_txoutclk_bufg),
        .din    (timestamp_t2_data),
        .wr_en  (fifo_t2_wren),
        .rd_en  (fifo_t2_rden),
        .dout   (timestamp_t2_buffer),
        .full   (),
        .empty  (fifo_t2_empty),
        .valid  (fifo_t2_valid)
    );
    always @(posedge clk_txoutclk_bufg) begin
        fifo_t2_rden <= ~fifo_t2_empty;
    end

    // T3 buffer, rx in, tx out
    reg  fifo_t3_wren;
    reg  fifo_t3_rden;
    wire fifo_t3_empty;
    fifo_64b_async_64b instance_fifo_timestamp_t3 (
        .wr_clk (clk_rxoutclk_bufg),
        .rd_clk (clk_txoutclk_bufg),
        .din    (timestamp_rx),
        .wr_en  (fifo_t3_wren),
        .rd_en  (1'b1),
        .dout   (timestamp_t3_buffer),
        .full   (),
        .empty  (fifo_t3_empty),
        .valid  ()
    );
    always @(posedge clk_rxoutclk_bufg) begin
        fifo_t3_wren <= ~fifo_t3_wren;
    end
    always @(posedge clk_txoutclk_bufg) begin
        fifo_t3_rden <= ~fifo_t3_empty;
    end

    // T4 buffer, tx in, rx out
    reg  fifo_t4_wren;
    reg  fifo_t4_rden;
    wire fifo_t4_empty;
    fifo_64b_async_64b instance_fifo_timestamp_t4 (
        .wr_clk (clk_txoutclk_bufg),
        .rd_clk (clk_rxoutclk_bufg),
        .din    (timestamp_tx),
        .wr_en  (fifo_t4_wren),
        .rd_en  (1'b1),
        .dout   (timestamp_t4_buffer),
        .full   (),
        .empty  (fifo_t4_empty),
        .valid  ()
    );
    always @(posedge clk_txoutclk_bufg) begin
        fifo_t4_wren <= ~fifo_t4_wren;
    end
    always @(posedge clk_rxoutclk_bufg) begin
        fifo_t4_rden <= ~fifo_t4_empty;
    end
endmodule

module buffer_timestamp_to_uart (
    input  wire clk_txoutclk_bufg,
    input  wire clk_rxoutclk_bufg,
    input  wire clk_uart,

    input  wire [63:0] data_tx,
    input  wire data_tx_valid,
    input  wire [63:0] data_rx,
    input  wire data_rx_valid,
    
    output wire [7:0] data_out,
    input  wire rd_en,
    output wire valid,
    output wire empty
    );

    wire [1:0] empty2;
    reg  [1:0] rden2;
    wire [1:0] valid2;

    // tx
    wire [7:0] tx_out;
    fifo_timestamp_to_uart instance_fifo_ptp_txdata_to_uart (
        .wr_clk (clk_txoutclk_bufg),
        .rd_clk (clk_uart),
        .din    (data_tx),
        .wr_en  (data_tx_valid),
        .rd_en  (rden2[0]),
        .dout   (tx_out),
        .full   (),
        .empty  (empty2[0]),
        .valid  (valid2[0])
    );

    // rx
    wire [7:0] rx_out;
    fifo_timestamp_to_uart instance_fifo_ptp_rxdata_to_uart (
        .wr_clk (clk_rxoutclk_bufg),
        .rd_clk (clk_uart),
        .din    (data_rx),
        .wr_en  (data_rx_valid),
        .rd_en  (rden2[1]),
        .dout   (rx_out),
        .full   (),
        .empty  (empty2[1]),
        .valid  (valid2[1])
    );

    // to uart
    reg  [7:0] fifo_uart_in;
    reg  fifo_uart_wren;
    fifo_uart instance_fifo_ptp_uart (
        .clk    (clk_uart),
        .din    (fifo_uart_in),
        .wr_en  (fifo_uart_wren),
        .rd_en  (rd_en),
        .dout   (data_out),
        .full   (),
        .empty  (empty),
        .valid  (valid)
    );

    // read control
    always @(posedge clk_uart) begin
        if (~empty2[0]) begin
            rden2 <= 2'b01;
        end else if (~empty2[1]) begin
            rden2 <= 2'b10;
        end else begin
            rden2 <= 2'b00;
        end
    end

    // write fifo
    always @(posedge clk_uart) begin
        fifo_uart_wren <= |valid2;

        if (valid2[0]) begin
            fifo_uart_in <= tx_out;
        end else if (valid2[1]) begin
            fifo_uart_in <= rx_out;
        end
    end
endmodule

module tdc_phase_measure #(
    parameter N_bins_bits = 8,
    parameter N_carry4 = 64
    ) (
    input  wire clk,
    input  wire clk_tx,
    input  wire clk_rx,
    output reg  [63:0] tdc_phase_results
    );

    reg  [23:0] counter_coarse;
    always @(posedge clk) begin
        counter_coarse <= counter_coarse + 1;
    end

    // system clock measure tx clock
    wire [N_bins_bits:0] tdc_rise_tx;
    wire [N_bins_bits:0] tdc_fall_tx;
    lib_tdc #(
        // for TDC
        .N_carry4(N_carry4),        // 25 carry4 per nanosecond
        .N_bins_bits(N_bins_bits)   // = log2(4*N_carry4)
    ) instance_tdc_tx_phase (
        // for TDC
        .clk    (clk),              // input clock
        .signal (clk_tx),           // input signal
        .tdc_raw_rise(tdc_rise_tx), // tdc output raw result. 1 + N, the first is enable signal
        .tdc_raw_fall(tdc_fall_tx)
    );

    // system clock measure rx clock
    wire [N_bins_bits:0] tdc_rise_rx;
    wire [N_bins_bits:0] tdc_fall_rx;
    lib_tdc #(
        // for TDC
        .N_carry4(N_carry4),        // 25 carry4 per nanosecond
        .N_bins_bits(N_bins_bits)   // = log2(4*N_carry4)
    ) instance_tdc_rx_phase (
        // for TDC
        .clk    (clk),              // input clock
        .signal (clk_rx),           // input signal
        .tdc_raw_rise(tdc_rise_rx), // tdc output raw result. 1 + N, the first is enable signal
        .tdc_raw_fall(tdc_fall_rx)
    );

    // output
    always @(posedge clk) begin
        if (tdc_rise_tx[N_bins_bits]) begin
            tdc_phase_results[63:40] <= counter_coarse;
            tdc_phase_results[39:32] <= tdc_rise_tx[7:0];
        end
        if (tdc_rise_rx[N_bins_bits]) begin
            tdc_phase_results[31: 8] <= counter_coarse;
            tdc_phase_results[ 7: 0] <= tdc_rise_rx[7:0];
        end
    end
endmodule
