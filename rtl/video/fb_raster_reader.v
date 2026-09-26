//============================================================================
// fb_raster_reader.v — DDR framebuffer -> raster video (for arcade_video)
//----------------------------------------------------------------------------
// Scans RGB565 framebuffers out of HPS DDR3 in raster order and produces a
// standard video raster (ce_pix + hs/vs/hblank/vblank + RGB888).
//
// The canvas is H_ACT x (V_BAND + V_ACT). Two sources per line:
//   panel : (PANEL_EN) one full-width canvas row from a single panel buffer
//           at PANEL_BASE (stride H_ACT); otherwise the canvas is BG.
//   video : the frame at frame_base_hw, shown in a VID_W x VID_H window at
//           (VID_X, V_BAND + VID_Y) on top of the panel while vid_en is high.
// Each source row is fetched on fb_ddr's line port in bursts of up to BURST
// words into its own ping-pong line buffer: line N is displayed from one half
// while line N+1 lands in the other. The swap at end of line only happens
// once every fetch for the next line has landed, otherwise the current line
// repeats -- a stutter, never a torn line. fline (the row being fetched) is
// resynced to the raster once per frame, which is also when frame_base_hw
// and vid_en are latched, so one displayed frame always comes from one state.
//
// Alignment: VID_X, VID_W, STRIDE, H_ACT and every base must be multiples of
// 4 halfwords (one 64-bit word); VID_W and H_ACT must be <= 1024.
//============================================================================
module fb_raster_reader #(
    parameter [15:0] H_ACT  = 16'd320,
    parameter [15:0] V_ACT  = 16'd240,
    parameter [15:0] STRIDE = 16'd320,     // video framebuffer halfwords per row
    parameter [15:0] V_BAND = 16'd0,       // rows above the canvas forced black
    parameter [15:0] H_FP = 16'd8, H_SYNC = 16'd32, H_BP = 16'd24,
    parameter [15:0] V_FP = 16'd8, V_SYNC = 16'd4,  V_BP = 16'd16,
    parameter [2:0]  CE_DIV_LOG2 = 3'd3,   // ce_pix = clk / 2^CE_DIV_LOG2
    // Video window inside the H_ACT x V_ACT canvas.
    parameter [15:0] VID_X = 16'd0,
    parameter [15:0] VID_Y = 16'd0,
    parameter [15:0] VID_W = H_ACT,
    parameter [15:0] VID_H = V_ACT,
    parameter [15:0] BG    = 16'h0000,     // RGB565 canvas colour when PANEL_EN = 0
    parameter        PANEL_EN   = 1'b0,    // 1: canvas comes from the panel buffer
    parameter [26:0] PANEL_BASE = 27'd0,   // panel buffer halfword base (stride H_ACT)
    parameter [7:0]  BURST = 8'd16         // words per line-port request (128 wedges the HPS bridge)
)(
    input             clk,
    input             reset,               // active-high
    input      [26:0] frame_base_hw,       // DDR halfword base of the video frame to display
    input             vid_en,              // show the video window (else the panel shows through)

    // fb_ddr line port
    output reg [24:0] lr_addr,             // 64-bit word address (= halfword address >> 2)
    output reg [7:0]  lr_len,
    output reg        lr_req,
    input             lr_ack,
    input      [63:0] lr_data,
    input             lr_valid,

    // high while no fetch is in flight (fb_writer may use the bus)
    output            fill_idle,

    // video raster out (-> arcade_video)
    output            ce_pix,
    output reg        hsync,
    output reg        vsync,
    output reg        hblank,
    output reg        vblank,
    output reg [15:0] hpos,                // aligned (x,y) of the pixel now on vid_*
    output reg [15:0] vpos,
    output     [7:0]  vid_r,
    output     [7:0]  vid_g,
    output     [7:0]  vid_b
);
    localparam [15:0] V_DISP  = V_ACT + V_BAND;
    localparam [15:0] H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
    localparam [15:0] V_TOTAL = V_DISP + V_FP + V_SYNC + V_BP;
    localparam [15:0] VID_WORDS = VID_W >> 2;
    localparam [15:0] PAN_WORDS = H_ACT >> 2;

    // pixel clock enable
    localparam [3:0] CE_MASK4 = (4'd1 << CE_DIV_LOG2) - 4'd1;
    localparam [2:0] CE_MASK  = CE_MASK4[2:0];
    reg [2:0] cediv = 3'd0;
    always @(posedge clk) cediv <= cediv + 3'd1;
    assign ce_pix = ((cediv & CE_MASK) == 3'd0);

    // raster counters
    reg [15:0] hcnt = 16'd0, vcnt = 16'd0;
    wire h_last   = (hcnt == H_TOTAL - 16'd1);
    wire v_last   = (vcnt == V_TOTAL - 16'd1);
    wire h_active = (hcnt < H_ACT);
    wire v_active = (vcnt < V_DISP);
    wire [15:0] vid_x  = hcnt - VID_X;     // named wire: no expression bit-select in a .v file
    wire        in_vid = (hcnt >= VID_X) && (hcnt < VID_X + VID_W) &&
                         (vcnt >= V_BAND + VID_Y) && (vcnt < V_BAND + VID_Y + VID_H);

    // ping-pong line buffers, 2 lines x 256 words each, index {buf, word[7:0]}
    reg  [63:0] lb_vid [0:511];
    reg  [63:0] lb_pan [0:511];
    reg         disp_buf = 1'b0;
    wire        fill_buf = ~disp_buf;

    reg [63:0] vword_q, pword_q;           // registered BRAM reads
    reg  [1:0] vlane_q, plane_q;           // which halfword of each word is this pixel
    reg        active_q;
    reg        vid_q;                      // pixel comes from the video window

    // fill FSM
    localparam F_IDLE = 3'd0, F_PAN = 3'd1, F_VID = 3'd2, F_WAIT = 3'd3;
    reg  [2:0] fst = F_IDLE;
    reg        seg;                        // 0 = panel, 1 = video: which line buffer lr_data goes to
    reg  [7:0] widx;                       // next line-buffer word to store
    reg  [7:0] left;                       // words of this segment not yet requested
    reg [15:0] fline;                      // display line being fetched
    reg        fill_done_q;                // fline has fully landed, awaiting the swap
    reg        resync_pending;
    reg [26:0] frame_base_hw_q;            // latched once per frame
    reg        vid_en_q;                   // latched once per frame
    initial begin lr_req = 1'b0; lr_addr = 25'd0; lr_len = 8'd0; end
    wire [15:0] fline_next = (fline == V_TOTAL - 16'd1) ? 16'd0 : fline + 16'd1;
    wire [15:0] frow       = fline - V_BAND - VID_Y;              // video framebuffer row for fline
    wire [15:0] prow       = fline - V_BAND;                      // panel row for fline
    wire [26:0] row_hw     = frame_base_hw_q + frow * STRIDE;     // halfword address of the video row
    wire [26:0] prow_hw    = PANEL_BASE + prow * H_ACT;           // halfword address of the panel row
    wire        want_vid   = vid_en_q && (fline >= V_BAND + VID_Y) && (frow < VID_H);
    wire        want_pan   = PANEL_EN && (fline >= V_BAND) && (prow < V_ACT);
    // Skip panel words the video window hides (window flush with the left or right canvas edge).
    localparam [15:0] VID_X_W   = VID_X >> 2;
    localparam [15:0] VID_END_W = (VID_X + VID_W) >> 2;
    wire        hide       = want_vid && (VID_X_W == 16'd0 || VID_END_W == PAN_WORDS);
    wire [7:0]  pan_first  = (hide && VID_X_W == 16'd0) ? VID_END_W[7:0] : 8'd0;
    wire [7:0]  pan_words  = !hide ? PAN_WORDS[7:0] :
                             (VID_X_W == 16'd0) ? (PAN_WORDS[7:0] - VID_END_W[7:0]) : VID_X_W[7:0];
    wire [26:0] pan_hw     = prow_hw + {17'd0, pan_first, 2'b00};

    always @(posedge clk) begin
        if (reset) begin
            hcnt <= 0; vcnt <= 0; disp_buf <= 1'b0;
            hsync <= 0; vsync <= 0; hblank <= 1; vblank <= 1; active_q <= 0; vid_q <= 0;
            hpos <= 16'd0; vpos <= 16'd0;
            fst <= F_IDLE; widx <= 8'd0;   // lr_req keeps its value: fb_ddr may still be finishing a burst
            frame_base_hw_q <= frame_base_hw;      // never scan the buffer the writer starts on
            vid_en_q <= vid_en;
            fline <= 16'd0; fill_done_q <= 1'b0; resync_pending <= 1'b0;
        end else begin
            // ---- display timing (ce_pix-gated); never stalls on the fetch ----
            if (ce_pix) begin
                vword_q  <= lb_vid[{disp_buf, vid_x[9:2]}];
                pword_q  <= lb_pan[{disp_buf, hcnt[9:2]}];
                vlane_q  <= vid_x[1:0];
                plane_q  <= hcnt[1:0];
                vid_q    <= in_vid & vid_en_q;
                active_q <= h_active & v_active & (vcnt >= V_BAND);
                hpos     <= hcnt;   vpos <= vcnt;
                hblank   <= ~h_active;
                vblank   <= ~v_active;
                hsync    <= (hcnt >= H_ACT + H_FP) && (hcnt < H_ACT + H_FP + H_SYNC);
                vsync    <= (vcnt >= V_DISP + V_FP) && (vcnt < V_DISP + V_FP + V_SYNC);
                if (h_last) begin
                    hcnt <= 16'd0;
                    vcnt <= v_last ? 16'd0 : vcnt + 16'd1;
                    // swap only if the next line has landed; otherwise repeat this one
                    if (fill_done_q) begin
                        disp_buf    <= ~disp_buf;
                        fill_done_q <= 1'b0;
                    end
                    if (v_last) resync_pending <= 1'b1;
                end else begin
                    hcnt <= hcnt + 16'd1;
                end
            end

            // ---- fill FSM (every clk): panel segment, then video segment ----
            case (fst)
            F_IDLE:
                if (!fill_done_q) begin
                    fst <= F_PAN;
                    if (resync_pending) begin
                        fline           <= 16'd1;      // one row ahead of the raster
                        frame_base_hw_q <= frame_base_hw;
                        vid_en_q        <= vid_en;
                        resync_pending  <= 1'b0;
                    end else begin
                        fline <= fline_next;
                    end
                end
            F_PAN:
                if (lr_ack != lr_req) begin
                    // previous burst still returning (only possible right after a reset): wait it out
                end else if (want_pan && pan_words != 8'd0) begin
                    lr_addr <= pan_hw[26:2];
                    lr_len  <= (pan_words > BURST) ? BURST : pan_words;
                    left    <= (pan_words > BURST) ? pan_words - BURST : 8'd0;
                    lr_req  <= ~lr_req;
                    seg     <= 1'b0;
                    widx    <= pan_first;             // line-buffer word = canvas word position
                    fst     <= F_WAIT;
                end else begin
                    fst <= F_VID;
                end
            F_VID:
                if (want_vid) begin
                    lr_addr <= row_hw[26:2];
                    lr_len  <= (VID_WORDS[7:0] > BURST) ? BURST : VID_WORDS[7:0];
                    left    <= (VID_WORDS[7:0] > BURST) ? VID_WORDS[7:0] - BURST : 8'd0;
                    lr_req  <= ~lr_req;
                    seg     <= 1'b1;
                    widx    <= 8'd0;
                    fst     <= F_WAIT;
                end else begin
                    fst         <= F_IDLE;             // nothing (more) to fetch for this line
                    fill_done_q <= 1'b1;
                end
            F_WAIT: begin
                if (lr_valid) begin
                    if (seg) lb_vid[{fill_buf, widx}] <= lr_data;
                    else     lb_pan[{fill_buf, widx}] <= lr_data;
                    widx <= widx + 8'd1;
                end
                if (lr_ack == lr_req) begin          // last word of this burst arrives on this same edge
                    if (left != 8'd0) begin          // next burst of the same segment
                        lr_addr <= lr_addr + {17'd0, lr_len};
                        lr_len  <= (left > BURST) ? BURST : left;
                        left    <= (left > BURST) ? left - BURST : 8'd0;
                        lr_req  <= ~lr_req;
                    end else if (!seg) begin
                        fst <= F_VID;                // panel row done, now the video row
                    end else begin
                        fst         <= F_IDLE;
                        fill_done_q <= 1'b1;
                    end
                end
            end
            default: fst <= F_IDLE;
            endcase
        end
    end

    assign fill_idle = fill_done_q;

    wire [15:0] vpx = (vlane_q == 2'd0) ? vword_q[15:0]  :
                      (vlane_q == 2'd1) ? vword_q[31:16] :
                      (vlane_q == 2'd2) ? vword_q[47:32] : vword_q[63:48];
    wire [15:0] ppx = (plane_q == 2'd0) ? pword_q[15:0]  :
                      (plane_q == 2'd1) ? pword_q[31:16] :
                      (plane_q == 2'd2) ? pword_q[47:32] : pword_q[63:48];
    wire [15:0] px  = vid_q ? vpx : (PANEL_EN ? ppx : BG);
    assign vid_r = active_q ? {px[15:11], px[15:13]} : 8'd0;  // 5->8
    assign vid_g = active_q ? {px[10:5],  px[10:9]}  : 8'd0;  // 6->8
    assign vid_b = active_q ? {px[4:0],   px[4:2]}   : 8'd0;  // 5->8
endmodule
