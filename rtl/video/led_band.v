//============================================================================
// led_band.v — VCR-Robots status band at framebuffer (x,y) coords
//----------------------------------------------------------------------------
// Originally Dragon's Lair's arcade scoreboard, ported from the raster renderer
// in DragonsLair_CPU.sv.  Given the current pixel (hc,vc) + the 16 LED digits,
// outputs seg_lit = this pixel is a lit segment of the band.  Caller paints it.
//
// Layout: 33 char-slots x 6px pitch, 5x7 glyphs, band rows BAND_Y0..+7.
// X_START recentred for 320: (320 - 33*6)/2 = 61.
//
// ROBOTS-2026-08-15 — RELABELLED.  The band used to read
//     "P1 <score> L <lives>   P2 <score> L <lives>   CR <credits>"
// which is meaningless here: Robots keeps no score, no lives and no credits, so
// every label described something the digits underneath were not.  It now reads
//
//     F012345 S07 L7A3 C00F P1 M0
//
// Digit map (led_digits[i*4 +: 4]):
//   0-5   frame number, decimal, MSD first      -> "F"
//   6-7   current segment index, DECIMAL 00-21   -> "S"
//   8-10  DIAG live audio ring level, hex       -> "L"   ] DIAG-REVERT-2026-08-15
//   11-13 DIAG credit-blocks per second, hex    -> "C"   ] remove with the A/V work
//   14    1 = tape rolling, 0 = paused          -> "P"
//   15    modal: 0 none / 1 Restart?No / 2 Yes  -> "M"
//
// Font holds 0-9 A-F plus P L R S M.  Code 31 is blank; code 15 is a real 'F'.
//============================================================================
module led_band #(
    // RES-512x480-FIX-2026-07-24: X_START must be recentred for the new width, and the glyphs
    // magnified or they render half-size on a 480-row image.
    //   SCALE_LOG2=0 (1x): X_START = (W - N_SLOT*PITCH)/2      -> 320: 61
    //   SCALE_LOG2=1 (2x): X_START = (W - N_SLOT*PITCH*2)/2    -> 512: 58
    // The band must be tall enough for the magnified glyph: BAND_H >= BAND_Y0 + FH*2^SCALE_LOG2.
    // ORIGINAL: parameter [15:0] X_START = 16'd61;  (no SCALE_LOG2)
    parameter [15:0] X_START = 16'd61,   // (320 - N_SLOT*PITCH)/2, centred
    parameter [1:0]  SCALE_LOG2 = 2'd0,  // glyph magnification = 2^SCALE_LOG2
    parameter [15:0] BAND_Y0 = 16'd2
)(
    input      [15:0] hc,
    input      [15:0] vc,
    input      [63:0] led_digits,        // 16 x 4-bit, digit i = [i*4 +: 4]
    output            seg_lit
);
    localparam FH = 7, PITCH = 6, N_SLOT = 33;

    // 5x7 font, packed 35 bits/glyph: row0(top)=[34:30] .. row6=[4:0], bit4=left.
    function [34:0] glyph(input [4:0] ch);
        case (ch)
            5'd0:  glyph = 35'b01110_10001_10011_10101_11001_10001_01110; // 0
            5'd1:  glyph = 35'b00100_01100_00100_00100_00100_00100_01110; // 1
            5'd2:  glyph = 35'b01110_10001_00001_00010_00100_01000_11111; // 2
            5'd3:  glyph = 35'b11111_00010_00100_00010_00001_10001_01110; // 3
            5'd4:  glyph = 35'b00010_00110_01010_10010_11111_00010_00010; // 4
            5'd5:  glyph = 35'b11111_10000_11110_00001_00001_10001_01110; // 5
            5'd6:  glyph = 35'b00110_01000_10000_11110_10001_10001_01110; // 6
            5'd7:  glyph = 35'b11111_00001_00010_00100_01000_01000_01000; // 7
            5'd8:  glyph = 35'b01110_10001_10001_01110_10001_10001_01110; // 8
            5'd9:  glyph = 35'b01110_10001_10001_01111_00001_00010_01100; // 9
            5'd10: glyph = 35'b01110_10001_10001_11111_10001_10001_10001; // A
            5'd11: glyph = 35'b11110_10001_10001_11110_10001_10001_11110; // B
            5'd12: glyph = 35'b01110_10001_10000_10000_10000_10001_01110; // C
            5'd13: glyph = 35'b11110_10001_10001_10001_10001_10001_11110; // D
            5'd14: glyph = 35'b11111_10000_10000_11110_10000_10000_11111; // E
            // ROBOTS-2026-08-15: code 15 used to fall through to the blank default,
            // so a value of F rendered as nothing. The segment index reaches F, and
            // hex readouts are used for diagnostics, so give it a real glyph.
            5'd15: glyph = 35'b11111_10000_10000_11110_10000_10000_10000; // F
            5'd16: glyph = 35'b11110_10001_10001_11110_10000_10000_10000; // P
            5'd17: glyph = 35'b10000_10000_10000_10000_10000_10000_11111; // L
            5'd18: glyph = 35'b11110_10001_10001_11110_10100_10010_10001; // R
            5'd19: glyph = 35'b01111_10000_10000_01110_00001_00001_11110; // S  (ROBOTS-2026-08-15)
            5'd20: glyph = 35'b10001_11011_10101_10101_10001_10001_10001; // M  (ROBOTS-2026-08-15)
            5'd21: glyph = 35'b01110_10001_10000_10011_10001_10001_01110; // G  (ROBOTS-2026-08-15)
            // ROBOTS-2026-08-15: BLANK IS NOW CODE 31, NOT 15. Code 15 became a real
            // 'F' glyph above, and the slot decoder used to emit 15 for empty slots --
            // which would paint an F into every gap. Empty slots emit 31 now.
            default: glyph = 35'd0;                                       // 31 = blank
        endcase
    endfunction

    // RES-512x480-FIX-2026-07-24: >> SCALE_LOG2 magnifies by replicating source pixels; the
    // in_band extents grow by the same factor. SCALE_LOG2=0 reproduces the original exactly.
    wire [15:0] hoff = hc - X_START;
    wire [15:0] voff = vc - BAND_Y0;
    wire [15:0] bx   = hoff >> SCALE_LOG2;
    wire [5:0]  slot = bx / PITCH;                // 0..32
    wire [2:0]  fx   = bx - slot*PITCH;           // 0..5 (5 = inter-char gap)
    wire [2:0]  fy   = voff >> SCALE_LOG2;        // 0..6 within the glyph
    wire in_band = (hc >= X_START) && (hc < X_START + ((N_SLOT*PITCH) << SCALE_LOG2)) &&
                   (vc >= BAND_Y0) && (vc < BAND_Y0 + (FH << SCALE_LOG2));

    // ROBOTS-2026-08-15: slot map REWRITTEN for Robots. The old one was Dragon's
    // Lair's arcade scoreboard -- "P1 <score> L <lives>  P2 <score> L <lives>  CR
    // <credits>". Robots keeps no score, no lives and no credits, so every one of
    // those labels was a lie about what the digits underneath meant.
    //
    // Reads:   F012345 S07 L7A3 C00F P1 M0
    //
    //   F <6>  frame number, decimal, most significant digit first
    //   S <2>  current segment index, DECIMAL 00-21, numbered as in Robots.idx
    //   L <3>  ] DIAG-REVERT-2026-08-15: A/V-sync. L = LIVE ring level (high =>
    //   C <3>  ] credit-limited, low => bandwidth-limited). C = credit-blocks/sec.
    //          ] Both hex. Remove these two groups (slots 12-20)
    //          ] when the sync work is done -- digits 8-13 are theirs alone.
    //   P <1>  1 = tape rolling, 0 = paused
    //   M <1>  modal: 0 none, 1 "Restart? No", 2 "Restart? Yes"
    //
    // Labels are limited to glyphs this font has: 0-9 A-F P L R S M.
    reg [4:0] ch;
    always @* case (slot)
        6'd0:  ch = 5'd15;                                                        // 'F'
        6'd1:  ch = {1'b0, led_digits[ 0*4 +: 4]};   6'd2:  ch = {1'b0, led_digits[ 1*4 +: 4]};
        6'd3:  ch = {1'b0, led_digits[ 2*4 +: 4]};   6'd4:  ch = {1'b0, led_digits[ 3*4 +: 4]};
        6'd5:  ch = {1'b0, led_digits[ 4*4 +: 4]};   6'd6:  ch = {1'b0, led_digits[ 5*4 +: 4]};
        6'd8:  ch = 5'd19;                                                        // 'S'
        6'd9:  ch = {1'b0, led_digits[ 6*4 +: 4]};   6'd10: ch = {1'b0, led_digits[ 7*4 +: 4]};
        6'd12: ch = 5'd17;                                                        // 'L'  (DIAG: ring level)
        6'd13: ch = {1'b0, led_digits[ 8*4 +: 4]};   6'd14: ch = {1'b0, led_digits[ 9*4 +: 4]};
        6'd15: ch = {1'b0, led_digits[10*4 +: 4]};
        6'd17: ch = 5'd21;                                                        // 'G' game: packet + seed
        6'd18: ch = {1'b0, led_digits[11*4 +: 4]};   6'd19: ch = {1'b0, led_digits[12*4 +: 4]};
        6'd20: ch = {1'b0, led_digits[13*4 +: 4]};
        6'd22: ch = 5'd16;                                                        // 'P'
        6'd23: ch = {1'b0, led_digits[14*4 +: 4]};
        6'd25: ch = 5'd20;                                                        // 'M'
        6'd26: ch = {1'b0, led_digits[15*4 +: 4]};
        default: ch = 5'd31;                                                      // blank (NOT 15)
    endcase

    wire [34:0] gbits = glyph(ch);
    reg  [4:0]  rowbits;
    always @* case (fy)
        3'd0: rowbits = gbits[34:30];  3'd1: rowbits = gbits[29:25];
        3'd2: rowbits = gbits[24:20];  3'd3: rowbits = gbits[19:15];
        3'd4: rowbits = gbits[14:10];  3'd5: rowbits = gbits[9:5];
        3'd6: rowbits = gbits[4:0];    default: rowbits = 5'd0;
    endcase

    wire pix = (fx < 3'd5) & rowbits[4 - fx];
    assign seg_lit = in_band & pix;
endmodule
