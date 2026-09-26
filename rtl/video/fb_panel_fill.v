//============================================================================
// fb_panel_fill.v — TEMPORARY: fills the panel buffer with a test pattern
// after reset, through fb_ddr's random halfword port (R). Placeholder until
// the asset blitter writes real panel content.
//
// Pattern (RGB565): 1-px white border on the canvas edges, light-grey grid
// lines every 64 px, colour gradient elsewhere. Straight, unbroken grid lines
// on screen prove the panel addressing end to end.
//============================================================================
module fb_panel_fill #(
    parameter [15:0] W    = 16'd960,
    parameter [15:0] H    = 16'd540,
    parameter [26:0] BASE = 27'd0          // panel buffer halfword base (stride W)
)(
    input             clk,
    input             reset,
    input             refill,              // pulse: repaint the whole panel (e.g. on restart)

    output reg [27:1] r_addr,
    output reg [15:0] r_din,
    output     [1:0]  r_be,
    output            r_we,
    output reg        r_req,
    input             r_ack,
    output reg        done
);
    assign r_be = 2'b11;
    assign r_we = 1'b1;

    reg [15:0] x, y;
    reg [26:0] hw;                         // running halfword address
    reg        busy;
    reg        refill_pend;
    initial begin r_req = 1'b0; done = 1'b0; end

    wire border = (x == 16'd0) || (x == W - 16'd1) || (y == 16'd0) || (y == H - 16'd1);
    wire grid   = (x[5:0] == 6'd0) || (y[5:0] == 6'd0);
    wire [15:0] pat = border ? 16'hFFFF :
                      grid   ? 16'hC618 :
                      {x[9:5], y[9:4], 5'd12};

    always @(posedge clk) begin
        if (reset) begin
            x <= 16'd0; y <= 16'd0; hw <= BASE; busy <= 1'b0; done <= 1'b0; refill_pend <= 1'b0;
            // r_req keeps its value: fb_ddr is not reset and tracks the toggle
        end else if ((refill || refill_pend) && !busy) begin
            x <= 16'd0; y <= 16'd0; hw <= BASE; done <= 1'b0; refill_pend <= 1'b0;
        end else if (!done) begin
            if (refill) refill_pend <= 1'b1;       // a write is in flight: restart once it lands
            if (!busy) begin
                if (r_ack == r_req) begin
                    r_addr <= hw;
                    r_din  <= pat;
                    r_req  <= ~r_req;
                    busy   <= 1'b1;
                end
            end else if (r_ack == r_req) begin
                busy <= 1'b0;
                hw   <= hw + 27'd1;
                if (x == W - 16'd1) begin
                    x <= 16'd0;
                    if (y == H - 16'd1) done <= 1'b1;
                    else                y <= y + 16'd1;
                end else begin
                    x <= x + 16'd1;
                end
            end
        end
    end
endmodule
