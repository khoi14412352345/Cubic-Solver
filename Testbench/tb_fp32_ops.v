`timescale 1ns/1ps

module tb_fp32_ops;
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

    reg [31:0] add_a, add_b;
    reg add_sub;
    wire [31:0] add_result;

    reg [31:0] mul_a, mul_b;
    wire [31:0] mul_result;

    reg [31:0] div_a, div_b;
    wire [31:0] div_result;

    reg [31:0] sqrt_a;
    wire [31:0] sqrt_result;

    fp32_add u_add (.a(add_a), .b(add_b), .sub(add_sub), .result(add_result));
    fp32_mul u_mul (.a(mul_a), .b(mul_b), .result(mul_result));
    fp32_div u_div (.a(div_a), .b(div_b), .result(div_result));
    fp32_sqrt u_sqrt (.a(sqrt_a), .result(sqrt_result));

    task run_add_case;
        input [1023:0] name;
        input [31:0] lhs;
        input [31:0] rhs;
        input sub;
        input [31:0] expected;
        begin
            add_a = lhs;
            add_b = rhs;
            add_sub = sub;
            #1;
            expect_hex(name, add_result, expected);
        end
    endtask

    task run_mul_case;
        input [1023:0] name;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        begin
            mul_a = lhs;
            mul_b = rhs;
            #1;
            expect_hex(name, mul_result, expected);
        end
    endtask

    task run_div_case;
        input [1023:0] name;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        begin
            div_a = lhs;
            div_b = rhs;
            #1;
            expect_hex(name, div_result, expected);
        end
    endtask

    task run_sqrt_case;
        input [1023:0] name;
        input [31:0] value;
        input [31:0] expected;
        begin
            sqrt_a = value;
            #1;
            expect_hex(name, sqrt_result, expected);
        end
    endtask

    initial begin
        $dumpfile("tests/tb_fp32_ops.vcd");
        $dumpvars(0, tb_fp32_ops);

        run_add_case("fp32_add_sub_test: 1.0 + 2.0 = 3.0", 32'h3F800000, 32'h40000000, 1'b0, 32'h40400000);
        run_add_case("fp32_add_sub_test: 3.0 - 1.0 = 2.0", 32'h40400000, 32'h3F800000, 1'b1, 32'h40000000);
        run_mul_case("fp32_mul_test: 2.0 * 3.0 = 6.0", 32'h40000000, 32'h40400000, 32'h40C00000);
        run_div_case("fp32_div_test: 6.0 / 2.0 = 3.0", 32'h40C00000, 32'h40000000, 32'h40400000);
        run_sqrt_case("fp32_sqrt_test: sqrt(4.0) = 2.0", 32'h40800000, 32'h40000000);

        print_summary("tb_fp32_ops");
        $finish;
    end
endmodule
