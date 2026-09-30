`timescale 1ns/1ps

// Unit test for lfsr32: reset loads the seed, the register follows
// x^32 + x^22 + x^2 + x + 1 (taps [31,21,1,0]) every enabled clock,
// holds when disabled, and never reaches the all-zero lock-up state.

module tb_lfsr32;
    reg clk = 1'b0, resetn = 1'b0, enable = 1'b1;
    wire [31:0] state;
    reg  [31:0] expected;
    integer errors = 0, checks = 0, i;
    always #10 clk = ~clk;

    lfsr32 #(.RESET_SEED(32'hF001_AB32)) dut (
        .clk(clk), .resetn(resetn), .enable(enable), .state(state)
    );

    function [31:0] step(input [31:0] s);
        step = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
    endfunction

    task expect_state(input [31:0] e, input [255:0] label);
        begin
            checks = checks + 1;
            if (state !== e) begin
                errors = errors + 1;
                if (errors <= 5) $display("FAIL: %0s state=%h expected %h", label, state, e);
            end
        end
    endtask

    initial begin
        #25;
        expect_state(32'hF001_AB32, "reset seed");
        @(negedge clk) resetn = 1'b1;

        expected = 32'hF001_AB32;
        for (i = 0; i < 1000; i = i + 1) begin
            @(negedge clk);
            expected = step(expected);
            expect_state(expected, "sequence");
            if (state == 32'd0) begin errors = errors + 1; $display("FAIL: all-zero lock-up"); end
        end

        enable = 1'b0;
        repeat (5) @(negedge clk);
        expect_state(expected, "hold when disabled");

        resetn = 1'b0; #1;
        expect_state(32'hF001_AB32, "async reset reloads seed");

        if (errors == 0) $display("PASS: lfsr32, %0d checks", checks);
        else             $fatal(1, "lfsr32: %0d of %0d checks failed", errors, checks);
        $finish;
    end
endmodule
