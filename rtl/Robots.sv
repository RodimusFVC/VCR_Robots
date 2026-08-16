//============================================================================
//
//  Isaac Asimov's ROBOTS (Kodak KV-701VT, 1988) -- playback controller
//  Copyright (C) 2026 Rodimus
//
//  STRIP-2026-08-15: this REPLACES the Dragon's Lair control layer
//  (rtl/DragonsLair{,_CPU,_LDV1000}.sv), which was deleted rather than renamed.
//  Robots is not an arcade PCB -- there is no CPU, no AY-3-8910 and no Pioneer
//  LD-V1000 to emulate. The "hardware" is a domestic VCR, so this module is a
//  tape transport, and the whole game is one linear play of robots.dlv.
//
//  It drives rtl/video/dlv_streamer.v across the SAME five-signal seam the DL
//  control layer used, so everything below it (streamer, JPEG decoder, triple
//  buffer, raster reader, led_band) is untouched:
//
//      ld_frame_o      -> dlv_streamer.ld_curr_frame   WHICH frame to show
//      ld_playing_o    -> dlv_streamer.ld_playing      audio drain gate
//      ld_search_cmd_o -> dlv_streamer.seek_flush      audio ring flush
//      led_digits_o    -> led_band                     on-screen debug readout
//      dbg_led         -> LED_USER                     "core alive" heartbeat
//
//  ---- HOW PLAYBACK IS ACTUALLY DRIVEN (read out of dlv_streamer.v, not assumed)
//    dlv_streamer.v:603   vid_target = f(ld_curr_frame)   (via disc_rel; 1:1 here)
//    dlv_streamer.v:745   a fetch fires ONLY when vid_target != last_fetched_frame
//  The streamer's internal ~30 Hz pacer is only a fetch OPPORTUNITY rate -- it
//  does not choose the frame. So frame_ctr below is the sole thing that advances
//  video: freeze it and the picture holds on its current frame. That is the
//  entirety of play/pause, and it needs no seek, no flush and no re-decode.
//
//  ---- WHY PAUSE DOES NOT PULSE ld_search_cmd_o
//  The design note guessed that pause/resume would be "a seek to the current
//  frame". Reading the streamer, that would be actively WRONG: seek_flush EMPTIES
//  the audio ring (dlv_streamer.v:432) to discard a stale segment, so using it for
//  a pause would throw away correctly-buffered audio and force a refill -- an
//  audible gap on every resume. Freezing in place is both simpler and better:
//  aud_credit only accrues when ld_curr_frame advances (dlv_streamer.v:412-414),
//  so a frozen counter starves the credit, aud_drain stops, and aud_rd HOLDS its
//  position. Audio stalls cleanly and resumes exactly where it left off.
//  (That also answers the "audio behaviour during an INDEFINITE hold" question
//  the design note flagged #unverified: the frame-lock credit gates the drain, so
//  a stopped counter cannot underrun the ring. Verified by reading the logic --
//  still wants a HW confirmation before the note is updated.)
//
//  ---- FUTURE: the segment / play-order index
//  A play order, per-segment indices and "held frame" markers are coming as a
//  separate index file. Nothing here needs to change to accept them: a segment
//  table becomes a block that LOADS frame_ctr and pulses ld_search_cmd_o, while
//  this transport keeps owning "does the frame number advance, and how fast".
//  That is why frame_ctr has an explicit load path (frame_load/frame_load_val)
//  even though nothing drives it yet.
//
//============================================================================

