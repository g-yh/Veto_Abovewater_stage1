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

    // The 400 MHz time-sync TDC uses an extra encoder pipeline stage to close
    // timing. The phase-measure counter compensates this fixed one-cycle delay.
    generate
        if (N == 64) begin : gen_balanced_high
            wire [7:0] high_idx1, high_idx2, high_idx3, high_idx4;
            module_encode_high64_pipe #(.BASE(8'd0)) enc1 (
                .clk(clk), .data(signals_delay[0*N +: N]), .idx(high_idx1));
            module_encode_high64_pipe #(.BASE(8'd64)) enc2 (
                .clk(clk), .data(signals_delay[1*N +: N]), .idx(high_idx2));
            module_encode_high64_pipe #(.BASE(8'd128)) enc3 (
                .clk(clk), .data(signals_delay[2*N +: N]), .idx(high_idx3));
            module_encode_high64_pipe #(.BASE(8'd192)) enc4 (
                .clk(clk), .data(signals_delay[3*N +: N]), .idx(high_idx4));

            always @(posedge clk) begin
                if (high_idx4 != 0)
                    high_one <= high_idx4;
                else if (high_idx3 != 0)
                    high_one <= high_idx3;
                else if (high_idx2 != 0)
                    high_one <= high_idx2;
                else
                    high_one <= high_idx1;
            end
        end else begin : gen_generic_high
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

            always @(posedge clk) begin
                tmp_1 <= temp1;
                tmp_2 <= temp2;
                tmp_3 <= temp3;
                tmp_4 <= temp4;
                if (tmp_4 != 0)
                    high_one <= tmp_4;
                else if (tmp_3 != 0)
                    high_one <= tmp_3;
                else if (tmp_2 != 0)
                    high_one <= tmp_2;
                else
                    high_one <= tmp_1;
            end
        end
    endgenerate
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

    // The 400 MHz time-sync TDC uses an extra encoder pipeline stage to close
    // timing. The phase-measure counter compensates this fixed one-cycle delay.
    generate
        if (N == 64) begin : gen_balanced_low
            wire [7:0] low_idx1, low_idx2, low_idx3, low_idx4;
            module_encode_low64_pipe #(.BASE(8'd0), .EMPTY_VALUE(8'd64)) enc1 (
                .clk(clk), .data(signals_delay[0*N +: N]), .idx(low_idx1));
            module_encode_low64_pipe #(.BASE(8'd64)) enc2 (
                .clk(clk), .data(signals_delay[1*N +: N]), .idx(low_idx2));
            module_encode_low64_pipe #(.BASE(8'd128)) enc3 (
                .clk(clk), .data(signals_delay[2*N +: N]), .idx(low_idx3));
            module_encode_low64_pipe #(.BASE(8'd192)) enc4 (
                .clk(clk), .data(signals_delay[3*N +: N]), .idx(low_idx4));

            always @(posedge clk) begin
                if (low_idx1 != N)
                    low_one <= low_idx1;
                else if (low_idx2 != 0)
                    low_one <= low_idx2;
                else if (low_idx3 != 0)
                    low_one <= low_idx3;
                else
                    low_one <= low_idx4;
            end
        end else begin : gen_generic_low
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

            always @(posedge clk) begin
                tmp_1 <= temp1;
                tmp_2 <= temp2;
                tmp_3 <= temp3;
                tmp_4 <= temp4;
                if (tmp_1 != N)
                    low_one <= tmp_1;
                else if (tmp_2 != 0)
                    low_one <= tmp_2;
                else if (tmp_3 != 0)
                    low_one <= tmp_3;
                else
                    low_one <= tmp_4;
            end
        end
    endgenerate
endmodule

module module_encode_high64 (
    input  wire [63:0] data,
    output reg  [5:0]  idx
);
    reg [31:0] sel32;
    reg [15:0] sel16;
    reg [7:0]  sel8;
    reg [3:0]  sel4;
    reg [1:0]  sel2;

    always @(*) begin
        idx[5] = |data[63:32];
        sel32  = idx[5] ? data[63:32] : data[31:0];
        idx[4] = |sel32[31:16];
        sel16  = idx[4] ? sel32[31:16] : sel32[15:0];
        idx[3] = |sel16[15:8];
        sel8   = idx[3] ? sel16[15:8] : sel16[7:0];
        idx[2] = |sel8[7:4];
        sel4   = idx[2] ? sel8[7:4] : sel8[3:0];
        idx[1] = |sel4[3:2];
        sel2   = idx[1] ? sel4[3:2] : sel4[1:0];
        idx[0] = sel2[1];
    end
endmodule

