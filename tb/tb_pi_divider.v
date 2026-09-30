`timescale 1ns/1ps

// Unit test for pi_divider: pi_q = 4 * hits / total in Q3.29.
// Exact results, divide-by-zero guard, one-cycle valid pulse, busy flag,
// and that inputs changing after start don't corrupt the result.

module tb_pi_divider;
    reg clk = 1'b0, resetn = 1'b0, start = 1'b0;
    reg  [31:0] hits, total;
    wire busy, valid;
    wire [60:0] pi_q;
    integer errors = 0, checks = 0, cycles;
    always #10 clk = ~clk;

    pi_divider #(.W(32), .FBITS(29)) dut (
        .clk(clk), .resetn(resetn), .start(start),
        .hits(hits), .total(total), .busy(busy), .valid(valid), .pi_q(pi_q)
    );

    task run(input [31:0] h, input [31:0] t, input [60:0] expected, input [255:0] label);
        begin
            @(negedge clk); hits = h; total = t; start = 1'b1;
            @(negedge clk); start = 1'b0;
            hits = 32'hDEAD_BEEF; total = 32'd7;   // scramble inputs after the start pulse
            cycles = 1;
            while (valid !== 1'b1 && cycles < 20) begin @(negedge clk); cycles = cycles + 1; end
            checks = checks + 1;
            if (valid !== 1'b1 || pi_q !== expected) begin
                errors = errors + 1;
                $display("FAIL: %0s hits=%0d total=%0d pi_q=%0d expected %0d", label, h, t, pi_q, expected);
            end
            @(negedge clk);
            checks = checks + 1;
            if (valid !== 1'b0 || busy !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL: %0s valid/busy did not clear", label);
            end
        end
    endtask

    initial begin
        hits = 0; total = 0;
        repeat (2) @(negedge clk);
        resetn = 1'b1;

        run(32'd1,       32'd1,       61'd4 << 29,        "all hits = 4.0");
        run(32'd0,       32'd100,     61'd0,              "no hits = 0");
        run(32'd0,       32'd0,       61'd0,              "total=0 guarded");
        run(32'd5,       32'd0,       (61'd5 << 31),      "total=0 divides by 1");
        run(32'd1,       32'd2,       61'd2 << 29,        "half = 2.0");
        run(32'd785398,  32'd1000000, (61'd785398 << 31) / 61'd1000000,   "pi-ish");
        run(32'd7852678, 32'd10000000,(61'd7852678 << 31) / 61'd10000000, "10M-sample result");

        if (errors == 0) $display("PASS: pi divider, %0d checks", checks);
        else             $fatal(1, "pi divider: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
