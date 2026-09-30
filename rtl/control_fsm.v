// control_fsm.v
module control_fsm #(
    parameter integer COUNT_W      = 32,
    parameter integer PI_W         = 32,
    parameter integer FBITS        = 29,
    parameter integer SPAWN_BATCH  = 10   // number of points to spawn per SPACE
)(
    input  wire clk,
    input  wire resetn,            // active-low reset

    // User inputs (one cycle pulses)
    input  wire space_pulse,
    input  wire enter_pulse,

    // From point FSM / lane
    input  wire point_done,        // from point_fsm / lane

    // Live counters
    input  wire [COUNT_W-1:0] inside_points,
    input  wire [COUNT_W-1:0] total_points,

    // Control outputs (one cycle pulses)
    output reg  start_point,       // to lane / point_fsm
    output reg  div_start,         // to internal divider (optional debug)
    output reg  update_hex,        // to HEX driver

    // Latched snapshots and displayed pi
    output reg  [COUNT_W-1:0]    inside_latched,
    output reg  [COUNT_W-1:0]    total_latched,
    output reg  [PI_W+FBITS-1:0] pi_reg      // holds last computed pi on HEX
);

    // ---------- State encoding ----------
    localparam S_IDLE        = 3'b000;
    localparam S_SPAWN_KICK  = 3'b001;
    localparam S_SPAWN_WAIT  = 3'b010;
    localparam S_PI_START    = 3'b011;
    localparam S_PI_WAIT     = 3'b100;
    localparam S_SHOW_PI     = 3'b101;

    reg [2:0] state, state_n;
    reg [$clog2(SPAWN_BATCH):0] spawn_cnt, spawn_cnt_n;

    // Divider connections (internal)
    wire [PI_W+FBITS-1:0] div_pi;
    wire                  div_done;

    // ---------- Combinational next-state + pulses ----------
    always @* begin
        // defaults: hold state & counter, no pulses
        state_n     = state;
        spawn_cnt_n = spawn_cnt;
        start_point = 1'b0;
        div_start   = 1'b0;
        update_hex  = 1'b0;

        case (state)
            S_IDLE: begin
                if (space_pulse) begin
                    // kick off SPAWN_BATCH points
                    spawn_cnt_n = SPAWN_BATCH - 1;
                    state_n     = S_SPAWN_KICK;
                end else if (enter_pulse && (total_points != {COUNT_W{1'b0}})) begin
                    state_n = S_PI_START;
                end
            end

            S_SPAWN_KICK: begin
                start_point = 1'b1;
                state_n     = S_SPAWN_WAIT;
            end

            S_SPAWN_WAIT: begin
                if (point_done) begin
                    if (spawn_cnt == 0) begin
                        state_n = S_IDLE;
                    end else begin
                        spawn_cnt_n = spawn_cnt - 1'b1;
                        state_n     = S_SPAWN_KICK;
                    end
                end
            end

            S_PI_START: begin
                div_start = 1'b1;
                state_n   = S_PI_WAIT;
            end

            S_PI_WAIT: begin
                if (div_done) begin
                    state_n = S_SHOW_PI;
                end
            end

            S_SHOW_PI: begin
                update_hex = 1'b1;
                state_n    = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

    // ---------- Sequential state & latches ----------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state          <= S_IDLE;
            spawn_cnt      <= {($clog2(SPAWN_BATCH)+1){1'b0}};
            inside_latched <= {COUNT_W{1'b0}};
            total_latched  <= {COUNT_W{1'b0}};
            pi_reg         <= {(PI_W+FBITS){1'b0}};
        end else begin
            state     <= state_n;
            spawn_cnt <= spawn_cnt_n;

            // Latch counters & pi exactly when divider finishes
            if (state == S_PI_WAIT && div_done) begin
                inside_latched <= inside_points;
                total_latched  <= total_points;
                pi_reg         <= div_pi;
            end
        end
    end

    // ---------- Internal divider ----------
    pi_divider #(
        .W    (PI_W),
        .FBITS(FBITS)
    ) u_pi_divider (
        .clk   (clk),
        .resetn(resetn),
        .start (div_start),
        .hits  (inside_points),
        .total (total_points),
        .busy  (),
        .valid (div_done),
        .pi_q  (div_pi)
    );

endmodule
