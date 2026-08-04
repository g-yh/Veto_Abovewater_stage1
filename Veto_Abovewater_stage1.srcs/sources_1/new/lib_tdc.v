// TDC module (lite), time-to-digital converter
module lib_tdc #(
    // for TDC
    parameter N_carry4 = 50,    // 25 carry4 per nanosecond
    parameter N_bins_bits = 8   // = log2(4*N_carry4)
    ) (
    // for TDC
    input  wire clk,    // input clock
    input  wire signal, // input signal
    output reg  [N_bins_bits:0] tdc_raw_rise,   // output tdc raw result. 1 + N, the first is enable signal
                                tdc_raw_fall
    );
    // First, TDL line generates delay signals
    wire [4*N_carry4-1:0] signals_delay;
    module_tdl #(
        .N_carry4(N_carry4)
    ) instance_tdl (
        .clk(clk),
        .signal(signal),
        .signals_delay(signals_delay)
    );

    // Second, encoding, find highest one for rise edge and lowest one for fall edge
    wire [N_bins_bits-1:0]  high_one,
                            low_one;
    module_encode_high_one #(
        .N(N_carry4),    // N_carry4
        .N_bins_bits(N_bins_bits)
    ) instance_encode_high_one (
        .clk(clk),
        .signals_delay(signals_delay),
        .high_one(high_one)
    );
    module_encode_low_one #(
        .N(N_carry4),    // N_carry4
        .N_bins_bits(N_bins_bits)
    ) instance_encode_low_one (
        .clk(clk),
        .signals_delay(signals_delay),
        .low_one(low_one)
    );

    // add enable flag
    always @(posedge clk) begin
        tdc_raw_rise[N_bins_bits-1:0] <= high_one;
        tdc_raw_fall[N_bins_bits-1:0] <= low_one;
        
        // define the enable flag, rise and fall
        if ((tdc_raw_rise == 0) && (high_one != 0)) begin
            tdc_raw_rise[N_bins_bits] <= 1;
        end else begin
            tdc_raw_rise[N_bins_bits] <= 0;
        end
        if ((tdc_raw_fall == 0) && (low_one != 0)) begin
            tdc_raw_fall[N_bins_bits] <= 1;
        end else begin
            tdc_raw_fall[N_bins_bits] <= 0;
        end
    end

endmodule
// template
    // tdc_lite #(
    //     .N_carry4(50),      // 25 carry4 per nanosecond
    //     .N_bins_bits(8)     // = log2(4*N_carry4)
    // ) instance_tdc (
    //     .clk(clk),          // input clock
    //     .signal(signal),    // input signal
    //     .tdc_raw_rise(tdc_raw_rise),  // tdc output raw result. 1 + N, the first is enable signal
    //     .tdc_raw_fall(tdc_raw_fall)
    // );

