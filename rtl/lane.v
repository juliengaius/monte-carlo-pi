// instantiate_lane.v
module lane
(
    input  wire clk,
    input  wire resetn,
    input  wire start_point, // from control FSM

    // to shared counters
    output wire total_inc,
    output wire inside_inc,

    // to display rand x rand y
    output wire [15:0] unit_x_uq16, unit_y_uq16,

    // back to control
    output wire point_done,

    output wire vga_write,
    output wire [9:0] vga_x,
    output wire [8:0] vga_y,
    output wire [8:0] vga_color
);
    // LFSRs free-run
    wire [31:0] rand_x, rand_y;

    lfsr32 #(
        .RESET_SEED(32'hF001_AB32)
    ) LFSR_X (
        .clk (clk),
        .resetn (resetn),
        .enable (1'b1),
        .state (rand_x)
    );

    lfsr32 #(
        .RESET_SEED(32'hF000_5465)
    ) LFSR_Y (
        .clk (clk),
        .resetn (resetn),
        .enable (1'b1),
        .state (rand_y)
    );

    // unitizer
    wire unit_valid;
    wire unit_load;
    wire load_seed;

    unitizer_uq16 UZ (
        .clk (clk),
        .resetn (resetn),
        .load (unit_load), 
        .rx (rand_x),
        .ry (rand_y),
        .x_uq16 (unit_x_uq16),
        .y_uq16 (unit_y_uq16),
        .valid (unit_valid)
    );

    // hit (combinational)
    wire inside_comb;
    hit_kernel_uq16_comb HIT (
        .x_in (unit_x_uq16),
        .y_in (unit_y_uq16),
        .inside(inside_comb)
    );
    
    // sprite handshake between point_fsm and sprite_drawer
    wire sprite_start;
    wire [9:0] sprite_center_x;
    wire [8:0] sprite_center_y;
    wire sprite_is_inside;
    wire sprite_done;

    // point FSM
    point_fsm PFSM (
        .clk (clk),
        .resetn (resetn),
        .start_point (start_point),

        .load_seed (load_seed),
        .unit_load (unit_load),
        .unit_x_uq16 (unit_x_uq16),
        .unit_y_uq16 (unit_y_uq16),
        .unit_valid (unit_valid),

        .inside_comb (inside_comb),

        .total_inc (total_inc),
        .inside_inc (inside_inc),
        .point_done (point_done),

        .sprite_start (sprite_start),
        .sprite_center_x (sprite_center_x),
        .sprite_center_y (sprite_center_y),
        .sprite_is_inside (sprite_is_inside),
        .sprite_done (sprite_done)
    );

    // sprite drawer: produces final VGA stream
    sprite_drawer #(
        .COLOR_DEPTH (9),
        .XOBJ (4),
        .YOBJ (4),
        .CRUMB_INIT_FILE ("./MIF/crumb_16_16_9.mif"),
        .BERRY_INIT_FILE ("./MIF/berry_16_16_9.mif")
    ) SD (
        .clk (clk),
        .resetn (resetn),
        .start (sprite_start),
        .center_x (sprite_center_x),
        .center_y (sprite_center_y),
        .is_inside (sprite_is_inside),

        .vga_x (vga_x),
        .vga_y (vga_y),
        .vga_color (vga_color),
        .vga_write (vga_write),

        .done (sprite_done)
    );


endmodule