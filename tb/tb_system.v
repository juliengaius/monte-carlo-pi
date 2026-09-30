`timescale 1ns/1ps

// System-level testbench: real control_fsm + lane + mc_counters + pi_divider.
// Drives SPACE presses exactly like the board would, logs every sample, then
// presses ENTER and logs the latched hit/total counts and the Q3.29 pi result.
//
// Outputs (compared against model/mc_model by sim/compare.py):
//   build/schedule.txt     "<space_cycle> <batch_size>" per SPACE press
//   build/rtl_samples.csv  idx,cycle,x,y,hit per sample + final line
//
// Parameters (override with iverilog -P):
//   BATCH      points per SPACE press (control_fsm SPAWN_BATCH; board uses 10)
//   NUM_PRESS  number of SPACE presses
//   MAX_GAP    idle cycles between presses are pseudo-random in [0, MAX_GAP)

module tb_system;
    parameter integer BATCH     = 10;
    parameter integer NUM_PRESS = 200;
    parameter integer MAX_GAP   = 1000;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg space_pulse = 1'b0;
    reg enter_pulse = 1'b0;
    always #10 clk = ~clk;   // 50 MHz, like CLOCK_50

    // ---------------- DUT: same wiring as montecarlo_top ----------------
    wire start_point, total_inc, inside_inc, point_done;
    wire [15:0] unit_x_uq16, unit_y_uq16;
    wire vga_write;
    wire [9:0] vga_x;
    wire [8:0] vga_y, vga_color;
    wire [31:0] total_points, inside_points;
    wire div_start, update_hex;
    wire [31:0] inside_latched, total_latched;
    wire [60:0] pi_reg;

    lane U_LANE (
        .clk(clk), .resetn(resetn), .start_point(start_point),
        .total_inc(total_inc), .inside_inc(inside_inc),
        .unit_x_uq16(unit_x_uq16), .unit_y_uq16(unit_y_uq16),
        .point_done(point_done),
        .vga_write(vga_write), .vga_x(vga_x), .vga_y(vga_y), .vga_color(vga_color)
    );

    mc_counters U_CNTS (
        .clk(clk), .resetn(resetn),
        .total_inc(total_inc), .inside_inc(inside_inc),
        .total_points(total_points), .inside_points(inside_points)
    );

    control_fsm #(.COUNT_W(32), .PI_W(32), .FBITS(29), .SPAWN_BATCH(BATCH)) U_CTRL (
        .clk(clk), .resetn(resetn),
        .space_pulse(space_pulse), .enter_pulse(enter_pulse),
        .point_done(point_done),
        .inside_points(inside_points), .total_points(total_points),
        .start_point(start_point), .div_start(div_start), .update_hex(update_hex),
        .inside_latched(inside_latched), .total_latched(total_latched), .pi_reg(pi_reg)
    );

    // ---------------- cycle counter ----------------
    // cycle 0 = first rising edge after reset is released (matches the C model)
    integer cycle = 0;
    always @(posedge clk) cycle <= resetn ? cycle + 1 : 0;

    // ---------------- sample logger ----------------
    integer fs, fsched;
    integer idx = 0;
    integer latch_cycle;
    always @(posedge clk) if (resetn) begin
        if (U_LANE.unit_load) latch_cycle = cycle;   // edge where the unitizer latches the LFSRs
        if (total_inc) begin
            $fwrite(fs, "%0d,%0d,%0d,%0d,%0d\n", idx, latch_cycle, unit_x_uq16, unit_y_uq16, inside_inc);
            idx = idx + 1;
        end
    end

    // ---------------- stimulus ----------------
    integer p, gap, seed, press_cycle;
    initial begin
        fs     = $fopen("build/rtl_samples.csv", "w");
        fsched = $fopen("build/schedule.txt", "w");
        $fwrite(fs, "idx,cycle,x,y,hit\n");
        seed = 241;

        repeat (3) @(posedge clk);
        @(negedge clk) resetn = 1'b1;

        for (p = 0; p < NUM_PRESS; p = p + 1) begin
            // wait for the previous batch to finish (control FSM back in IDLE)
            while (U_CTRL.state !== 3'b000) @(negedge clk);
            gap = $unsigned($random(seed)) % MAX_GAP;
            repeat (gap) @(negedge clk);

            space_pulse = 1'b1;
            @(posedge clk) press_cycle = cycle;    // control_fsm samples SPACE on this edge
            $fwrite(fsched, "%0d %0d\n", press_cycle, BATCH);
            @(negedge clk) space_pulse = 1'b0;
        end

        while (U_CTRL.state !== 3'b000) @(negedge clk);
        repeat (5) @(negedge clk);

        enter_pulse = 1'b1;
        @(negedge clk) enter_pulse = 1'b0;
        @(posedge update_hex);
        @(negedge clk);

        $fwrite(fs, "final,hits=%0d,total=%0d,pi_q=%0d\n", inside_latched, total_latched, pi_reg);
        $fclose(fs);
        $fclose(fsched);
        $display("rtl: %0d samples, hits=%0d, pi_q=%0d", total_latched, inside_latched, pi_reg);
        $finish;
    end
endmodule
