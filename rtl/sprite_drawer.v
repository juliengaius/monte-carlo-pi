module sprite_drawer #(
    parameter COLOR_DEPTH = 9,
    parameter XOBJ = 4, // 2^4 = 16 pixels wide
    parameter YOBJ = 4, // 2^4 = 16 pixels tall
    parameter CRUMB_INIT_FILE = "./MIF/crumb_16_16_9.mif",
    parameter BERRY_INIT_FILE = "./MIF/berry_16_16_9.mif"
)(
    input wire clk,
    input wire resetn,

    // new sprite
    input wire start, 
    input wire [9:0] center_x,
    input wire [8:0] center_y,
    input wire is_inside, // 1 = berry, 0 = crumb

    // VGA outputs
    output reg [9:0] vga_x,
    output reg [8:0] vga_y,
    output reg [COLOR_DEPTH-1:0] vga_color,
    output reg vga_write,

    output reg done
);
    localparam BOX_SIZE_X = (1 << XOBJ); // 16
    localparam BOX_SIZE_Y = (1 << YOBJ); // 16

    // FSM states
    localparam S_IDLE = 2'd0;
    localparam S_DRAW = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0] state, state_next;

    // latched center
    reg [9:0] center_x_reg;
    reg [8:0] center_y_reg;
    reg is_inside_reg;

    // local sprite coords (0..15)
    reg [XOBJ-1:0] xc;
    reg [YOBJ-1:0] yc;

    // ROM interface
    wire [XOBJ+YOBJ-1:0] addr = {yc, xc};
    wire [COLOR_DEPTH-1:0] crumb_color;
    wire [COLOR_DEPTH-1:0] berry_color;
    wire [COLOR_DEPTH-1:0] sprite_color_raw;

    // instantiate both ROMs
    object_mem CRUMB_MEM (
        .address(addr),
        .clock (clk),
        .q (crumb_color)
    );
    defparam CRUMB_MEM.n = COLOR_DEPTH;
    defparam CRUMB_MEM.Mn = XOBJ + YOBJ;
    defparam CRUMB_MEM.INIT_FILE = CRUMB_INIT_FILE;

    object_mem BERRY_MEM (
        .address(addr),
        .clock (clk),
        .q (berry_color)
    );
    defparam BERRY_MEM.n = COLOR_DEPTH;
    defparam BERRY_MEM.Mn = XOBJ + YOBJ;
    defparam BERRY_MEM.INIT_FILE = BERRY_INIT_FILE;

    assign sprite_color_raw = is_inside_reg ? berry_color : crumb_color;

    //state table
    always @* begin
        // defaults
        vga_write = 1'b0;
        vga_x = 10'd0;
        vga_y = 9'd0;
        vga_color = {COLOR_DEPTH{1'b0}};
        done = 1'b0;

        state_next = state;

        case (state)
            S_IDLE: begin
                if (start)
                    state_next = S_DRAW;
            end

            S_DRAW: begin

                // compute pixel's absolute coordinates
                // center - 8 + (0..15)
                vga_x = center_x_reg - (BOX_SIZE_X >> 1) + xc;
                vga_y = center_y_reg - (BOX_SIZE_Y >> 1) + yc;
                vga_color = sprite_color_raw;

                // if pixel is blakc dont write to simulate vectir image
                if (sprite_color_raw != {COLOR_DEPTH{1'b0}})
                    vga_write = 1'b1;
                else
                    vga_write = 1'b0;

                // next pixel
                if (xc == BOX_SIZE_X-1 && yc == BOX_SIZE_Y-1)
                    state_next = S_DONE;
                else
                    state_next = S_DRAW;
            end

            S_DONE: begin
                done = 1'b1;
                // wait to be released (start should be 0 again)
                if (!start)
                    state_next = S_IDLE;
            end

            default: state_next = S_IDLE;
        endcase
    end
    // state ffs
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            center_x_reg <= 10'd0;
            center_y_reg <= 9'd0;
            is_inside_reg <= 1'b0;
            xc <= {XOBJ{1'b0}};
            yc <= {YOBJ{1'b0}};
        end else begin
            state <= state_next;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        center_x_reg <= center_x;
                        center_y_reg <= center_y;
                        is_inside_reg <= is_inside;
                        xc <= {XOBJ{1'b0}};
                        yc <= {YOBJ{1'b0}};
                    end
                end

                S_DRAW: begin
                    // walk over sprite grid
                    if (xc == BOX_SIZE_X-1) begin
                        xc <= {XOBJ{1'b0}};
                        if (yc != BOX_SIZE_Y-1)
                            yc <= yc + 1'b1;
                    end else begin
                        xc <= xc + 1'b1;
                    end
                end

                S_DONE: begin

                end
            endcase
        end
    end

endmodule
