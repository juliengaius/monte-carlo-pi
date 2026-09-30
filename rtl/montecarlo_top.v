module montecarlo_top (
    input wire CLOCK_50,
    input wire [1:0] KEY, // KEY[0] = resetn (active low), KEY[1] = point button (active low)
    input wire [1:0] SW, // display select
	 input wire PS2_CLK,
	 input wire PS2_DAT,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [9:0] LEDR,
    output wire [7:0] VGA_R,
    output wire [7:0] VGA_G,
    output wire [7:0] VGA_B,
    output wire VGA_HS,
    output wire VGA_VS,
    output wire VGA_BLANK_N,
    output wire VGA_SYNC_N,
    output wire VGA_CLK
);

    wire clk = CLOCK_50;
    wire resetn = KEY[0];     
    //wire start_point = ~KEY[1];  

    wire total_inc;
    wire inside_inc;
    wire point_done;
    wire [15:0] unit_x_uq16;
    wire [15:0] unit_y_uq16;

    wire lane_vga_write;
    wire [9:0] lane_vga_x;
    wire [8:0] lane_vga_y;
    wire [8:0] lane_vga_color;

    lane U_LANE (
        .clk (clk),
        .resetn (resetn),
        .start_point (start_point),
        .total_inc (total_inc),
        .inside_inc (inside_inc),
        .point_done (point_done),
        .unit_x_uq16 (unit_x_uq16),
        .unit_y_uq16 (unit_y_uq16),
        .vga_write  (lane_vga_write),
        .vga_x (lane_vga_x),
        .vga_y (lane_vga_y),
        .vga_color (lane_vga_color)
    );

    wire [31:0] total_points;
    wire [31:0] inside_points;

    mc_counters U_CNTS (
        .clk (clk),
        .resetn (resetn),
        .total_inc (total_inc),
        .inside_inc (inside_inc),
        .total_points (total_points),
        .inside_points (inside_points)
    );

    reg [31:0] disp;
    always @* begin
        case (SW)
            2'b00: disp = {16'h0000, unit_x_uq16};
            2'b01: disp = {16'h0000, unit_y_uq16};
            2'b10: disp = total_points;
            2'b11: disp = pi_scaled;
            default: disp = 32'h0;
        endcase
    end

    hex7seg h0 (.hex(disp[3:0]), .seg(HEX0));
    hex7seg h1 (.hex(disp[7:4]), .seg(HEX1));
    hex7seg h2 (.hex(disp[11:8]), .seg(HEX2));
    hex7seg h3 (.hex(disp[15:12]), .seg(HEX3));

    assign LEDR[0] = point_done;
    assign LEDR[9:1] = 0;

     // VGA adapter
    vga_adapter VGA (
        .resetn (resetn),
        .clock (CLOCK_50),
        .color (lane_vga_color),
        .x (lane_vga_x),
        .y (lane_vga_y),
        .write (lane_vga_write),
        .VGA_R (VGA_R),
        .VGA_G (VGA_G),
        .VGA_B (VGA_B),
        .VGA_HS (VGA_HS),
        .VGA_VS (VGA_VS),
        .VGA_BLANK_N (VGA_BLANK_N),
        .VGA_SYNC_N (VGA_SYNC_N),
        .VGA_CLK (VGA_CLK)
    );
    defparam VGA.RESOLUTION  = "640x480";
    defparam VGA.COLOR_DEPTH = 9;
    defparam VGA.BACKGROUND_IMAGE = "./MIF/quarter_circle_bg.mif";
	 
	 
	 //PS/2 interface
 	 wire [7:0] scan_code;
	 wire       scan_ready;
	 wire       space_pulse_kb;
 	 wire       enter_pulse_kb;

	 ps2_receiver PS2_IF (
		 .clk       (CLOCK_50),
		 .resetn    (resetn),
		 .ps2_clk   (PS2_CLK),
		 .ps2_data  (PS2_DAT),
		 .scan_code (scan_code),
		 .scan_ready(scan_ready)
	 );

	 ps2_space_enter PS2_KEYS (
		 .clk        (CLOCK_50),
		 .resetn     (resetn),
		 .scan_code  (scan_code),
		 .scan_ready (scan_ready),
		 .space_pulse(space_pulse_kb),
		 .enter_pulse(enter_pulse_kb)
	 );
	 