module module_encode_low64 (
    input  wire [63:0] data,
    output reg  [5:0]  idx
);
    reg [31:0] sel32;
    reg [15:0] sel16;
    reg [7:0]  sel8;
    reg [3:0]  sel4;
    reg [1:0]  sel2;

    always @(*) begin
        if (!(|data)) begin
            idx = 6'd0;
        end else begin
            idx[5] = !(|data[31:0]);
            sel32  = idx[5] ? data[63:32] : data[31:0];
            idx[4] = !(|sel32[15:0]);
            sel16  = idx[4] ? sel32[31:16] : sel32[15:0];
            idx[3] = !(|sel16[7:0]);
            sel8   = idx[3] ? sel16[15:8] : sel16[7:0];
            idx[2] = !(|sel8[3:0]);
            sel4   = idx[2] ? sel8[7:4] : sel8[3:0];
            idx[1] = !(|sel4[1:0]);
            sel2   = idx[1] ? sel4[3:2] : sel4[1:0];
            idx[0] = !sel2[0];
        end
    end
endmodule

module module_encode_high32 (
    input  wire [31:0] data,
    output reg  [4:0]  idx
);
    reg [15:0] sel16;
    reg [7:0]  sel8;
    reg [3:0]  sel4;
    reg [1:0]  sel2;

    always @(*) begin
        idx[4] = |data[31:16];
        sel16  = idx[4] ? data[31:16] : data[15:0];
        idx[3] = |sel16[15:8];
        sel8   = idx[3] ? sel16[15:8] : sel16[7:0];
        idx[2] = |sel8[7:4];
        sel4   = idx[2] ? sel8[7:4] : sel8[3:0];
        idx[1] = |sel4[3:2];
        sel2   = idx[1] ? sel4[3:2] : sel4[1:0];
        idx[0] = sel2[1];
    end
endmodule

module module_encode_low32 (
    input  wire [31:0] data,
    output reg  [4:0]  idx
);
    reg [15:0] sel16;
    reg [7:0]  sel8;
    reg [3:0]  sel4;
    reg [1:0]  sel2;

    always @(*) begin
        if (!(|data)) begin
            idx = 5'd0;
        end else begin
            idx[4] = !(|data[15:0]);
            sel16  = idx[4] ? data[31:16] : data[15:0];
            idx[3] = !(|sel16[7:0]);
            sel8   = idx[3] ? sel16[15:8] : sel16[7:0];
            idx[2] = !(|sel8[3:0]);
            sel4   = idx[2] ? sel8[7:4] : sel8[3:0];
            idx[1] = !(|sel4[1:0]);
            sel2   = idx[1] ? sel4[3:2] : sel4[1:0];
            idx[0] = !sel2[0];
        end
    end
endmodule

module module_encode_high64_pipe #(
    parameter [7:0] BASE = 8'd0
    ) (
    input  wire       clk,
    input  wire [63:0] data,
    output reg  [7:0]  idx
);
    wire [4:0] high_lo;
    wire [4:0] high_hi;
    module_encode_high32 enc_lo (.data(data[31:0]), .idx(high_lo));
    module_encode_high32 enc_hi (.data(data[63:32]), .idx(high_hi));

    reg       high_any_valid;
    reg       high_hi_valid;
    reg [4:0] high_lo_r;
    reg [4:0] high_hi_r;

    always @(posedge clk) begin
        high_any_valid <= |data;
        high_hi_valid <= |data[63:32];
        high_lo_r     <= high_lo;
        high_hi_r     <= high_hi;
        if (!high_any_valid)
            idx <= 8'd0;
        else if (high_hi_valid)
            idx <= BASE + 8'd32 + high_hi_r;
        else
            idx <= BASE + high_lo_r;
    end
endmodule

module module_encode_low64_pipe #(
    parameter [7:0] BASE = 8'd0,
    parameter [7:0] EMPTY_VALUE = 8'd0
    ) (
    input  wire       clk,
    input  wire [63:0] data,
    output reg  [7:0]  idx
);
    wire [4:0] low_lo;
    wire [4:0] low_hi;
    module_encode_low32 enc_lo (.data(data[31:0]), .idx(low_lo));
    module_encode_low32 enc_hi (.data(data[63:32]), .idx(low_hi));

    reg       low_any_valid;
    reg       low_lo_valid;
    reg       low_hi_valid;
    reg [4:0] low_lo_r;
    reg [4:0] low_hi_r;

    always @(posedge clk) begin
        low_any_valid <= |data;
        low_lo_valid <= |data[31:0];
        low_hi_valid <= |data[63:32];
        low_lo_r     <= low_lo;
        low_hi_r     <= low_hi;
        if (!low_any_valid)
            idx <= EMPTY_VALUE;
        else if (low_lo_valid)
            idx <= BASE + low_lo_r;
        else if (low_hi_valid)
            idx <= BASE + 8'd32 + low_hi_r;
        else
            idx <= EMPTY_VALUE;
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
