`timescale 1ns/1ps

// Unit test for hit_kernel_uq16_comb: x^2 + y^2 <= 1.0 in UQ0.16.
// Corners, axes, and the exact circle boundary: for a sweep of x values,
// y_max = floor(sqrt(2^32 - x^2)) must be inside and y_max + 1 outside.

module tb_hit_kernel;
    reg  [15:0] x, y;
    wire        in_circle;
    integer errors = 0, checks = 0, i;
    reg  [63:0] r, ymax;

    hit_kernel_uq16_comb dut (.x_in(x), .y_in(y), .inside(in_circle));

    task check(input [15:0] tx, input [15:0] ty, input expected);
        begin
            x = tx; y = ty; #1;
            checks = checks + 1;
            if (in_circle !== expected) begin
                errors = errors + 1;
                $display("FAIL: x=%0d y=%0d inside=%b expected %b", tx, ty, in_circle, expected);
            end
        end
    endtask

    // integer square root of a 64-bit value
    function [63:0] isqrt(input [63:0] v);
        reg [63:0] lo, hi, mid;
        begin
            lo = 0; hi = 64'h1_0000_0000;
            while (lo < hi) begin
                mid = (lo + hi + 1) >> 1;
                if (mid * mid <= v) lo = mid; else hi = mid - 1;
            end
            isqrt = lo;
        end
    endfunction

    initial begin
        check(16'd0,     16'd0,     1'b1);   // origin
        check(16'd65535, 16'd0,     1'b1);   // largest x on the axis (just under 1.0)
        check(16'd0,     16'd65535, 1'b1);
        check(16'd65535, 16'd65535, 1'b0);   // far corner
        check(16'd46341, 16'd46341, 1'b0);   // just past 1/sqrt(2) on the diagonal
        check(16'd46340, 16'd46340, 1'b1);

        // exact boundary sweep
        for (i = 0; i < 65536; i = i + 97) begin
            r = 64'h1_0000_0000 - i * i;
            ymax = isqrt(r);
            if (ymax <= 65535) check(i[15:0], ymax[15:0], 1'b1);
            if (ymax + 1 <= 65535) check(i[15:0], ymax[15:0] + 16'd1, 1'b0);
        end

        if (errors == 0) $display("PASS: hit kernel, %0d checks including the exact circle boundary", checks);
        else             $fatal(1, "hit kernel: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
