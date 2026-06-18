`timescale 1ns/1ps

module tb_cubic_discriminant_deflation;
    reg clk = 1'b0;
    reg rst = 1'b0;
    reg start = 1'b0;
    reg [31:0] a, b, c, d;
    wire [31:0] x0, x1, x2;
    wire done, error;

localparam [31:0] FP_NAN = 32'h7FC00000;
localparam real ROOT_TOL = 0.05;

integer pass_count = 0;
integer fail_count = 0;

function is_nan;
    input [31:0] bits;
    begin
        is_nan = (bits[30:23] == 8'hFF) && (bits[22:0] != 0);
    end
endfunction

function real fp32_to_real;
    input [31:0] bits;
    integer exp;
    integer i;
    real mant;
    real val;
    begin
        if (is_nan(bits)) begin
            fp32_to_real = 0.0;
        end else if (bits[30:0] == 0) begin
            fp32_to_real = 0.0;
        end else begin
            mant = (bits[30:23] == 0) ? 0.0 : 1.0;
            for (i = 0; i < 23; i = i + 1) begin
                if (bits[22-i]) begin
                    mant = mant + (1.0 / (2.0 ** (i + 1)));
                end
            end
            exp = bits[30:23] - 127;
            val = mant * (2.0 ** exp);
            fp32_to_real = bits[31] ? -val : val;
        end
    end
endfunction

task record_result;
    input condition;
    input [1023:0] name;
    begin
        if (condition) begin
            pass_count = pass_count + 1;
            $display("PASS: %0s", name);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s", name);
        end
    end
endtask

task expect_hex;
    input [1023:0] name;
    input [31:0] actual;
    input [31:0] expected;
    begin
        record_result(actual === expected, name);
        if (actual !== expected) begin
            $display("      expected=%h actual=%h", expected, actual);
        end
    end
endtask

function close_real;
    input real actual;
    input real expected;
    real diff;
    begin
        diff = actual - expected;
        if (diff < 0.0) diff = -diff;
        close_real = (diff <= ROOT_TOL);
    end
endfunction

task print_summary;
    input [1023:0] tb_name;
    begin
        $display("%0s SUMMARY: %0d passed, %0d failed", tb_name, pass_count, fail_count);
        if (fail_count != 0) begin
            $display("TESTBENCH FAILED");
            $finish;
        end
    end
endtask

    cubic_solver dut (
        .clk(clk), .rst(rst), .start(start),
        .a(a), .b(b), .c(c), .d(d),
        .x0(x0), .x1(x1), .x2(x2),
        .done(done), .error(error)
    );

integer last_cycles = 0;

task reset_dut;
    begin
        rst = 1'b1;
        start = 1'b0;
        a = 32'h00000000;
        b = 32'h00000000;
        c = 32'h00000000;
        d = 32'h00000000;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
    end
endtask

task run_solver_raw;
    input [31:0] ca;
    input [31:0] cb;
    input [31:0] cc;
    input [31:0] cd;
    integer cycles;
    begin
        reset_dut();
        @(negedge clk);
        a = ca;
        b = cb;
        c = cc;
        d = cd;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        cycles = 0;
        while (!done && cycles < 600) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        last_cycles = cycles;
        if (!done) begin
            fail_count = fail_count + 1;
            $display("FAIL: solver timeout");
        end
    end
endtask

function root_close;
    input [31:0] root_bits;
    input real expected;
    begin
        root_close = !is_nan(root_bits) && close_real(fp32_to_real(root_bits), expected);
    end
endfunction

function any_root_close;
    input real expected;
    begin
        any_root_close = root_close(x0, expected) || root_close(x1, expected) || root_close(x2, expected);
    end
endfunction

function integer count_matches;
    input real e0;
    input real e1;
    input real e2;
    integer matched_roots;
    begin
        matched_roots = 0;
        if (any_root_close(e0)) matched_roots = matched_roots + 1;
        if (any_root_close(e1)) matched_roots = matched_roots + 1;
        if (any_root_close(e2)) matched_roots = matched_roots + 1;
        count_matches = matched_roots;
    end
endfunction

task expect_roots_any_order;
    input [1023:0] name;
    input [31:0] ca;
    input [31:0] cb;
    input [31:0] cc;
    input [31:0] cd;
    input real e0;
    input real e1;
    input real e2;
    integer matched_roots;
    begin
        run_solver_raw(ca, cb, cc, cd);
        matched_roots = count_matches(e0, e1, e2);
        record_result(done && !error && (matched_roots == 3), name);
        if (!(done && !error && (matched_roots == 3))) begin
            $display("      expected roots near %f, %f, %f", e0, e1, e2);
            $display("      got x0=%h (%f), x1=%h (%f), x2=%h (%f), error=%b",
                     x0, fp32_to_real(x0), x1, fp32_to_real(x1), x2, fp32_to_real(x2), error);
        end
    end
endtask

task expect_all_outputs_close;
    input [1023:0] name;
    input [31:0] ca;
    input [31:0] cb;
    input [31:0] cc;
    input [31:0] cd;
    input real expected;
    begin
        run_solver_raw(ca, cb, cc, cd);
        record_result(done && !error &&
                      root_close(x0, expected) && root_close(x1, expected) && root_close(x2, expected),
                      name);
        if (!(done && !error &&
              root_close(x0, expected) && root_close(x1, expected) && root_close(x2, expected))) begin
            $display("      expected all outputs near %f", expected);
            $display("      got x0=%h (%f), x1=%h (%f), x2=%h (%f), error=%b",
                     x0, fp32_to_real(x0), x1, fp32_to_real(x1), x2, fp32_to_real(x2), error);
        end
    end
endtask

task expect_one_real_two_nan;
    input [1023:0] name;
    input [31:0] ca;
    input [31:0] cb;
    input [31:0] cc;
    input [31:0] cd;
    input real expected_real;
    integer nan_count;
    begin
        run_solver_raw(ca, cb, cc, cd);
        nan_count = (is_nan(x0) ? 1 : 0) + (is_nan(x1) ? 1 : 0) + (is_nan(x2) ? 1 : 0);
        record_result(done && !error && (nan_count == 2) && any_root_close(expected_real), name);
        if (!(done && !error && (nan_count == 2) && any_root_close(expected_real))) begin
            $display("      expected one real near %f and two NaNs", expected_real);
            $display("      got x0=%h (%f), x1=%h (%f), x2=%h (%f), error=%b",
                     x0, fp32_to_real(x0), x1, fp32_to_real(x1), x2, fp32_to_real(x2), error);
        end
    end
endtask

task expect_error_case;
    input [1023:0] name;
    input [31:0] ca;
    input [31:0] cb;
    input [31:0] cc;
    input [31:0] cd;
    begin
        run_solver_raw(ca, cb, cc, cd);
        record_result(done && error && is_nan(x0) && is_nan(x1) && is_nan(x2), name);
        if (!(done && error && is_nan(x0) && is_nan(x1) && is_nan(x2))) begin
            $display("      error=%b x0=%h x1=%h x2=%h", error, x0, x1, x2);
        end
    end
endtask

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tests/tb_cubic_discriminant_deflation.vcd");
        $dumpvars(0, tb_cubic_discriminant_deflation);

        run_solver_raw(32'h3F800000, 32'hC0C00000, 32'h41300000, 32'hC0C00000);
        record_result(done && !error && !dut.disc_r[31] && (dut.disc_r[30:0] != 0),
                      "disc_positive: deflated quadratic discriminant is positive");
        record_result(root_close(x1, 3.0) && root_close(x2, 1.0),
                      "quadratic_solve: x1/x2 solve remaining quadratic roots 3 and 1");
        record_result(root_close(dut.q1_r, -4.0) && root_close(dut.q0_r, 3.0),
                      "synthetic_div: after x0=2, q1=-4 and q0=3");

        run_solver_raw(32'h3F800000, 32'hC0C00000, 32'h41400000, 32'hC1000000);
        record_result(done && !error && (dut.disc_r[30:0] == 0),
                      "disc_zero: deflated quadratic discriminant is zero");
        record_result(root_close(x1, 2.0) && root_close(x2, 2.0),
                      "quadratic_solve: zero discriminant produces duplicated root 2");

        print_summary("tb_cubic_discriminant_deflation");
        $finish;
    end
endmodule