//	 assign LEDR[9] = scan_ready;
//	 
//	 hex7seg dbg_hex0 (.hex(scan_code[3:0]), .seg(HEX0));
//	 hex7seg dbg_hex1 (.hex(scan_code[7:4]), .seg(HEX1));
	 
	 wire key1_now = ~KEY[1];
	 reg key1_d;
	 always @(posedge clk or negedge resetn) begin
		if (!resetn)
			key1_d <= 1'b0;
		else
			key1_d <= key1_now;
		end
	wire key1_pulse = key1_now && ~key1_d;
	wire space_pulse = space_pulse_kb | key1_pulse;
	wire enter_pulse = enter_pulse_kb;
	 
	 //FSM outputs
	 wire start_point;
	 wire update_hex;
	 wire div_start;

	 wire [31:0] inside_latched;
	 wire [31:0] total_latched;
	 wire [32+29-1:0] pi_reg;   // 61 bits
	 wire [31:0] pi_scaled = (pi_reg * 32'd10000) >> 29;
	

	 control_fsm #(
		 .COUNT_W(32),
		 .PI_W(32),
		 .FBITS(29),
		 .SPAWN_BATCH(10)
	 ) FSM (
		 .clk           (CLOCK_50),
		 .resetn        (KEY[0]),

		 .space_pulse   (space_pulse),    // <-- SPACE triggers point batch
		 .enter_pulse   (enter_pulse),    // <-- ENTER triggers π compute

		 .point_done    (point_done),
		 .inside_points (inside_points),
		 .total_points  (total_points),

		 .start_point   (start_point),    // <-- goes to lane
		 .div_start     (div_start),      // internal
		 .update_hex    (update_hex),     // goes to hex_pi_driver

		 .inside_latched(inside_latched),
		 .total_latched (total_latched),
		 .pi_reg        (pi_reg)
);

	 wire [6:0] pi_h5, pi_h4, pi_h3, pi_h2, pi_h1, pi_h0;
	 wire pi_dp4;

	 hex_pi_driver #(
		 .IN_W(61),
		 .FBITS(29)
	 ) HEXPI (
		 .clk      (CLOCK_50),
		 .resetn   (KEY[0]),
		 .load     (update_hex),  // pulse from FSM
		 .value_in (pi_reg),

		 .busy(),
		 .valid(),

		 .HEX5(pi_h5),
		 .HEX4(pi_h4),
		 .HEX3(pi_h3),
		 .HEX2(pi_h2),
		 .HEX1(pi_h1),
		 .HEX0(pi_h0),
		 .DP4(pi_dp4)
);
	 
endmodule

module hex7seg (
    input wire [3:0] hex,
    output reg [6:0] seg
);
    always @* begin
        case (hex)
            4'h0: seg = 7'b100_0000;
            4'h1: seg = 7'b111_1001;
            4'h2: seg = 7'b010_0100;
            4'h3: seg = 7'b011_0000;
            4'h4: seg = 7'b001_1001;
            4'h5: seg = 7'b001_0010;
            4'h6: seg = 7'b000_0010;
            4'h7: seg = 7'b111_1000;
            4'h8: seg = 7'b000_0000;
            4'h9: seg = 7'b001_0000;
            4'hA: seg = 7'b000_1000;
            4'hB: seg = 7'b000_0011;
            4'hC: seg = 7'b100_0110;
            4'hD: seg = 7'b010_0001;
            4'hE: seg = 7'b000_0110;
            4'hF: seg = 7'b000_1110;
            default: seg = 7'b111_1111;
        endcase
    end
endmodule
