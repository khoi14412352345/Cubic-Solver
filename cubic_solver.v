`timescale 1ns/1ps

// ============================================================
// FP32 add/subtract
// Combinational, simplified IEEE-754 single precision datapath.
// ============================================================
module fp32_add (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        sub,
    output reg  [31:0] result
);
    reg        sa, sb, sr;
    reg [7:0]  ea, eb, er;
    reg [24:0] ma, mb, mr;
    reg [7:0]  diff;
    reg [4:0]  lz;
    reg [7:0]  max_shift;

    wire a_zero = (a[30:0] == 31'b0);
    wire b_zero = (b[30:0] == 31'b0);
    wire a_nan  = (a[30:23] == 8'hFF) && (a[22:0] != 23'b0);
    wire b_nan  = (b[30:23] == 8'hFF) && (b[22:0] != 23'b0);
    wire a_inf  = (a[30:23] == 8'hFF) && (a[22:0] == 23'b0);
    wire b_inf  = (b[30:23] == 8'hFF) && (b[22:0] == 23'b0);

    function [4:0] lzc24;
        input [23:0] value;
        begin
            if      (value[23]) lzc24 = 5'd0;
            else if (value[22]) lzc24 = 5'd1;
            else if (value[21]) lzc24 = 5'd2;
            else if (value[20]) lzc24 = 5'd3;
            else if (value[19]) lzc24 = 5'd4;
            else if (value[18]) lzc24 = 5'd5;
            else if (value[17]) lzc24 = 5'd6;
            else if (value[16]) lzc24 = 5'd7;
            else if (value[15]) lzc24 = 5'd8;
            else if (value[14]) lzc24 = 5'd9;
            else if (value[13]) lzc24 = 5'd10;
            else if (value[12]) lzc24 = 5'd11;
            else if (value[11]) lzc24 = 5'd12;
            else if (value[10]) lzc24 = 5'd13;
            else if (value[9])  lzc24 = 5'd14;
            else if (value[8])  lzc24 = 5'd15;
            else if (value[7])  lzc24 = 5'd16;
            else if (value[6])  lzc24 = 5'd17;
            else if (value[5])  lzc24 = 5'd18;
            else if (value[4])  lzc24 = 5'd19;
            else if (value[3])  lzc24 = 5'd20;
            else if (value[2])  lzc24 = 5'd21;
            else if (value[1])  lzc24 = 5'd22;
            else if (value[0])  lzc24 = 5'd23;
            else                lzc24 = 5'd24;
        end
    endfunction

    always @(*) begin
        sa = a[31];
        sb = b[31] ^ sub;
        ea = a[30:23];
        eb = b[30:23];
        ma = (ea != 8'b0) ? {2'b01, a[22:0]} : 25'b0;
        mb = (eb != 8'b0) ? {2'b01, b[22:0]} : 25'b0;
        sr = 1'b0;
        er = 8'b0;
        mr = 25'b0;
        diff = 8'b0;
        lz = 5'b0;
        max_shift = 8'b0;

        if (a_nan || b_nan) begin
            result = 32'h7FC00000;
        end else if (a_inf && b_inf) begin
            result = (sa == sb) ? {sa, 8'hFF, 23'b0} : 32'h7FC00000;
        end else if (a_inf) begin
            result = {sa, 8'hFF, 23'b0};
        end else if (b_inf) begin
            result = {sb, 8'hFF, 23'b0};
        end else if (a_zero && b_zero) begin
            result = 32'b0;
        end else if (a_zero) begin
            result = {sb, eb, b[22:0]};
        end else if (b_zero) begin
            result = a;
        end else begin
            if (ea < eb) begin
                sa = b[31] ^ sub;
                sb = a[31];
                ea = b[30:23];
                eb = a[30:23];
                ma = {2'b01, b[22:0]};
                mb = {2'b01, a[22:0]};
            end

            diff = ea - eb;
            mb = (diff > 8'd24) ? 25'b0 : (mb >> diff);
            er = ea;

            if (sa == sb) begin
                mr = ma + mb;
                sr = sa;
            end else if (ma >= mb) begin
                mr = ma - mb;
                sr = sa;
            end else begin
                mr = mb - ma;
                sr = sb;
            end

            if (mr == 25'b0) begin
                result = 32'b0;
            end else if (mr[24]) begin
                mr = mr >> 1;
                er = er + 8'd1;
                result = (er == 8'hFF) ? {sr, 8'hFF, 23'b0} : {sr, er, mr[22:0]};
            end else begin
                lz = lzc24(mr[23:0]);
                max_shift = er - 8'd1;
                if ({3'b000, lz} > max_shift) begin
                    lz = max_shift[4:0];
                end
                mr = mr << lz;
                er = er - {3'b000, lz};
                result = (er == 8'b0) ? 32'b0 : {sr, er, mr[22:0]};
            end
        end
    end
endmodule

// ============================================================
// FP32 multiply
// ============================================================
module fp32_mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);
    reg        sr;
    reg [8:0]  er;
    reg [47:0] product;

    wire a_zero = (a[30:0] == 31'b0);
    wire b_zero = (b[30:0] == 31'b0);
    wire a_nan  = (a[30:23] == 8'hFF) && (a[22:0] != 23'b0);
    wire b_nan  = (b[30:23] == 8'hFF) && (b[22:0] != 23'b0);
    wire a_inf  = (a[30:23] == 8'hFF) && (a[22:0] == 23'b0);
    wire b_inf  = (b[30:23] == 8'hFF) && (b[22:0] == 23'b0);

    always @(*) begin
        sr = a[31] ^ b[31];
        er = 9'b0;
        product = 48'b0;

        if (a_nan || b_nan || (a_inf && b_zero) || (b_inf && a_zero)) begin
            result = 32'h7FC00000;
        end else if (a_inf || b_inf) begin
            result = {sr, 8'hFF, 23'b0};
        end else if (a_zero || b_zero) begin
            result = {sr, 31'b0};
        end else begin
            er = {1'b0, a[30:23]} + {1'b0, b[30:23]} - 9'd127;
            product = {1'b1, a[22:0]} * {1'b1, b[22:0]};

            if (product[47]) begin
                product = product >> 1;
                er = er + 9'd1;
            end

            if (er[8] || er == 9'b0) begin
                result = {sr, 31'b0};
            end else if (er >= 9'd255) begin
                result = {sr, 8'hFF, 23'b0};
            end else begin
                result = {sr, er[7:0], product[45:23]};
            end
        end
    end
endmodule

// ============================================================
// FP32 divide
// Combinational version kept for the standalone FP32 operation TB.
// The top-level solver uses fp32_div_seq below.
// ============================================================
module fp32_div (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);
    reg         sr;
    reg signed [9:0] er;
    reg [23:0] ma, mb;
    reg [48:0] remainder;
    reg [48:0] divisor;
    reg [24:0] quotient;
    integer bit_i;

    wire a_zero = (a[30:0] == 31'b0);
    wire b_zero = (b[30:0] == 31'b0);
    wire a_nan  = (a[30:23] == 8'hFF) && (a[22:0] != 23'b0);
    wire b_nan  = (b[30:23] == 8'hFF) && (b[22:0] != 23'b0);
    wire a_inf  = (a[30:23] == 8'hFF) && (a[22:0] == 23'b0);
    wire b_inf  = (b[30:23] == 8'hFF) && (b[22:0] == 23'b0);

    always @(*) begin
        sr = a[31] ^ b[31];
        er = 10'sd0;
        ma = 24'b0;
        mb = 24'b0;
        remainder = 49'b0;
        divisor = 49'b0;
        quotient = 25'b0;

        if (a_nan || b_nan || (a_zero && b_zero) || (a_inf && b_inf)) begin
            result = 32'h7FC00000;
        end else if (b_zero || a_inf) begin
            result = {sr, 8'hFF, 23'b0};
        end else if (a_zero || b_inf) begin
            result = {sr, 31'b0};
        end else begin
            er = {2'b0, a[30:23]} - {2'b0, b[30:23]} + 10'sd127;
            ma = {1'b1, a[22:0]};
            mb = {1'b1, b[22:0]};
            remainder = {ma, 23'b0};
            divisor = {1'b0, mb, 24'b0};

            for (bit_i = 24; bit_i >= 0; bit_i = bit_i - 1) begin
                if (remainder >= divisor) begin
                    remainder = remainder - divisor;
                    quotient[bit_i] = 1'b1;
                end
                divisor = divisor >> 1;
            end

            if (quotient[24]) begin
                quotient = quotient >> 1;
                er = er + 10'sd1;
            end else if (!quotient[23]) begin
                quotient = quotient << 1;
                er = er - 10'sd1;
            end

            if (er <= 10'sd0) begin
                result = {sr, 31'b0};
            end else if (er >= 10'sd255) begin
                result = {sr, 8'hFF, 23'b0};
            end else begin
                result = {sr, er[7:0], quotient[22:0]};
            end
        end
    end
endmodule

// ============================================================
// Sequential FP32 divide
// One subtract/compare step per cycle. This keeps the solver small
// and avoids synthesizing a large combinational divider in the top.
// ============================================================
module fp32_div_seq (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result,
    output reg         done
);
    reg         busy;
    reg         sign_r;
    reg signed [9:0] exp_r;
    reg [4:0]   bit_idx;
    reg [48:0]  remainder_r;
    reg [48:0]  divisor_r;
    reg [24:0]  quotient_r;

    wire a_zero = (a[30:0] == 31'b0);
    wire b_zero = (b[30:0] == 31'b0);
    wire a_nan  = (a[30:23] == 8'hFF) && (a[22:0] != 23'b0);
    wire b_nan  = (b[30:23] == 8'hFF) && (b[22:0] != 23'b0);
    wire a_inf  = (a[30:23] == 8'hFF) && (a[22:0] == 23'b0);
    wire b_inf  = (b[30:23] == 8'hFF) && (b[22:0] == 23'b0);

    wire        step_ge = (remainder_r >= divisor_r);
    wire [48:0] step_remainder = step_ge ? (remainder_r - divisor_r) : remainder_r;
    wire [24:0] step_quotient  = step_ge ? (quotient_r | (25'd1 << bit_idx)) : quotient_r;

    wire signed [9:0] norm_exp_hi = exp_r + 10'sd1;
    wire signed [9:0] norm_exp_lo = exp_r - 10'sd1;
    wire signed [9:0] final_exp =
        step_quotient[24] ? norm_exp_hi :
        (!step_quotient[23] ? norm_exp_lo : exp_r);
    wire [24:0] final_quotient =
        step_quotient[24] ? (step_quotient >> 1) :
        (!step_quotient[23] ? (step_quotient << 1) : step_quotient);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'b0;
            sign_r <= 1'b0;
            exp_r <= 10'sd0;
            bit_idx <= 5'd0;
            remainder_r <= 49'b0;
            divisor_r <= 49'b0;
            quotient_r <= 25'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                sign_r <= a[31] ^ b[31];

                if (a_nan || b_nan || (a_zero && b_zero) || (a_inf && b_inf)) begin
                    result <= 32'h7FC00000;
                    done <= 1'b1;
                end else if (b_zero || a_inf) begin
                    result <= {a[31] ^ b[31], 8'hFF, 23'b0};
                    done <= 1'b1;
                end else if (a_zero || b_inf) begin
                    result <= {a[31] ^ b[31], 31'b0};
                    done <= 1'b1;
                end else begin
                    busy <= 1'b1;
                    exp_r <= {2'b0, a[30:23]} - {2'b0, b[30:23]} + 10'sd127;
                    remainder_r <= {{1'b1, a[22:0]}, 23'b0};
                    divisor_r <= {1'b0, {1'b1, b[22:0]}, 24'b0};
                    quotient_r <= 25'b0;
                    bit_idx <= 5'd24;
                end
            end else if (busy) begin
                if (bit_idx == 5'd0) begin
                    if (final_exp <= 10'sd0) begin
                        result <= {sign_r, 31'b0};
                    end else if (final_exp >= 10'sd255) begin
                        result <= {sign_r, 8'hFF, 23'b0};
                    end else begin
                        result <= {sign_r, final_exp[7:0], final_quotient[22:0]};
                    end
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    remainder_r <= step_remainder;
                    quotient_r <= step_quotient;
                    divisor_r <= divisor_r >> 1;
                    bit_idx <= bit_idx - 5'd1;
                end
            end
        end
    end
endmodule

// ============================================================
// FP32 square root
// Lightweight estimate based on exponent halving and mantissa slope.
// ============================================================
module fp32_sqrt (
    input  wire [31:0] a,
    output reg  [31:0] result
);
    reg [7:0]  exp_out;
    reg [22:0] mant_out;
    reg signed [9:0] exp_unbiased;
    reg signed [9:0] exp_half;
    reg              exp_odd;

    wire a_zero = (a[30:0] == 31'b0);
    wire a_nan  = (a[30:23] == 8'hFF) && (a[22:0] != 23'b0);
    wire a_inf  = (a[30:23] == 8'hFF) && (a[22:0] == 23'b0);

    always @(*) begin
        exp_out = 8'b0;
        mant_out = 23'b0;
        exp_unbiased = 10'sd0;
        exp_half = 10'sd0;
        exp_odd = 1'b0;

        if (a_nan || a[31]) begin
            result = 32'h7FC00000;
        end else if (a_zero) begin
            result = 32'b0;
        end else if (a_inf) begin
            result = {1'b0, 8'hFF, 23'b0};
        end else begin
            exp_unbiased = {2'b0, a[30:23]} - 10'sd127;
            exp_odd = exp_unbiased[0];
            exp_half = exp_odd ? ((exp_unbiased - 10'sd1) >>> 1) :
                                 (exp_unbiased >>> 1);
            exp_out = exp_half + 10'sd127;

            if (exp_odd) begin
                mant_out = 23'h3504F3 + (a[22:0] >> 1) - (a[22:0] >> 3);
            end else begin
                mant_out = a[22:0] >> 1;
            end

            result = {1'b0, exp_out, mant_out};
        end
    end
endmodule

// ============================================================
// Cubic solver
// Method:
//   1. Find one real root using Newton-Raphson.
//   2. Deflate the cubic into a quadratic.
//   3. Solve the quadratic and output only real roots.
// ============================================================
module cubic_solver (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [31:0] d,
    output reg  [31:0] x0,
    output reg  [31:0] x1,
    output reg  [31:0] x2,
    output reg         done,
    output reg         error
);
    localparam NAN   = 32'h7FC00000;
    localparam TWO   = 32'h40000000;
    localparam THREE = 32'h40400000;
    localparam FOUR  = 32'h40800000;

    localparam [5:0] ST_IDLE      = 6'd0,
                     ST_CHECK_A   = 6'd1,
                     ST_INIT_M3A  = 6'd2,
                     ST_INIT_M2B  = 6'd3,
                     ST_INIT_DIV  = 6'd4,
                     ST_INIT_WAIT = 6'd5,
                     ST_F_M0      = 6'd6,
                     ST_F_A0      = 6'd7,
                     ST_F_M1      = 6'd8,
                     ST_F_A1      = 6'd9,
                     ST_F_M2      = 6'd10,
                     ST_F_A2      = 6'd11,
                     ST_FP_M0     = 6'd12,
                     ST_FP_A0     = 6'd13,
                     ST_FP_M1     = 6'd14,
                     ST_FP_A1     = 6'd15,
                     ST_NR_DIV    = 6'd16,
                     ST_NR_WAIT   = 6'd17,
                     ST_NR_SUB    = 6'd18,
                     ST_DEF_M0    = 6'd19,
                     ST_DEF_A0    = 6'd20,
                     ST_DEF_M1    = 6'd21,
                     ST_DEF_A1    = 6'd22,
                     ST_DISC_M0   = 6'd23,
                     ST_DISC_M1   = 6'd24,
                     ST_DISC_M2   = 6'd25,
                     ST_DISC_SUB  = 6'd26,
                     ST_DISC_CHK  = 6'd27,
                     ST_SQRT      = 6'd28,
                     ST_DENOM     = 6'd29,
                     ST_X1_ADD    = 6'd30,
                     ST_X1_DIV    = 6'd31,
                     ST_X1_WAIT   = 6'd32,
                     ST_X2_ADD    = 6'd33,
                     ST_X2_DIV    = 6'd34,
                     ST_X2_WAIT   = 6'd35;

    reg [5:0]  state;
    reg [5:0]  iter;
    reg [31:0] ra, rb, rc, rd;
    reg [31:0] xn;
    reg [31:0] fx_r;
    reg [31:0] three_a_r;
    reg [31:0] two_b_r;
    reg [31:0] q1_r;
    reg [31:0] q0_r;
    reg [31:0] disc_r;
    reg [31:0] sqrt_r;
    reg [31:0] denom_r;
    reg [31:0] neg_q1_r;
    reg [31:0] work_r;

    reg [31:0] add_a;
    reg [31:0] add_b;
    reg        add_sub;
    wire [31:0] add_y;

    reg [31:0] mul_a;
    reg [31:0] mul_b;
    wire [31:0] mul_y;

    reg [31:0] sqrt_a;
    wire [31:0] sqrt_y;

    reg [31:0] div_a;
    reg [31:0] div_b;
    reg        div_start;
    wire [31:0] div_y;
    wire        div_done;

    fp32_add u_add (
        .a(add_a),
        .b(add_b),
        .sub(add_sub),
        .result(add_y)
    );

    fp32_mul u_mul (
        .a(mul_a),
        .b(mul_b),
        .result(mul_y)
    );

    fp32_sqrt u_sqrt (
        .a(sqrt_a),
        .result(sqrt_y)
    );

    fp32_div_seq u_div (
        .clk(clk),
        .rst(rst),
        .start(div_start),
        .a(div_a),
        .b(div_b),
        .result(div_y),
        .done(div_done)
    );

    always @(*) begin
        add_a = 32'b0;
        add_b = 32'b0;
        add_sub = 1'b0;
        mul_a = 32'b0;
        mul_b = 32'b0;
        sqrt_a = 32'b0;

        case (state)
            ST_INIT_M3A: begin mul_a = THREE;     mul_b = ra; end
            ST_INIT_M2B: begin mul_a = TWO;       mul_b = rb; end

            ST_F_M0:     begin mul_a = ra;        mul_b = xn; end
            ST_F_A0:     begin add_a = work_r;    add_b = rb; add_sub = 1'b0; end
            ST_F_M1:     begin mul_a = work_r;    mul_b = xn; end
            ST_F_A1:     begin add_a = work_r;    add_b = rc; add_sub = 1'b0; end
            ST_F_M2:     begin mul_a = work_r;    mul_b = xn; end
            ST_F_A2:     begin add_a = work_r;    add_b = rd; add_sub = 1'b0; end

            ST_FP_M0:    begin mul_a = three_a_r; mul_b = xn; end
            ST_FP_A0:    begin add_a = work_r;    add_b = two_b_r; add_sub = 1'b0; end
            ST_FP_M1:    begin mul_a = work_r;    mul_b = xn; end
            ST_FP_A1:    begin add_a = work_r;    add_b = rc; add_sub = 1'b0; end

            ST_NR_SUB:   begin add_a = xn;        add_b = work_r; add_sub = 1'b1; end

            ST_DEF_M0:   begin mul_a = ra;        mul_b = x0; end
            ST_DEF_A0:   begin add_a = work_r;    add_b = rb; add_sub = 1'b0; end
            ST_DEF_M1:   begin mul_a = q1_r;      mul_b = x0; end
            ST_DEF_A1:   begin add_a = work_r;    add_b = rc; add_sub = 1'b0; end

            ST_DISC_M0:  begin mul_a = q1_r;      mul_b = q1_r; end
            ST_DISC_M1:  begin mul_a = ra;        mul_b = q0_r; end
            ST_DISC_M2:  begin mul_a = FOUR;      mul_b = work_r; end
            ST_DISC_SUB: begin add_a = disc_r;    add_b = work_r; add_sub = 1'b1; end

            ST_SQRT:     begin sqrt_a = disc_r; end
            ST_DENOM:    begin mul_a = TWO;       mul_b = ra; end

            ST_X1_ADD:   begin add_a = neg_q1_r;  add_b = sqrt_r; add_sub = 1'b0; end
            ST_X2_ADD:   begin add_a = neg_q1_r;  add_b = sqrt_r; add_sub = 1'b1; end
            default: ;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            iter <= 6'd0;
            ra <= 32'b0;
            rb <= 32'b0;
            rc <= 32'b0;
            rd <= 32'b0;
            xn <= 32'b0;
            fx_r <= 32'b0;
            three_a_r <= 32'b0;
            two_b_r <= 32'b0;
            q1_r <= 32'b0;
            q0_r <= 32'b0;
            disc_r <= 32'b0;
            sqrt_r <= 32'b0;
            denom_r <= 32'b0;
            neg_q1_r <= 32'b0;
            work_r <= 32'b0;
            div_a <= 32'b0;
            div_b <= 32'b0;
            div_start <= 1'b0;
            x0 <= NAN;
            x1 <= NAN;
            x2 <= NAN;
            done <= 1'b0;
            error <= 1'b0;
        end else begin
            div_start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    if (start) begin
                        ra <= a;
                        rb <= b;
                        rc <= c;
                        rd <= d;
                        x0 <= NAN;
                        x1 <= NAN;
                        x2 <= NAN;
                        state <= ST_CHECK_A;
                    end
                end

                ST_CHECK_A: begin
                    if (ra[30:0] == 31'b0) begin
                        x0 <= NAN;
                        x1 <= NAN;
                        x2 <= NAN;
                        done <= 1'b1;
                        error <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_INIT_M3A;
                    end
                end

                ST_INIT_M3A: begin
                    work_r <= mul_y;
                    state <= ST_INIT_M2B;
                end

                ST_INIT_M2B: begin
                    three_a_r <= work_r;
                    work_r <= mul_y;
                    state <= ST_INIT_DIV;
                end

                ST_INIT_DIV: begin
                    two_b_r <= work_r;
                    div_a <= {~rb[31], rb[30:0]};
                    div_b <= three_a_r;
                    div_start <= 1'b1;
                    state <= ST_INIT_WAIT;
                end

                ST_INIT_WAIT: begin
                    if (div_done) begin
                        xn <= div_y;
                        iter <= 6'd0;
                        state <= ST_F_M0;
                    end
                end

                ST_F_M0: begin work_r <= mul_y; state <= ST_F_A0; end
                ST_F_A0: begin work_r <= add_y; state <= ST_F_M1; end
                ST_F_M1: begin work_r <= mul_y; state <= ST_F_A1; end
                ST_F_A1: begin work_r <= add_y; state <= ST_F_M2; end
                ST_F_M2: begin work_r <= mul_y; state <= ST_F_A2; end

                ST_F_A2: begin
                    fx_r <= add_y;
                    state <= ST_FP_M0;
                end

                ST_FP_M0: begin work_r <= mul_y; state <= ST_FP_A0; end
                ST_FP_A0: begin work_r <= add_y; state <= ST_FP_M1; end
                ST_FP_M1: begin work_r <= mul_y; state <= ST_FP_A1; end

                ST_FP_A1: begin
                    work_r <= add_y;
                    state <= ST_NR_DIV;
                end

                ST_NR_DIV: begin
                    if ((fx_r[30:0] == 31'b0) || (work_r[30:0] == 31'b0)) begin
                        x0 <= xn;
                        state <= ST_DEF_M0;
                    end else begin
                        div_a <= fx_r;
                        div_b <= work_r;
                        div_start <= 1'b1;
                        state <= ST_NR_WAIT;
                    end
                end

                ST_NR_WAIT: begin
                    if (div_done) begin
                        work_r <= div_y;
                        state <= ST_NR_SUB;
                    end
                end

                ST_NR_SUB: begin
                    xn <= add_y;
                    iter <= iter + 6'd1;
                    if (iter >= 6'd5) begin
                        x0 <= add_y;
                        state <= ST_DEF_M0;
                    end else begin
                        state <= ST_F_M0;
                    end
                end

                ST_DEF_M0: begin work_r <= mul_y; state <= ST_DEF_A0; end

                ST_DEF_A0: begin
                    q1_r <= add_y;
                    work_r <= add_y;
                    state <= ST_DEF_M1;
                end

                ST_DEF_M1: begin work_r <= mul_y; state <= ST_DEF_A1; end

                ST_DEF_A1: begin
                    q0_r <= add_y;
                    state <= ST_DISC_M0;
                end

                ST_DISC_M0: begin
                    disc_r <= mul_y;
                    state <= ST_DISC_M1;
                end

                ST_DISC_M1: begin
                    work_r <= mul_y;
                    state <= ST_DISC_M2;
                end

                ST_DISC_M2: begin
                    work_r <= mul_y;
                    state <= ST_DISC_SUB;
                end

                ST_DISC_SUB: begin
                    disc_r <= add_y;
                    state <= ST_DISC_CHK;
                end

                ST_DISC_CHK: begin
                    neg_q1_r <= {~q1_r[31], q1_r[30:0]};
                    if (disc_r[31] && (disc_r[30:0] != 31'b0)) begin
                        x1 <= NAN;
                        x2 <= NAN;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (disc_r[30:0] == 31'b0) begin
                        state <= ST_DENOM;
                    end else begin
                        state <= ST_SQRT;
                    end
                end

                ST_SQRT: begin
                    sqrt_r <= sqrt_y;
                    state <= ST_DENOM;
                end

                ST_DENOM: begin
                    denom_r <= mul_y;
                    if (disc_r[30:0] == 31'b0) begin
                        work_r <= neg_q1_r;
                        state <= ST_X1_DIV;
                    end else begin
                        state <= ST_X1_ADD;
                    end
                end

                ST_X1_ADD: begin
                    work_r <= add_y;
                    state <= ST_X1_DIV;
                end

                ST_X1_DIV: begin
                    div_a <= work_r;
                    div_b <= denom_r;
                    div_start <= 1'b1;
                    state <= ST_X1_WAIT;
                end

                ST_X1_WAIT: begin
                    if (div_done) begin
                        x1 <= div_y;
                        if (disc_r[30:0] == 31'b0) begin
                            x2 <= div_y;
                            done <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_X2_ADD;
                        end
                    end
                end

                ST_X2_ADD: begin
                    work_r <= add_y;
                    state <= ST_X2_DIV;
                end

                ST_X2_DIV: begin
                    div_a <= work_r;
                    div_b <= denom_r;
                    div_start <= 1'b1;
                    state <= ST_X2_WAIT;
                end

                ST_X2_WAIT: begin
                    if (div_done) begin
                        x2 <= div_y;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
