// point_FSM.v
module point_fsm
(
    input wire clk,
    input wire resetn,

    // from control FSM
    input wire start_point, // 1-cycle pulse (or level, your choice)

    // to lfsr (optional reseed)
    output reg load_seed,

    // from LFSRs via unitizer
    output reg unit_load,  // tell unitizer to latch current LFSR outputs
    input wire [15:0] unit_x_uq16, // latched output from unitizer
    input wire [15:0] unit_y_uq16,
    input wire unit_valid,  // can ignore if we trust latency

    // from hit kernel (combinational)
    input wire inside_comb,

    // to counters
    output reg total_inc,
    output reg inside_inc,

    // back to control
    output reg point_done,

    // to sprite drawer
    output reg sprite_start,
    output reg [9:0] sprite_center_x,
    output reg [8:0] sprite_center_y,
    output reg sprite_is_inside,
    input wire sprite_done
);
    // states
    localparam P_IDLE = 3'd0;
    localparam P_GET_RANDOM  = 3'd1;
    localparam P_COMPUTE_HIT = 3'd2;
    localparam P_UPDATE_CNT  = 3'd3;
    localparam P_DRAW = 3'd4;
    localparam P_DONE = 3'd5;

    // qarter square corners: (192,36), (192,418), (574,418)
    localparam [9:0] ORIGIN_X = 10'd192; // (0,0) x
    localparam [8:0] ORIGIN_Y = 9'd418; // (0,0) y (bottom)
    localparam [8:0] R_PIX = 9'd382; // side length in pixels

    // multiply unit_x/unit_y (UQ0.16) by 382 and scale back down
    wire [24:0] x_mul = unit_x_uq16 * R_PIX; // 16+9-1 bits
    wire [24:0] y_mul = unit_y_uq16 * R_PIX;

    wire [8:0] x_off = x_mul[24:16];  // 0 to 381
    wire [8:0] y_off = y_mul[24:16];  // 0 to381

    wire [9:0] x_pix = ORIGIN_X + {1'b0, x_off}; // ≈192 to 573
    wire [8:0] y_pix = ORIGIN_Y - y_off;         // ≈418 to 37

    reg [2:0] state, state_next;
    reg inside_reg;

    // state and output logic
    always @* begin
        // defaults
        load_seed = 1'b0;
        unit_load = 1'b0;
        total_inc = 1'b0;
        inside_inc = 1'b0;
        point_done = 1'b0;

        sprite_start = 1'b0;
        sprite_center_x = 10'd0;
        sprite_center_y = 9'd0;
        sprite_is_inside = 1'b0;

        state_next = state;

        case (state)
            P_IDLE: begin
                if (start_point)
                    state_next = P_GET_RANDOM;
            end

            // latch the current LFSR outputs (through unitizer)
            P_GET_RANDOM: begin
                load_seed  = 1'b1;
                unit_load  = 1'b1;  
                state_next = P_COMPUTE_HIT;
            end

            // hit is combinational on the latched unit_x/y
            P_COMPUTE_HIT: begin
                state_next = P_UPDATE_CNT;
            end

            // pulse counters using the combinational result
            P_UPDATE_CNT: begin
                total_inc = 1'b1;
                inside_inc = inside_comb; 

                // en sprite drawer for this point
                sprite_start = 1'b1; 
                sprite_center_x = x_pix;
                sprite_center_y = y_pix;
                sprite_is_inside = inside_reg; 

                state_next = P_DRAW;
            end

            // wait until sprite has finished drawing 16x16
            P_DRAW: begin
                if (sprite_done)
                    state_next = P_DONE;
            end

            P_DONE: begin
                point_done = 1'b1;
                state_next = P_IDLE;
            end

            default: state_next = P_IDLE;
        endcase
    end

    // state register
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            state <= P_IDLE;
        else
            state <= state_next;
    end

    // latch inside/outside for color/type
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            inside_reg <= 1'b0;
        else if (state == P_COMPUTE_HIT)
            inside_reg <= inside_comb;
    end

endmodule