// TDL module, time delay line
module module_tdl #(
    parameter N_carry4 = 50    // need 25 carry4 per nanosecond
    ) (
    input  wire clk,
    input  wire signal,
    output reg  [4*N_carry4-1:0] signals_delay
    );
    wire [4*N_carry4-1:0] carry_out_wire; // carry4 ports

    // initialize carry4
    CARRY4 instance_carry4_init (
        .CI(1'b0),          // initial carry-in
        .CYINIT(signal),    // input signal
        .DI(4'b0000),       // data input, both 0 and 1 are ok, don't care
        .S (4'b1111),       // select input, MUST be all 1
        .O (),              // sum out, no need
        .CO(carry_out_wire[3:0]) // carry out to next stage, delay
    );
    // generate carry4 chain
    genvar i;
    generate for (i=1; i<N_carry4; i=i+1) begin
        CARRY4 carry4_instance_gen (
            .CI(carry_out_wire[4*i-1]), // carry from previous stage
            .CYINIT(1'b0),
            .DI(4'b0000),
            .S (4'b1111),
            .O (),
            .CO(carry_out_wire[4*i+3:4*i])
        );
    end endgenerate;

    // output. if necessary, sample twice
    reg  [4*N_carry4-1:0] signals_delay_temp;
    always @(posedge clk) begin
        signals_delay_temp <= carry_out_wire;   // use the neighbor FF
        signals_delay <= signals_delay_temp;
    end
endmodule
// template
    // module_tdl #(
    //     .N_carry4(N_carry4)
    // ) instance_tdl (
    //     .clk(clk),
    //     .signal(signal),
    //     .signals_delay(signals_delay)
    // );

// Encode module, find the highest one for rise edge
module module_encode_high_one #(
    parameter N = 50,          // N_carry4, 25ns per nanosecond
    parameter N_bins_bits = 8   // = log2(4*N_carry4)
    ) (
    input  wire clk,
    input  wire [4*N-1:0] signals_delay,
    output reg  [N_bins_bits-1:0] high_one
    );
    reg  [N_bins_bits-1:0] temp1, temp2, temp3, temp4,  // without clk, combinatorial logic
                           tmp_1, tmp_2, tmp_3, tmp_4;  // with clk
    integer t1, t2, t3, t4;

    // first, no clk, and split to 4 pieces to faster
    always @(*) begin
        // search from high to low
        temp4 = 0;
        for (t4=3*N; t4<4*N; t4=t4+1) begin
            if (signals_delay[t4]) temp4 = t4;
        end
        temp3 = 0;
        for (t3=2*N; t3<3*N; t3=t3+1) begin
            if (signals_delay[t3]) temp3 = t3;
        end
        temp2 = 0;
        for (t2=1*N; t2<2*N; t2=t2+1) begin
            if (signals_delay[t2]) temp2 = t2;
        end
        temp1 = 0;
        for (t1=0*N; t1<1*N; t1=t1+1) begin
            if (signals_delay[t1]) temp1 = t1;
        end
    end
    // second, with clk, and sum up
    always @(posedge clk) begin
        // sample
        tmp_1 <= temp1;
        tmp_2 <= temp2;
        tmp_3 <= temp3;
        tmp_4 <= temp4;
        // output the highest one, and output zero in idle
        if (tmp_4 != 0)
            high_one <= tmp_4;
        else if (tmp_3 != 0)
            high_one <= tmp_3;
        else if (tmp_2 != 0)
            high_one <= tmp_2;
        else
            high_one <= tmp_1;
    end
endmodule
// template
    // module_encode_high_one #(
    //     .N(N_carry4),    // N_carry4
    //     .N_bins_bits(N_bins_bits)
    // ) instance_encode_high_one (
    //     .clk(clk),
    //     .signals_delay(signals_delay),
    //     .high_one(high_one)
    // );

// Encode module, find the lowest one for fall edge
module module_encode_low_one #(
    parameter N = 50,  // N_carry4
    parameter N_bins_bits = 8
    ) (
    input  wire clk,
    input  wire [4*N-1:0] signals_delay,
    output reg  [N_bins_bits-1:0] low_one
    );
    reg  [N_bins_bits-1:0] temp1, temp2, temp3, temp4,  // without clk, combinatorial logic
                           tmp_1, tmp_2, tmp_3, tmp_4;  // with clk
    integer t1, t2, t3, t4;

    // first, no clk, and split to 4 pieces to faster
    always @(*) begin
        // search from low to high
        temp1 = N;
        for (t1=N-1; t1>=0; t1=t1-1) begin
            if (signals_delay[t1]) temp1 = t1;
        end
        temp2 = 0;
        for (t2=2*N-1; t2>=N; t2=t2-1) begin
            if (signals_delay[t2]) temp2 = t2;
        end
        temp3 = 0;
        for (t3=3*N-1; t3>=2*N; t3=t3-1) begin
            if (signals_delay[t3]) temp3 = t3;
        end
        temp4 = 0;
        for (t4=4*N-1; t4>=3*N; t4=t4-1) begin
            if (signals_delay[t4]) temp4 = t4;
        end
    end
    // second, with clk, and sum up
    always @(posedge clk) begin
        // sample
        tmp_1 <= temp1;
        tmp_2 <= temp2;
        tmp_3 <= temp3;
        tmp_4 <= temp4;
        // output the lowest one, and output zero in idle or full of one
        if (tmp_1 != N)
            low_one <= tmp_1;
        else if (tmp_2 != 0)
            low_one <= tmp_2;
        else if (tmp_3 != 0)
            low_one <= tmp_3;
        else
            low_one <= tmp_4;
    end
endmodule
// template
    // module_encode_low_one #(
    //     .N(N_carry4),    // N_carry4
    //     .N_bins_bits(N_bins_bits)
    // ) instance_encode_low_one (
    //     .clk(clk),
    //     .signals_delay(signals_delay),
    //     .low_one(low_one)
    // );