module Robots #(
    // CLK-PARAM-2026-08-15: the core clock is ONE number and everything derives
    // from it. 40 MHz is pure Dragon's Lair inheritance (Z80 /10, AY /20 -- both
    // deleted); nothing in Robots needs it, and a 1920x1080 canvas at 29.97 fps
    // wants ~67 MHz. Raising it also raises DDR throughput, since DDRAM_CLK is
    // this same clock. Change CLK_HZ here, the PLL, and nothing else.
    parameter [31:0] CLK_HZ = 32'd40_000_000,

    // 29.97 fps NTSC content rate = 30000/1001 fps exactly, so one film frame is
    // CLK_HZ * 1001 / 30000 cycles. 64-bit intermediate on purpose: at 40 MHz the
    // product is 4.004e10 and would overflow a 32-bit expression.
    // (40 MHz -> 1,334,667 = 29.96999 fps, matching the old hand-computed value.)
    parameter [31:0] FILM_PERIOD = 32'(longint'(CLK_HZ) * 1001 / 30000),

    // robots.dlv holds 81,065 frames -> last valid index is 81,064.
    parameter [16:0] LAST_FRAME  = 17'd81064,

    // 1 = hold the last frame at end of tape, 0 = wrap to the start.
    // The tape is a linear play with an interactive endgame AFTER it ends, so
    // holding (not wrapping) is the correct behaviour.
    parameter        HOLD_AT_END = 1'b1
)(
    input             reset,            // ACTIVE LOW (top level inverts MiSTer's)
    input             clk_sys,          // 40 MHz

    // Player inputs, active HIGH. Mapping follows README.MD.
    input       [7:0] p1,               // {  -, -, btn_b, btn_a, right, left, down, up }
    input       [3:0] cab,              // { coin2, coin1, start2, start1 }

    input             pause,            // MiSTer system pause (OSD / 'P')
    input             disc_hold,        // video pipeline is holding (seek/refill)

    output     [63:0] led_digits_o,     // -> led_band (16 x 4-bit BCD digits)
    output            dbg_led,          // -> LED_USER

    output     [16:0] ld_frame_o,       // -> dlv_streamer.ld_curr_frame
    output            ld_search_cmd_o,  // -> dlv_streamer.seek_flush
    output            ld_playing_o,     // -> dlv_streamer.ld_playing

    // ---- seam for the overlay renderer (clue panel / dialogs), not built yet ----
    output            ui_modal_o,       // 1 = draw a modal over the video window
    output            ui_confirm_sel_o, // 0 = "No" highlighted, 1 = "Yes"

    // Clue cards. card_show_o is high for the whole Clue Card segment: the tape
    // is still rolling underneath (audio continues), so the renderer should paint
    // the full-screen card OVER the video window and drop back to the thumbnail
    // strip when it falls. cards_revealed_o is the sticky set for that strip.
    output            card_show_o,
    output      [2:0] card_id_o,        // 0..5 = card A..F
    output      [5:0] cards_revealed_o
);

    //------------------------------------------------------------------------
    // Controls (README.MD mapping)
    //   Start  -> play / pause playback     <-- the only one wired in this step
    //   A      -> select / activate         )
    //   B      -> return / revert           )  declared so the mapping is fixed
    //   D-Pad  -> move selection            )  now and does not get redone later
    //   Select -> RESTART / RESET GAME  (2026-08-15: was "select difficulty" in
    //             README.MD. Difficulty is a BOOT-TIME choice -- it picks which
    //             64-entry solution table and which 12 card bitmaps are live -- so
    //             changing it mid-tape would invalidate every clue already
    //             revealed. Restart is the honest verb for "put me back to the
    //             boot menu", and it is the same operation internally.)
    //------------------------------------------------------------------------
    wire btn_start  = cab[0];           // start1  -> play / pause
    wire btn_select = cab[2];           // coin1   -> restart
    /* verilator lint_off UNUSED */
    wire btn_up     = p1[0];
    wire btn_down   = p1[1];
    wire btn_left   = p1[2];
    wire btn_right  = p1[3];
    wire btn_a      = p1[4];            // select / activate (zoom in)
    wire btn_b      = p1[5];            // return / revert   (zoom out)
    /* verilator lint_on UNUSED */
    wire btn_seek_p = p1[6];            // L -> seek to prior index
    wire btn_seek_n = p1[7];            // R -> seek to next index

    // Edge-detect everything so a held button acts once, not every clock.
    reg  start_q, select_q, a_q, b_q, left_q, right_q, seekp_q, seekn_q;
    wire start_edge   = btn_start  & ~start_q;
    wire restart_edge = btn_select & ~select_q;
    wire a_edge       = btn_a      & ~a_q;
    wire b_edge       = btn_b      & ~b_q;
    wire move_edge    = (btn_left  & ~left_q) | (btn_right & ~right_q);
    wire seekp_edge   = btn_seek_p & ~seekp_q;
    wire seekn_edge   = btn_seek_n & ~seekn_q;

    always @(posedge clk_sys) begin
        if (!reset) begin
            start_q  <= 1'b0;  select_q <= 1'b0;
            a_q      <= 1'b0;  b_q      <= 1'b0;
            left_q   <= 1'b0;  right_q  <= 1'b0;
            seekp_q  <= 1'b0;  seekn_q  <= 1'b0;
        end else begin
            start_q  <= btn_start;  select_q <= btn_select;
            a_q      <= btn_a;      b_q      <= btn_b;
            left_q   <= btn_left;   right_q  <= btn_right;
            seekp_q  <= btn_seek_p; seekn_q  <= btn_seek_n;
        end
    end

    //------------------------------------------------------------------------
    // Transport registers.
    // Declared HERE, above the modal layer, because the modal block samples
    // `playing` into resume_after. Verilator accepts the forward reference;
    // Quartus 17.0 is stricter about use-before-declaration, so the declaration
    // leads. Do not move these back down with the transport logic.
    //------------------------------------------------------------------------
    reg         playing;
    reg  [16:0] frame_ctr;
    reg  [31:0] film_div;
    reg   [5:0] cards;                  // sticky: card A..F has been revealed

    //------------------------------------------------------------------------
    // MODAL UI LAYER (2026-08-15)
    //
    // A modal is any full-screen prompt that takes over the controls: the
    // Restart confirmation today, the zoomed-card overlay next.
    //
    // WHO OWNS THE PAUSE.  Start stays a real, always-available manual pause --
    // the "potty break" case -- but it must NOT be the thing that decides whether
    // the tape runs while a modal is up. So a modal HOLDS the tape for as long as
    // it is open and REMEMBERS the transport state it interrupted (resume_after).
    // Cancelling restores that state exactly, which is the whole point: if the
    // player had deliberately paused before opening a dialog, backing out of the
    // dialog must not start the tape rolling. Start is ignored while a modal is
    // open, so the two can never disagree about who is holding the tape.
    //
    // RENDERING IS NOT BUILT YET. This is the state machine and the seam only --
    // ui_modal_o / ui_confirm_sel_o are what the overlay renderer will consume
    // once the clue-panel framebuffer exists. Until then the state is observable
    // on the LED band (debug digit 15), which is the only in-fabric readout
    // available on this setup.
    //------------------------------------------------------------------------
    localparam [1:0] UI_IDLE    = 2'd0,
                     UI_RESTART = 2'd1;

    reg  [1:0] ui_state;
    reg        confirm_sel;     // 0 = No (default -- destructive action never pre-selected)
    reg        resume_after;    // transport state to restore if the modal is cancelled

    wire ui_modal   = (ui_state != UI_IDLE);

    // In a two-option prompt, left and right both just toggle: there is nowhere
    // else to go, and it means the player cannot get lost holding one direction.
    wire ui_open    = ~ui_modal & restart_edge;
    wire do_restart = (ui_state == UI_RESTART) & a_edge &  confirm_sel;   // "Yes"
    wire do_cancel  = (ui_state == UI_RESTART) & (b_edge | (a_edge & ~confirm_sel));

    always @(posedge clk_sys) begin
        if (!reset) begin
            ui_state     <= UI_IDLE;
            confirm_sel  <= 1'b0;
            resume_after <= 1'b0;
        end else if (ui_open) begin
            ui_state     <= UI_RESTART;
            confirm_sel  <= 1'b0;         // always opens on "No"
            resume_after <= playing;      // remember what we interrupted
        end else if (do_restart | do_cancel) begin
            ui_state     <= UI_IDLE;
        end else if (ui_modal & move_edge) begin
            confirm_sel  <= ~confirm_sel;
        end
    end

    //------------------------------------------------------------------------
    // Transport logic  (registers declared above the modal layer -- see there)
    //------------------------------------------------------------------------
    wire        at_end    = (frame_ctr >= LAST_FRAME);
    wire        film_tick = (film_div == FILM_PERIOD - 32'd1);

    // Advance only when genuinely playing AND nothing is holding us: the player's
    // own pause, the MiSTer system pause, the video pipeline, or an open modal.
    // All four freeze the COUNTER rather than the tick, so the film cadence keeps
    // its phase across a hold however long it lasts.
    wire        frame_adv = film_tick & playing & ~pause & ~disc_hold & ~ui_modal
                            & (phase == G_PLAY)
                            & ~(at_end & HOLD_AT_END);

    //------------------------------------------------------------------------
    // GAME STATE: skill -> card mode -> play.  2026-08-15
    //
    // THE SEED IS THE CARD BITMASK. The six clue cards carry bit values
    // A=1 B=2 C=4 D=8 E=16 F=32, and the GAME NUMBER is their sum -- so the 6-bit
    // mask of "which side was drawn" IS the 0..63 seed. No arithmetic needed.
    //
    // Two boot choices, both made before any video rolls (difficulty must not be
    // changed mid-tape: it selects which solution table AND which card bitmaps are
    // live, so a late change would invalidate every clue already revealed):
    //   G_SKILL     pick packet 0..3   (Beginner/Intermediate/Advanced/Expert)
    //   G_CARDMODE  pick Random (default) or Player-picks
    //   G_PLAY      tape rolls
    //------------------------------------------------------------------------
    localparam [1:0] G_SKILL = 2'd0, G_CARDMODE = 2'd1, G_PLAY = 2'd2;

    reg  [1:0] phase;
    reg  [1:0] packet;          // 0=Beginner 1=Intermediate 2=Advanced 3=Expert
    reg        pick_mode;       // 0 = random cards, 1 = player picks
    reg  [5:0] seed;            // card side bitmask == GAME NUMBER 0..63
    reg  [5:0] card_known;      // which of A..F have been resolved

    // Free-running LFSR, sampled on the player's keypress: the exact clock they
    // press on is the entropy, which is the only real source a core like this has.
    reg [15:0] lfsr;
    always @(posedge clk_sys) begin
        if (!reset) lfsr <= 16'hACE1;
        else        lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
    end

    always @(posedge clk_sys) begin
        if (!reset) begin
            phase <= G_SKILL;  packet <= 2'd0;  pick_mode <= 1'b0;
            seed  <= 6'd0;     card_known <= 6'd0;
        end else if (do_restart) begin
            phase <= G_SKILL;  packet <= 2'd0;  pick_mode <= 1'b0;
            seed  <= 6'd0;     card_known <= 6'd0;
        end else case (phase)
            G_SKILL: begin
                if (btn_left  & ~left_q)  packet <= packet - 2'd1;
                if (btn_right & ~right_q) packet <= packet + 2'd1;
                if (a_edge) phase <= G_CARDMODE;
            end
            G_CARDMODE: begin
                if (move_edge) pick_mode <= ~pick_mode;
                if (b_edge)    phase <= G_SKILL;          // back
                if (a_edge) begin
                    phase <= G_PLAY;
                    // Random: draw all six now, so nothing ever blocks a seek.
                    // Player-picks: nothing known yet; each card resolves when its
                    // Clue Card segment is reached.
                    if (!pick_mode) begin
                        seed       <= lfsr[5:0];
                        card_known <= 6'b111111;
                    end
                end
            end
            default: begin
                // Player-picks: a card resolves the moment its segment is entered.
                // (Which SIDE is a UI choice; until that screen exists, take the
                // LFSR bit so the transport is exercisable end to end.)
                if (pick_mode & card_show & ~card_known[card_id]) begin
                    card_known[card_id] <= 1'b1;
                    seed[card_id]       <= lfsr[0];
                end
            end
        endcase
    end

    //------------------------------------------------------------------------
    // SOLUTION ROM -- all 256 outcomes in 16 rules (vault, triple-verified).
    // seed[5:4] picks the quadrant; ONE remaining bit decides; the rest are red
    // herrings. Page letters encode A=0..Z=25, AA=26..FF=31.
    //------------------------------------------------------------------------
    localparam [4:0] P_A=0,P_B=1,P_C=2,P_D=3,P_E=4,P_F=5,P_G=6,P_H=7,P_I=8,P_J=9,
                     P_K=10,P_L=11,P_M=12,P_N=13,P_O=14,P_P=15,P_Q=16,P_R=17,
                     P_S=18,P_T=19,P_U=20,P_V=21,P_W=22,P_X=23,P_Y=24,P_Z=25,
                     P_AA=26,P_BB=27,P_CC=28,P_DD=29,P_EE=30,P_FF=31;

    function [2:0] sel_bit(input [1:0] pk, input [1:0] q);
        case ({pk,q})
            4'b00_00: sel_bit=3'd0;  4'b00_01: sel_bit=3'd1;
            4'b00_10: sel_bit=3'd3;  4'b00_11: sel_bit=3'd2;   // Beginner
            4'b01_00: sel_bit=3'd0;  4'b01_01: sel_bit=3'd1;
            4'b01_10: sel_bit=3'd0;  4'b01_11: sel_bit=3'd1;   // Intermediate
            4'b10_00: sel_bit=3'd3;  4'b10_01: sel_bit=3'd2;
            4'b10_10: sel_bit=3'd3;  4'b10_11: sel_bit=3'd2;   // Advanced
            default:  sel_bit=(q==2'b00)?3'd0:(q==2'b01)?3'd1:(q==2'b10)?3'd3:3'd2;
        endcase
    endfunction

    function [4:0] page_of(input [1:0] pk, input [1:0] q, input b);
        case ({pk,q})
            4'b00_00: page_of = b?P_CC:P_K;   4'b00_01: page_of = b?P_P :P_Y;
            4'b00_10: page_of = b?P_T :P_G;   4'b00_11: page_of = b?P_EE:P_C;
            4'b01_00: page_of = b?P_N :P_E;   4'b01_01: page_of = b?P_AA:P_FF;
            4'b01_10: page_of = b?P_W :P_I;   4'b01_11: page_of = b?P_R :P_A;
            4'b10_00: page_of = b?P_V :P_D;   4'b10_01: page_of = b?P_DD:P_H;
            4'b10_10: page_of = b?P_M :P_Z;   4'b10_11: page_of = b?P_F :P_O;
            4'b11_00: page_of = b?P_Q :P_J;   4'b11_01: page_of = b?P_X :P_L;
            4'b11_10: page_of = b?P_S :P_B;   default:  page_of = b?P_U :P_BB;
        endcase
    endfunction

    wire [1:0] quad     = seed[5:4];
    wire [2:0] sbit     = sel_bit(packet, quad);
    wire       decider  = seed[sbit];
    wire [4:0] page_idx = page_of(packet, quad, decider);

    //------------------------------------------------------------------------
    // SEEK LOCK: you may not jump PAST a clue you have not got yet.
    // Clue Card segments are 8,10,12,14,16,18 -> cards 0..5. The first one whose
    // card is still unknown is a hard ceiling on any forward seek. In random mode
    // every card is known at boot, so this never binds.
    //------------------------------------------------------------------------
    function [5:0] seek_ceiling(input [5:0] known);
        seek_ceiling = !known[0] ? 6'd8  : !known[1] ? 6'd10 : !known[2] ? 6'd12 :
                       !known[3] ? 6'd14 : !known[4] ? 6'd16 : !known[5] ? 6'd18 :
                                                                          6'd63;
    endfunction
    wire [5:0] seek_cap = seek_ceiling(card_known);

    //------------------------------------------------------------------------
    // SEGMENT INDEX + SEEK  (2026-08-15)  L = prior index, R = next index.
    //
    // Table is the REAL index now (_VCR/Robots.idx, 2026-08-15), replacing the
    // evenly-spaced placeholder. Verified against the .dlv before use: the 22
    // video segments are contiguous 0..81064 with no gaps or overlaps and total
    // exactly 81,065 frames = the packed frame count.
    //
    // ⚠️ These are the 22 segments that HAVE TAPE FRAMES. The 8 INSERT rows in
    // Robots.idx (Difficulty, Show Card A-F, Solve Case) are core-rendered screens
    // with no frames, so they are not seek targets and are not modelled here yet.
    // ⚠️ DISPOSITION IS NOT ENFORCED YET -- Never Play / Skippable currently play
    // like anything else. Seek only. That is the next piece of work.
    //
    // Seeking is the ONLY thing that exercises ld_search_cmd_o -> seek_flush and
    // the streamer's audio re-point. That path has never run on this core, and it
    // is the same mechanism that keeps DL's audio anchored, so it is worth having
    // for diagnosis alone.
    //
    // Behaviour is CD-player semantics: "prior" restarts the CURRENT segment if we
    // are more than PREV_THRESH into it, otherwise it steps back a segment.
    //------------------------------------------------------------------------
    localparam [5:0]  N_INDEX     = 6'd22;
    localparam [16:0] PREV_THRESH = 17'd60;   // 2 s at 29.97 fps
    localparam [5:0]  BOOT_IDX    = 6'd1;     // Kodak Intro: frame 0-91 is leader

    // Disposition, per the user's 2026-08-15 decisions on Robots.idx:
    //   D_SKIP  jump straight over it. Both Blank Spaces (pure leader) and the
    //           Clue Packet (we pick difficulty up front, so its 28 s prompt is
    //           dead air). A jump, so it DOES flush the audio ring -- correct,
    //           the buffered audio belongs to the old position.
    //   D_PLAY  play normally.
    //   D_SKPBL play normally, but L/R may leave early. "Skippable" needs no
    //           mechanism of its own: R already jumps to the next segment.
    //   D_CARD  Clue Card A-F. DO NOT jump. The tape keeps rolling so the on-tape
    //           audio continues, while the video window is replaced by the
    //           full-screen card. At segment end the card pops to the thumbnail
    //           strip and the next segment's video resumes.
    localparam [1:0] D_SKIP = 2'd0, D_PLAY = 2'd1, D_SKPBL = 2'd2, D_CARD = 2'd3;

    function [1:0] index_disp(input [5:0] i);
        case (i)
            6'd0:  index_disp = D_SKIP;    // Blank Space
            6'd1:  index_disp = D_SKPBL;   // Kodak Intro
            6'd2:  index_disp = D_PLAY;    // Crime Notice
            6'd3:  index_disp = D_PLAY;    // Game Intro
            6'd4:  index_disp = D_PLAY;    // Newscast 1
            6'd5:  index_disp = D_PLAY;    // Game Part 1
            6'd6:  index_disp = D_SKIP;    // Clue Packet
            6'd7:  index_disp = D_PLAY;    // Game Part 2
            6'd8:  index_disp = D_CARD;    // Clue Card A
            6'd9:  index_disp = D_PLAY;    // Game Part 3
            6'd10: index_disp = D_CARD;    // Clue Card B
            6'd11: index_disp = D_PLAY;    // Game Part 4
            6'd12: index_disp = D_CARD;    // Clue Card C
            6'd13: index_disp = D_PLAY;    // Game Part 5
            6'd14: index_disp = D_CARD;    // Clue Card D
            6'd15: index_disp = D_PLAY;    // Game Part 6
            6'd16: index_disp = D_CARD;    // Clue Card E
            6'd17: index_disp = D_PLAY;    // Game Part 7
            6'd18: index_disp = D_CARD;    // Clue Card F
            6'd19: index_disp = D_PLAY;    // Game Part 8
            6'd20: index_disp = D_SKPBL;   // Cast Credits
            6'd21: index_disp = D_SKIP;    // Blank Space (end of tape)
            default: index_disp = D_SKIP;
        endcase
    endfunction

    function playable(input [5:0] i);
        playable = (index_disp(i) == D_PLAY) || (index_disp(i) == D_SKPBL);
    endfunction

    //  #   name           disposition    frames
    function [16:0] index_frame(input [5:0] i);
        case (i)
            6'd0:  index_frame = 17'd0;      //  0 Blank Space   Never Play       0-   91
            6'd1:  index_frame = 17'd92;     //  1 Kodak Intro   Skippable       92-  761
            6'd2:  index_frame = 17'd762;    //  2 Crime Notice  Always Play    762- 1099
            6'd3:  index_frame = 17'd1100;   //  3 Game Intro    Always Play   1100- 4032
            6'd4:  index_frame = 17'd4033;   //  4 Newscast 1    Always Play   4033- 6364
            6'd5:  index_frame = 17'd6365;   //  5 Game Part 1   Always Play   6365-12600
            6'd6:  index_frame = 17'd12601;  //  6 Clue Packet   Never Play   12601-13444
            6'd7:  index_frame = 17'd13445;  //  7 Game Part 2   Always Play  13445-38073
            6'd8:  index_frame = 17'd38074;  //  8 Clue Card A   Never Play   38074-38448
            6'd9:  index_frame = 17'd38449;  //  9 Game Part 3   Always Play  38449-49080
            6'd10: index_frame = 17'd49081;  // 10 Clue Card B   Never Play   49081-49411
            6'd11: index_frame = 17'd49412;  // 11 Game Part 4   Always Play  49412-55005
            6'd12: index_frame = 17'd55006;  // 12 Clue Card C   Never Play   55006-55335
            6'd13: index_frame = 17'd55336;  // 13 Game Part 5   Always Play  55336-61358
            6'd14: index_frame = 17'd61359;  // 14 Clue Card D   Never Play   61359-61750
            6'd15: index_frame = 17'd61751;  // 15 Game Part 6   Always Play  61751-66545
            6'd16: index_frame = 17'd66546;  // 16 Clue Card E   Never Play   66546-66890
            6'd17: index_frame = 17'd66891;  // 17 Game Part 7   Always Play  66891-74192
            6'd18: index_frame = 17'd74193;  // 18 Clue Card F   Never Play   74193-74520
            6'd19: index_frame = 17'd74521;  // 19 Game Part 8   Always Play  74521-76069
            6'd20: index_frame = 17'd76070;  // 20 Cast Credits  Skippable    76070-80860
            6'd21: index_frame = 17'd80861;  // 21 Blank Space   Never Play   80861-81064
            default: index_frame = 17'd0;
        endcase
    endfunction

    reg  [5:0] idx;                                   // current segment

    // L/R visit PLAYABLE segments only, stepping over blanks and clue cards.
    // Two hops is enough because no two non-playable segments are adjacent in
    // Robots.idx. If a future index breaks that, seek degrades gracefully rather
    // than misbehaving: landing on a D_SKIP still auto-skips forward below.
    wire [5:0] nx1 = (idx + 6'd1 >= N_INDEX) ? idx : (idx + 6'd1);
    wire [5:0] nx2 = (nx1 + 6'd1 >= N_INDEX) ? nx1 : (nx1 + 6'd1);
    wire [5:0] idx_next = playable(nx1) ? nx1 : nx2;

    wire [5:0] pv1 = (idx <= BOOT_IDX) ? BOOT_IDX : (idx - 6'd1);
    wire [5:0] pv2 = (pv1 <= BOOT_IDX) ? BOOT_IDX : (pv1 - 6'd1);
    wire [5:0] idx_prev = playable(pv1) ? pv1 : pv2;

    // "prior" = restart this segment when we are well into it, else step back.
    wire       deep_in  = (frame_ctr > index_frame(idx) + PREV_THRESH);
    wire [5:0] seek_want = seekn_edge ? idx_next : (deep_in ? idx : idx_prev);
    // Never let a forward seek land beyond an unresolved clue.
    wire [5:0] seek_idx  = (seek_want > seek_cap) ? seek_cap : seek_want;

    wire       do_seek  = (seekp_edge | seekn_edge) & ~ui_modal;

    //---- automatic disposition handling ------------------------------------
    wire [1:0] disp_now  = index_disp(idx);
    wire       at_tail   = (idx + 6'd1 >= N_INDEX);
    // Jump over a D_SKIP segment. Self-clearing: the load moves idx past it.
    wire       auto_skip = (disp_now == D_SKIP) & ~at_tail;
    // The final Blank Space is the end of the tape, not something to skip INTO.
    wire       at_eot    = (disp_now == D_SKIP) &  at_tail;

    // Clue card showing: tape keeps rolling underneath (audio continues), the
    // video window is replaced by the full-screen card. Card 0..5 = A..F, from
    // segments 8,10,12,14,16,18.
    wire       card_show = (disp_now == D_CARD);
    wire [2:0] card_id   = (idx >= 6'd8) ? (idx[3:1] - 3'd4) : 3'd0;

    // Frame LOAD path -- a discontinuous jump, as opposed to frame_adv's +1.
    // Three users: a confirmed restart, an index seek, and an automatic skip.
    // NOT the clue cards -- those deliberately roll through so the audio survives.
    wire        frame_load     = do_restart | do_seek | auto_skip;
    wire [16:0] frame_load_val = do_restart ? index_frame(BOOT_IDX)
                               : do_seek    ? index_frame(seek_idx)
                                            : index_frame(idx + 6'd1);

    always @(posedge clk_sys) begin
        if (!reset) begin
            playing   <= 1'b0;              // start PAUSED: pressing Start is the
            frame_ctr <= index_frame(BOOT_IDX); // first thing that does anything.
            film_div  <= 32'd0;             // Frame 92, not 0 -- 0-91 is leader.
            idx       <= BOOT_IDX;
            cards     <= 6'd0;
        end else begin
            // free-running film cadence
            film_div <= film_tick ? 32'd0 : (film_div + 32'd1);

            // Start is a MANUAL pause and stays available at all times -- except
            // while a modal owns the tape, where obeying it would leave the two
            // disagreeing about who is holding playback.
            if (~ui_modal & start_edge) playing <= ~playing;

            // Confirmed restart lands in exactly the cold-boot state.
            if (do_restart) playing <= 1'b0;
            // Cancelled: put back the transport state the dialog interrupted.
            else if (do_cancel) playing <= resume_after;
            // Reaching the tail Blank Space IS the end of the tape. Stop there
            // rather than skipping into it -- there is nothing after it.
            if (at_eot) playing <= 1'b0;

            if (frame_load)
                frame_ctr <= frame_load_val;
            else if (frame_adv)
                frame_ctr <= at_end ? (HOLD_AT_END ? frame_ctr : 17'd0)
                                    : (frame_ctr + 17'd1);

            // Track which segment we are in. A seek or an auto-skip sets it
            // outright; plain playback advances it as the tape crosses the next
            // boundary, so next/prior stay meaningful after free-running past one.
            if (do_restart)
                idx <= BOOT_IDX;
            else if (do_seek)
                idx <= seek_idx;
            else if (auto_skip)
                idx <= idx + 6'd1;
            else if (frame_adv && (idx + 6'd1 < N_INDEX)
                               && (frame_ctr + 17'd1 >= index_frame(idx + 6'd1)))
                idx <= idx + 6'd1;

            // Sticky reveal mask for the thumbnail strip: a card counts as
            // revealed the moment its segment is entered, so the renderer can
            // draw it full-screen while card_show is high and as a thumbnail
            // afterwards, off one piece of state.
            if (do_restart) cards <= 6'd0;
            else if (card_show) cards[card_id] <= 1'b1;
        end
    end

    assign ld_frame_o   = frame_ctr;

    // Audio drain gate. Dropping this on pause silences the ring AND holds its
    // read pointer (dlv_streamer.v:375 aud_muted), which is exactly the
    // freeze-in-place behaviour we want.
    assign ld_playing_o = playing & ~pause & ~disc_hold & ~ui_modal;

    assign ui_modal_o       = ui_modal;
    assign ui_confirm_sel_o = confirm_sel;

    assign card_show_o      = card_show;
    assign card_id_o        = card_id;
    assign cards_revealed_o = cards;

    // A JUMP is the one case where flushing the audio ring IS correct: the ring
    // holds buffered audio for the old position, which must be discarded rather
    // than played over the new one. So this pulses on frame_load (restart today,
    // segment jumps once the index lands) and stays low for play/pause, where the
    // buffered audio is still exactly the audio we want on resume.
    // One cycle wide, matching dlv_streamer.v's seek_flush contract; the top
    // level's fb_seek_edge arms the seek-hold FSM off the same pulse, so video
    // freezes and audio refills, then both release together.
    // BOOT-ALIGN-2026-08-15: also pulse on the FIRST transition into play.
    // The streamer only clears the audio ring and holds both streams on seek_flush
    // (dlv_streamer.v:341,495,742). Nothing fires it at power-up, so a SEEK got a
    // clean clear + refill + release-together while STARTUP got no alignment at all
    // -- audio and video simply began whenever each was ready. That is why sync was
    // wrong "from the get-go" rather than drifting into it. Reuse the proven seek
    // alignment path for boot instead of inventing a second one.
    // Only the FIRST play: a flush costs a full re-prime (SEEK_FILL 12288 = 557 ms
    // at 22.05 kHz) and holds video with it, which is fine hidden behind the initial
    // Start press but would stall every pause/resume.
    reg search_pulse, playing_q, aligned_once;
    wire play_rise  = playing & ~playing_q;
    wire boot_align = play_rise & ~aligned_once;

    always @(posedge clk_sys) begin
        if (!reset) begin
            search_pulse <= 1'b0;  playing_q <= 1'b0;  aligned_once <= 1'b0;
        end else begin
            playing_q    <= playing;
            search_pulse <= frame_load | boot_align;
            if (boot_align) aligned_once <= 1'b1;
            if (do_restart) aligned_once <= 1'b0;   // restart re-arms boot alignment
        end
    end
    assign ld_search_cmd_o = search_pulse;

    //------------------------------------------------------------------------
    // On-screen debug readout via led_band.
    //
    // Slot map traced in led_band.v:72-84 -- digit i = led_digits[i*4 +: 4], and
    // digits 0..5 land on ADJACENT character slots 3..8 with digit 0 leftmost,
    // so a 6-digit frame counter reads correctly left-to-right. Digit 14 sits in
    // the "credits" slot, well clear of the counter.
    //
    // BCD is kept as its own ripple counter rather than converting frame_ctr,
    // which would cost a 17->6 double-dabble every frame for a debug display.
    // It cannot drift from frame_ctr: both share reset, load and enable.
    //------------------------------------------------------------------------
    // BINARY -> BCD, replacing the ripple counter 2026-08-15.
    //
    // The ripple counter could only ever track +1 steps from zero, so the instant
    // a SEEK loads an arbitrary frame the readout would have LIED. The LED band is
    // currently doing duty as a measuring instrument, so a lying readout is worse
    // than no readout.
    //
    // Free-running shift-add-3 (double dabble), 19 clocks a pass, so the digits
    // are never more than ~0.5 us stale at 40 MHz. It re-derives from frame_ctr
    // every pass instead of accumulating, so it cannot drift out of step with it.
    reg  [16:0] dd_bin;
    reg  [23:0] dd_bcd;
    reg  [23:0] bcd_q;                  // last completed conversion -> display
    reg   [4:0] dd_cnt;

    function [23:0] dd_adj(input [23:0] b);
        integer k;
        begin
            dd_adj = b;
            for (k = 0; k < 6; k = k + 1)
                if (dd_adj[k*4 +: 4] >= 4'd5)
                    dd_adj[k*4 +: 4] = dd_adj[k*4 +: 4] + 4'd3;
        end
    endfunction

    // Named intermediate deliberately: (expr)[msb:lsb] applied to a function call
    // is an expression bit-select, which Quartus 17.0 throws error 10170 on.
    wire [23:0] dd_adj_w = dd_adj(dd_bcd);

    always @(posedge clk_sys) begin
        if (!reset) begin
            dd_cnt <= 5'd0;  dd_bin <= 17'd0;  dd_bcd <= 24'd0;  bcd_q <= 24'd0;
        end else if (dd_cnt == 5'd0) begin
            dd_bin <= frame_ctr;        // resample: always the live value
            dd_bcd <= 24'd0;
            dd_cnt <= 5'd1;
        end else if (dd_cnt <= 5'd17) begin
            dd_bcd <= {dd_adj_w[22:0], dd_bin[16]};
            dd_bin <= {dd_bin[15:0], 1'b0};
            dd_cnt <= dd_cnt + 5'd1;
        end else begin
            bcd_q  <= dd_bcd;
            dd_cnt <= 5'd0;
        end
    end

    // Digit 15 = modal state, so the dialog is testable BEFORE the overlay
    // renderer exists: 0 = no modal, 1 = Restart? with "No" selected, 2 = with
    // "Yes" selected. Pressing Select should show 1, left/right should flip it
    // 1<->2, B should return it to 0.
    // M digit = {modal, pick_mode, phase}:  0 skill · 1 cardmode · 2 play
    //   6 = play + player-picks · 8+ = a modal is up (9=No, A=Yes on restart)
    wire [3:0] dbg_ui = ui_modal ? {2'b10, confirm_sel, 1'b0} : {1'b0, pick_mode, phase};

    // Digits 6,7 = current segment index in DECIMAL. The real index has 22
    // segments, so one hex digit can no longer hold it -- and decimal matches how
    // Robots.idx numbers them, which is what anyone cross-checking will have open.
    wire [5:0] idx_t10  = (idx >= 6'd20) ? 6'd20 : (idx >= 6'd10) ? 6'd10 : 6'd0;
    wire [3:0] idx_tens = (idx >= 6'd20) ? 4'd2  : (idx >= 6'd10) ? 4'd1  : 4'd0;
    wire [5:0] idx_ones = idx - idx_t10;

    // Digits 13..8 read 0 here but are OVERRIDDEN in VCR-Robots.sv by the
    // DIAG-REVERT-2026-08-15 A/V-sync counters; do not put anything there.
    // Digits 5..0 are the frame counter, MOST significant digit leftmost, so the
    // nibbles come out of bcd_q reversed (bcd_q[3:0] is units = digit 5).
    assign led_digits_o = { dbg_ui, {3'd0, playing},              // 15, 14
                            seed[3:0], {2'd0, seed[5:4]}, {2'd0, packet},  // 13,12,11
                            4'd0, 4'd0, 4'd0,                              // 10..8 (overridden)
                            idx_ones[3:0], idx_tens,              // 7 = ones, 6 = tens
                            bcd_q[3:0],   bcd_q[7:4],   bcd_q[11:8],   // 5, 4, 3
                            bcd_q[15:12], bcd_q[19:16], bcd_q[23:20] };// 2, 1, 0

    // ~0.6 Hz "core alive" heartbeat: 40 MHz / 2^26 = 0.596 Hz.
    // ~0.6 Hz whatever the clock: divide by CLK_HZ/2 rather than a fixed bit.
    reg [31:0] hb;
    always @(posedge clk_sys) hb <= (hb >= (CLK_HZ>>1)) ? 32'd0 : hb + 32'd1;
    reg  hb_t;
    always @(posedge clk_sys) if (hb >= (CLK_HZ>>1)) hb_t <= ~hb_t;
    assign dbg_led = hb_t;

endmodule
