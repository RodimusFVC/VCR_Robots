//============================================================================
//
// Dragon's Lair / Space Ace (US set) for MiSTer
// Copyright (C) 2026 Rodimus
// Based on MAME dlair.cpp; converted in place from the Kangaroo core copy
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

// STRIP-2026-08-15: ALL audio is now the .dlv tape audio.  Dragon's Lair mixed the
// AY-3-8910 (audio_l/r, from DragonsLair_CPU) with the .dlv PCM; Robots has no sound
// chip, so audio_l/r would be a constant 0 and the mux + saturation collapse to a
// straight pass-through of pcm_l/pcm_r.  Removing them rather than tying them to 0
// keeps a 17-bit adder and two comparators out of the fabric for no behaviour change.
//
// ORIGINAL (restore verbatim if a synthesised sound source is ever added):
// wire signed [15:0] audio_l, audio_r;
// wire signed [16:0] mix_l = audio_l + pcm_l;
// wire signed [16:0] mix_r = audio_r + pcm_r;
// wire signed [15:0] sat_l = (mix_l >  17'sd32767) ?  16'sd32767 :
//                            (mix_l < -17'sd32768) ? -16'sd32768 : mix_l[15:0];
// wire signed [15:0] sat_r = (mix_r >  17'sd32767) ?  16'sd32767 :
//                            (mix_r < -17'sd32768) ? -16'sd32768 : mix_r[15:0];
// assign AUDIO_L = pause_cpu ? 16'd0 : sat_l;
// assign AUDIO_R = pause_cpu ? 16'd0 : sat_r;
assign AUDIO_L = pause_cpu ? 16'd0 : pcm_l;   // pcm_* driven by dlv_strm, declared near the streamer
assign AUDIO_R = pause_cpu ? 16'd0 : pcm_r;
assign AUDIO_S = 1;   // signed
assign AUDIO_MIX = 0; // no mix, true stereo

assign LED_DISK  = 0;
assign LED_POWER = 0;
wire dbg_led;
assign LED_USER  = dbg_led;  // ~0.6 Hz "core alive" heartbeat from rtl/Robots.sv
assign BUTTONS = 0;

///////////////////////////////////////////////////

wire [1:0] ar = status[14:13];

// ROT0-FIX-2026-07-03: Dragon's Lair / Space Ace are HORIZONTAL-only.  This core was
// inherited from Kangaroo (vertical, ROT90) and defaulted to Vert (status[12]=0), which
// rotated the raster onto the right edge and used a portrait 3:4 aspect.  Force horizontal
// orientation + 4:3 aspect everywhere status[12] was used, and drop the (now inert)
// Orientation toggle from the OSD.  (Was: status[12] selected Vert/Horz.)
wire horz = 1'b1;

// LAYOUT-2026-07-04 (Option B): active frame is 320 x (240 video + 12 band) = 320x252.  "Original"
// AR is set to 320:252 (NOT 4:3) so pixels stay SQUARE and the 320x240 video sub-region renders
// exact 4:3 — the LED band is proportional overscan above it, video undistorted / uncropped.
// (This AR is HDMI/scaler-only; a real CRT ignores it.  If BAND_H changes, make this 240+BAND_H.)
// RES-512x480-2026-07-24: 512x480 is ANAMORPHIC (non-square NTSC pixels), unlike 320x240 which was
// already exact 4:3. So "Original" can no longer be the raw pixel count -- it must be the DISPLAY
// ratio. The 480 video rows want 4:3, and BAND_H=12 rows are added on top, so:
//     ARX:ARY = 4 : 3*(480+12)/480  ->  640 : 492
// (the old 320:252 was the same construction for a 240-row 4:3 image plus the same 12-row band).
// ORIGINAL:
// assign VIDEO_ARX = horz ? ((!ar) ? 12'd320 : (ar - 1'd1)) : ((!ar) ? 12'd3 : (ar - 1'd1));
// assign VIDEO_ARY = horz ? ((!ar) ? 12'd252 : 12'd0) : ((!ar) ? 12'd4 : 12'd0);
// ORIGINAL (512x480 video + band): ARX 640 / ARY 500
// assign VIDEO_ARX = horz ? ((!ar) ? 12'd640 : (ar - 1'd1)) : ((!ar) ? 12'd3 : (ar - 1'd1));
// assign VIDEO_ARY = horz ? ((!ar) ? 12'd500 : 12'd0) : ((!ar) ? 12'd4 : 12'd0);  // 4 : 3*(480+BAND_H)/480
// 960x540 square-pixel canvas = 16:9.
assign VIDEO_ARX = horz ? ((!ar) ? 12'd16 : (ar - 1'd1)) : ((!ar) ? 12'd3 : (ar - 1'd1));
assign VIDEO_ARY = horz ? ((!ar) ? 12'd9  : 12'd0) : ((!ar) ? 12'd4 : 12'd0);

`include "build_id.v"
localparam CONF_STR = {
	"ROBOTS;;",
	"S0,DLV,Load Tape;",   // slot 0 mounts robots.dlv (name-match auto-mount: robots.dlv)
	"ODE,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	// "OC,Orientation,Vert,Horz;",  // ROT0-FIX-2026-07-03: removed — DL/SA horizontal-only, orientation hardcoded (see horz)
	"OB,Flip Vertical,Off,On;",
	"OFH,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"P1,Pause Options;",
	"P1OP,Pause when OSD is open,On,Off;",
	"P1OQ,Dim video after 10s,On,Off;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Button1,Button2,Button3,Button4,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [31:0] status;
wire [10:0] ps2_key;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;

wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated = 1'b0;   // screen_rotate removed (ROT0) — video is never rotated

// LD-VIDEO-2026-07-04: .dlv block-mount interface (hps_io SD slot 0, VDNUM=1) -> dlv_streamer.
// The .dlv is a mounted block device (CHD-style, read on demand), NOT an ioctl_download blob.
wire        dlv_img_mounted;        // [VD:0]=1 bit, pulses on a new mount
wire [63:0] dlv_img_size;
wire [31:0] dlv_sd_lba[1];          // unpacked array (VDNUM=1)
wire  [5:0] dlv_sd_blk_cnt[1];
wire        dlv_sd_rd;
wire        dlv_sd_wr;
wire        dlv_sd_ack;
wire  [8:0] dlv_sd_buff_addr;
wire  [7:0] dlv_sd_buff_dout;
wire  [7:0] dlv_sd_buff_din[1];
wire        dlv_sd_buff_wr;
assign dlv_sd_wr          = 1'b0;   // read-only image
assign dlv_sd_buff_din[0] = 8'd0;   // never write back

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_40M),   // CLOCK-UNIFY-2026-07-04: was CLK_10M (Kangaroo leftover); core is single-clock 40M now
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key),

	// LD-VIDEO-2026-07-04: .dlv block-mount (slot 0) -> dlv_streamer (all CLK_40M, no CDC)
	.img_mounted(dlv_img_mounted),
	.img_readonly(),
	.img_size(dlv_img_size),
	.sd_lba(dlv_sd_lba),
	.sd_blk_cnt(dlv_sd_blk_cnt),
	.sd_rd(dlv_sd_rd),
	.sd_wr(dlv_sd_wr),
	.sd_ack(dlv_sd_ack),
	.sd_buff_addr(dlv_sd_buff_addr),
	.sd_buff_dout(dlv_sd_buff_dout),
	.sd_buff_din(dlv_sd_buff_din),
	.sd_buff_wr(dlv_sd_buff_wr)
);

////////////////////   CLOCKS   ///////////////////
wire CLK_40M;
wire CLK_UNUSED_10M;   // PLL outclk_1, consumed by nothing since CLOCK-UNIFY-2026-07-04
wire locked;

pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(CLK_40M),
    .outclk_1(CLK_UNUSED_10M),
    .locked(locked)
);

assign CLK_VIDEO = CLK_40M;   // HDMI needs the 40 MHz reference

wire reset = RESET | status[0] | buttons[1] | ioctl_download;

///////////////////         Keyboard           //////////////////

reg btn_up       = 0;
reg btn_down     = 0;
reg btn_left     = 0;
reg btn_right    = 0;
reg btn_fire     = 0;
reg btn_fire2    = 0;
reg btn_coin1    = 0;
reg btn_coin2    = 0;
reg btn_1p_start = 0;
reg btn_2p_start = 0;
reg btn_pause    = 0;
reg btn_service  = 0;

wire pressed = ~ps2_key[9];
wire [7:0] code = ps2_key[7:0];
always @(posedge CLK_40M) begin   // CLOCK-UNIFY-2026-07-04: was CLK_10M
	reg old_state;
	old_state <= ps2_key[10];
	if(old_state != ps2_key[10]) begin
		case(code)
			'h16: btn_1p_start <= pressed; // 1 = Player 1 Start
			'h1E: btn_2p_start <= pressed; // 2 = Player 2 Start
			'h2E: btn_coin1    <= pressed; // 5 = Coin Input 1
			'h36: btn_coin2    <= pressed; // 6 = Coin Input 2
			'h4D: btn_pause    <= pressed; // P = Pause
			'h46: btn_service  <= pressed; // 9 = Test Advance

			'h75: btn_up       <= pressed; // up         = Up
			'h72: btn_down     <= pressed; // down       = Down
			'h6B: btn_left     <= pressed; // left       = Left
			'h74: btn_right    <= pressed; // right      = Right
			'h14: btn_fire     <= pressed; // ctrl       = Draw Slow
			'h12: btn_fire2    <= pressed; // left shift = Draw Fast
		endcase 
	end
end

//////////////////  Arcade Buttons/Interfaces   ///////////////////////////

// Dragon's Lair / Space Ace: 4-way joystick + one action button (SWORD).
//Player 1
wire m_up1      = btn_up        | joystick_0[3];
wire m_down1    = btn_down      | joystick_0[2];
wire m_left1    = btn_left      | joystick_0[1];
wire m_right1   = btn_right     | joystick_0[0];
wire m_action1  = btn_fire      | joystick_0[4];
// SKILL-BUTTONS-2026-07-25: Space Ace's skill-level daughter board. Authority = Daphne
// game/lair.cpp:1055-1063 (SWITCH_SKILL1/2/3 clear joyskill bits 5/6/7); port $C008 is the
// "joystick/spaceace skill query" (lair.cpp:771). Active-low at the port via p1_bus = ~p1.
// MRA button order (Fire,Cadet,Captain,SpaceAce,...) = joystick_0[4],[5],[6],[7].
// Unused by Dragon's Lair, which simply never reads these bits.
wire m_skill1   = joystick_0[5];   // Cadet      -> p1[5]
wire m_skill2   = joystick_0[6];   // Captain    -> p1[6]
wire m_skill3   = joystick_0[7];   // Space Ace  -> p1[7]

//Start/Coin
wire m_start1   = btn_1p_start  | joystick_0[9];
wire m_start2   = btn_2p_start  | joystick_0[10];
wire m_coin1    = btn_coin1     | joystick_0[8];
wire m_coin2    = btn_coin2     | joystick_1[8];
// SEEK-BUTTONS-2026-08-15: L and R become index seek, so L must come OFF the
// MiSTer system pause or the two fight over joystick_0[11]. System pause remains
// on the keyboard 'P' and the OSD; the TAPE pause is Start, which is the one a
// player actually wants.
// ORIGINAL: wire m_pause = btn_pause | joystick_0[11];
wire m_pause    = btn_pause;
wire m_seek_prev = joystick_0[11];   // L
wire m_seek_next = joystick_0[10];   // R

// PAUSE SYSTEM
wire pause_cpu;
wire [23:0] rgb_out;
// DEAD-CODE-2026-07-05 FOLLOWUP: r/g/b used to be implicitly connected via .* to the
// (since-removed) dead CPU-video wires -- explicit now so this can't silently break again.
// rgb_out is still NOT consumed by arcade_video (RGB_in is fed by comp_r/g/b directly, see
// below) -- the dim-after-10s-paused feature has been non-functional since the FB-PIVOT-
// 2026-07-04 rewiring, predating this session. Left as-is (pre-existing, separate gap) rather
// than silently also wiring it in -- that's a real display-behavior change, not a compile fix.
pause #(8,8,8,CORE_CLK_HZ/1000000) pause  // CLKSPD in MHz; was hardcoded 10 while the clock was 40
(
	.*,
	.clk_sys(CLK_40M),   // CLOCK-UNIFY-2026-07-04: was CLK_10M
	.user_button(m_pause),
	.pause_request(1'b0),   // hiscore removed 2026-07-04
	.options(~status[26:25]),
	.r(comp_r), .g(comp_g), .b(comp_b)
);

///////////////                 Video                  ////////////////

// ---- Raster video path (DDR framebuffer -> arcade_video) : FB-PIVOT-2026-07-04 ----
wire        rr_ce_pix, rr_hs, rr_vs, rr_hblank, rr_vblank;
wire [15:0] rr_hpos, rr_vpos;
wire  [7:0] rr_r, rr_g, rr_b;
wire  [7:0] comp_r, comp_g, comp_b;   // video + menu selection border (assigned after the panel renderer)
// DIAG: 16-bit status readout in the panel. Two rows of 8 stripes, white = 1, grey = 0, read left->right.
//   top row    0 fb_ddr waiting on a read burst   1 reader waiting (lr_req!=lr_ack)
//              2 writer waiting (we_req!=we_ack)  3 fill_idle
//              4 EVER got read data               5 EVER completed a line burst
//              6 EVER got a write ack             7 DDRAM_BUSY right now
//   bottom row fb_ddr beats_left[7:0], MSB first
wire [24:0] rr_lr_addr;     // fb_raster_reader -> fb_ddr line-burst port
wire  [7:0] rr_lr_len;
wire        rr_lr_req, rr_lr_ack, rr_lr_valid;
wire [63:0] rr_lr_data;
// WRITE-GATE-2026-07-16 (new wire, delete on revert): fb_raster_reader tells fb_writer when its
// line fetch has landed, so the writer never contends with an in-flight read2.  Declared here
// because fb_writer is instantiated ABOVE fb_raster_reader.
wire        rr_fill_idle;

// DEAD-CODE-2026-07-05: the Kangaroo-derived rotation/2x-doubling scheme (ce_pix_2x,
// rotate_ccw, no_rotate, flip) was removed here — its only consumer, screen_rotate, was
// already commented out 2026-07-04 (SCREEN_ROTATE-REMOVED, see below), leaving those wires
// unread by anything (confirmed by grep + arcade_video's real port list has no such ports).
// DL/SA are ROT0 (horizontal) and always were; the video path never actually rotated.
//
// SCREEN_ROTATE-REMOVED-2026-07-04: DL/SA are ROT0, so screen_rotate only ever rotated a
// BLANK raster — and it drives FB_*/DDRAM_*, which our LD-video framebuffer now owns (see
// the STAGE-2 VIDEO block near endmodule).  Removed to resolve the multiple-driver conflict
// on FB_*/DDRAM_*.  video_rotated (its only other output) is tied off at its decl.
// To restore rotation: reinstate rotate_ccw/no_rotate/flip above, re-add
// `screen_rotate screen_rotate(.*);`, and delete the FB_* assigns + STAGE-2 VIDEO block.

// RASTER PATH (FB-PIVOT-2026-07-04): arcade_video is now driven by fb_raster_reader
// (DDR framebuffer) with the LED band composited over it — replaces the old core LED
// raster + 512-wide doubling.  Everything is on the standard core-video path, so the
// LED band shows AND the MiSTer screenshot captures it.
// RES-512x480-2026-07-24: first parameter is arcade_video's WIDTH -- the depth of video_mixer's
// scandoubler/hq2x line buffers. It MUST be >= H_ACT or those buffers wrap mid-line.
// ORIGINAL: arcade_video #(320,24) arcade_video
// ORIGINAL (512-wide raster): arcade_video #(512,24) arcade_video
arcade_video #(960,24) arcade_video   // WIDTH >= canvas width (CANVAS_W)
(
	.*,

	.clk_video(CLK_40M),
	.ce_pix(rr_ce_pix),

	.RGB_in({comp_r, comp_g, comp_b}),
	.HBlank(rr_hblank),
	.VBlank(rr_vblank),
	.HSync(rr_hs),
	.VSync(rr_vs),

	.fx(status[17:15])
);

// DIP switches — arrive from the OSD via ioctl index 254 (standard MiSTer DIP
// download). The MRA <switches> writes DSW1 -> byte 0, DSW2 -> byte 1.
// dsw[7:0] = DSW1 (AY port A), dsw[15:8] = DSW2 (AY port B).
reg [7:0] dip_sw[8] = '{8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_40M) begin   // CLOCK-UNIFY-2026-07-04: was CLK_10M (ioctl now same-domain 40M)
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end
wire [15:0] dsw = {dip_sw[1], dip_sw[0]};
wire [16:0] ld_curr_frame_top;   // HLE-DRIVE-2026-07-04: LD disc frame from DragonsLair -> dlv_streamer

// ---- SEEK-HOLD-2026-07-20 (step 1: the delay mechanism) --------------------------------------
// A real LD player does NOT seek instantly -- the head moves and playback visibly stalls. The
// games were designed around that pause. Resuming instantly is what left video racing to catch up
// (stutter, frames shown that should have been passed, audio ahead of picture). So: on a seek,
// HOLD both streams, refill the pipeline, then release TOGETHER and free-run until the next seek.
//   video : fb_adopt inhibited -> display FREEZES on the last frame (better than the black/zigzag
//           a real player showed).
//   audio : dlv_streamer mutes and HOLDS aud_rd, so the ring REFILLS instead of draining.
// Release requires BOTH: SEEK_PRIME post-seek frames decoded AND the audio ring primed.
//
// Declared here (above the dlv_streamer instance) because the instance uses them; the rest of the
// state machine lives with the framebuffer logic further down.
wire       fb_seek_pulse;      // = the Z80's CMD_SEARCH, straight from the LDV1000
reg        fb_seek_q;          // SEEK-HOLD-2026-07-20: edge-detect the arm. Belt-and-braces --
wire       fb_seek_edge = fb_seek_pulse & ~fb_seek_q;   // if the source ever stuck HIGH, a
                               // LEVEL-triggered arm would re-arm every cycle and the hold could
                               // never release (FSM-model-proven). An EDGE can only arm once.
wire       fb_aud_primed;      // from dlv_streamer (ring >= SEEK_FILL)
reg        fb_seek_hold;       // driven in the framebuffer block below

wire        ld_playing_top;      // AUDIO-GATE-2026-07-05: tape is rolling -> dlv_streamer audio gate

// UI-SEAM-2026-08-15: modal state out of Robots.sv, awaiting the overlay renderer.
/* verilator lint_off UNUSED */
wire        ui_modal_w;          // 1 = draw a modal over the video window
wire        ui_confirm_sel_w;    // 0 = "No" highlighted, 1 = "Yes"
wire        card_show_w;         // 1 = paint clue card full-screen over the video
wire  [2:0] card_id_w;           // 0..5 = card A..F
wire  [5:0] cards_revealed_w;    // sticky reveal mask for the thumbnail strip
/* verilator lint_on UNUSED */

// STRIP-2026-08-15: `DragonsLair dl_inst` (Z80 + AY-3-8910 + LD-V1000 HLE) replaced by the
// Robots tape transport. Same five-signal seam, so nothing below this point changed.
// Ports that went with the arcade hardware: .dsw (DIP switches read through the AY -- no AY,
// and difficulty is a boot-time menu choice here, not a DIP), .sound_l/.sound_r (no sound
// chip; ALL audio is the .dlv tape audio, see AUDIO_L/R above), and .ioctl_* (no ROMs to
// load -- the only payload is robots.dlv, which arrives over the sd_*/img_* block interface
// on hps_io slot 0, not the ioctl ROM path).
//
// Controls follow README.MD. Verified against the joystick bits at lines 413-432 rather than
// assumed: Start is joystick_0[9] -> m_start1 -> cab[0], which does NOT collide with the
// MiSTer system pause on joystick_0[11] (m_pause -> pause_cpu). Those are two different
// pauses and both are wired: Start holds the TAPE, the OSD/P pause freezes the whole core.
wire  [1:0] g_phase_w, g_packet_w;   // game state -> panel renderer
wire        g_pick_w;
wire  [5:0] g_seed_w;
wire  [1:0] g_cm_w;                  // card moment: 0 none, 1 choose face, 2 zoomed
wire  [2:0] g_cm_card_w;
wire        g_cm_sel_w;
wire  [4:0] g_focus_w;      // cursor: 0 video, 1 Map, 2 Suspects, 3..8 card A..F, 9..19 suspects, 20..23 endgame buttons
wire  [2:0] g_view_w;       // view: 0 none, 1 map, 2 leaflet, 3 answer, 4 notebook, 5 game assets, 6 clue zoom
wire  [3:0] g_gal_w;        // game assets item
wire  [1:0] g_eg_w;         // endgame: 0 play, 1 accusation, 2 verdict (credits), 3 end
wire        g_armed_w, g_win_w;
wire  [4:0] g_page_w;       // answer / notebook page
Robots #(.CLK_HZ(CORE_CLK_HZ)) robots_inst
(
	.reset(~reset),       // MiSTer reset is active-high; invert for active-low game modules

	.clk_sys(CLK_40M),    // 40 MHz -- film cadence divider lives inside Robots.sv

	// { R, L, B, A, right, left, down, up } active-high.
	// A = joystick_0[4] (select/activate), B = joystick_0[5] (return/revert),
	// L = joystick_0[11] (seek prior index), R = joystick_0[10] (seek next index).
	.p1({m_seek_next, m_seek_prev, m_skill1, m_action1, m_right1, m_left1, m_down1, m_up1}),
	// { coin2, coin1, start2, start1 } -- cab[0] = Start = play/pause,
	// cab[2] = m_coin1 = the pad's Select button (reserved for difficulty).
	.cab({m_coin2, m_coin1, m_start2, m_start1}),

	.pause(pause_cpu),
	// LD-HOLD-SYNC-2026-08-13: the seek hold freezes the frame counter as well as the picture.
	// fb_seek_hold is already in this CLK_40M domain, so no CDC is needed.
	.disc_hold(fb_seek_hold),

	.led_digits_o(),
	.dbg_led(dbg_led),
	.ld_frame_o(ld_curr_frame_top), .ld_search_cmd_o(fb_seek_pulse),
	.ld_playing_o(ld_playing_top),

	// UI-SEAM-2026-08-15: consumed by the overlay renderer once the clue-panel
	// framebuffer exists. Connected (not left dangling) so the seam is explicit
	// and the signals are already named where the renderer will need them.
	// Until then the modal state is visible on the LED band's debug digit 15.
	.ui_modal_o(ui_modal_w), .ui_confirm_sel_o(ui_confirm_sel_w),
	// INDEX-2026-08-15: clue-card state for the (not yet built) overlay renderer.
	// card_show_w is high across the whole Clue Card segment while the tape keeps
	// rolling, so the renderer paints the card over the video window and the
	// on-tape audio sting plays underneath.
	.card_show_o(card_show_w), .card_id_o(card_id_w), .cards_revealed_o(cards_revealed_w),
	.phase_o(g_phase_w), .packet_o(g_packet_w), .pick_mode_o(g_pick_w), .seed_o(g_seed_w),
	.cm_o(g_cm_w), .cm_card_o(g_cm_card_w), .cm_sel_o(g_cm_sel_w),
	.focus_o(g_focus_w), .view_o(g_view_w), .gal_o(g_gal_w),
	.eg_o(g_eg_w), .armed_o(g_armed_w), .win_o(g_win_w), .page_o(g_page_w)
);

// HISCORE REMOVED 2026-07-04 — Dragon's Lair / Space Ace / Thayer's Quest do not
// persist high scores.  The hiscore module was the SOLE driver of ioctl_din and
// ioctl_upload_req, so tie them off to keep hps_io happy.
assign ioctl_din        = 8'd0;
assign ioctl_upload_req = 1'b0;

//============================================================================
// STAGE-2 VIDEO CHECKPOINT (FB-TESTPATTERN-2026-07-04)
//----------------------------------------------------------------------------
// Enable the MISTER_FB framebuffer in HPS DDR3 (via rtl/ram_rom/ddram.sv @
// 0x30000000) and drive it with a test pattern to prove the ddram -> DDR3 FB ->
// ascal scaler path BEFORE the real streamer/decoder are hung on it.
// NOTE: while FB_EN=1 the scaler shows the framebuffer, so the LED-band /
// arcade_video output is NOT displayed during this checkpoint.
// TO REVERT to the LED-band display: set FB_EN back to 1'b0 (the DDR block below
// is then harmless/idle).  All of this runs in the CLK_40M domain (= DDRAM_CLK),
// so there is no hps_io/CDC involved yet.
//============================================================================
// FB-PIVOT-2026-07-04: MISTER_FB DISPLAY DISABLED.  It bypasses the core-video/
// arcade_video path where the LED band AND the screenshot both live, so it dropped
// the score and wasn't captured.  Switching to the RASTER path: the decoder writes
// frames to DDR (ddram/fb_writer below, kept), a raster reader reads them back in
// scan order into arcade_video, LED band composited in.  FB_EN stays 0.
assign FB_EN     = 1'b0;
assign FB_FORMAT = 5'b00100;      // (ignored while FB_EN=0) [2:0]=100 16bpp, [3]=0 565, [4]=0 RGB
assign FB_WIDTH  = 12'd320;
assign FB_HEIGHT = 12'd240;
assign FB_BASE   = 32'h30000000;  // must match fb_ddr.sv region base
assign FB_STRIDE = 14'd640;       // 320 px * 2 B (tight 16bpp)

assign DDRAM_CLK = CLK_40M;

wire [27:1] fb_wraddr;
wire [15:0] fb_din;
wire        fb_we_req, fb_we_ack;
wire [63:0] fb_din64;   // WRITE-STAGE-A-2026-07-20
wire  [7:0] fb_be64;
wire        tp_we, tp_ready;
wire [15:0] tp_x, tp_y;
wire  [7:0] tp_r, tp_g, tp_b;

// LD-VIDEO-STAGE1-2026-07-04: real .dlv -> block streamer -> JPEG decoder -> fb_writer.
// DIAG-REVERT-2026-07-04: the proven test-pattern source is kept commented for a 1-uncomment
// fallback (also restore fb_writer's px_* to tp_* below if you re-enable it).
// fb_testpattern tp_gen (
//     .clk(CLK_40M), .reset(reset),
//     .ready(tp_ready), .we(tp_we),
//     .x(tp_x), .y(tp_y), .r(tp_r), .g(tp_g), .b(tp_b)
// );

// ---- .dlv block streamer (hps_io slot 0) — all CLK_40M, single-clock, no CDC ----
wire  [7:0] strm_byte;
wire        strm_valid, strm_ready, strm_last;
wire        dec_reset_w;                // STREAMING-2026-07-04: per-frame decoder reset (decoder only)
wire signed [15:0] pcm_l, pcm_r;        // STREAMING-2026-07-04: .dlv PCM -> audio mux (see AUDIO_L/R above)
wire        dec_frame_done, dec_idle;   // declared here: the streamer's blit interlock reads dec_idle
// Asset blit (streamer fetches a .dlv asset frame; decoder + fb_writer draw it into the panel)
reg         blit_req_r = 1'b0;
reg  [16:0] blit_frame_r = 17'd0;
reg         blit_busy = 1'b0;           // a blit is decoding: hold off video fetches
wire        blit_ack_w, fetch_blit_w, blit_start_w, blit_fail_w;
wire [16:0] tape_frames_w;

// STREAMING-2026-07-04: continuous video+audio streamer.  Free-runs film frames from START_FRAME
// (paced ~30 fps), and keeps a 44.1 kHz PCM ring topped up (audio has SD priority).  The one-shot
// frame fetch (ld_req_*/STAGE1_FRAME) is removed — this is the real streaming path.
// ROBOTS-RATE-2026-08-15: START_FRAME 1000 -> 0. DL used 1000 to skip its black leader;
// robots.dlv was packed with ldframe_offset=0 and disc==video 1:1, so frame 0 is real content.
dlv_streamer #(.CLK_HZ(CORE_CLK_HZ), .START_FRAME(17'd0)) dlv_strm (
    .clk(CLK_40M), .reset(reset),
    .img_mounted(dlv_img_mounted), .img_size(dlv_img_size),
    .sd_lba(dlv_sd_lba[0]), .sd_blk_cnt(dlv_sd_blk_cnt[0]),
    .sd_rd(dlv_sd_rd), .sd_ack(dlv_sd_ack),
    .sd_buff_addr(dlv_sd_buff_addr), .sd_buff_dout(dlv_sd_buff_dout), .sd_buff_wr(dlv_sd_buff_wr),
    .out_byte(strm_byte), .out_valid(strm_valid), .out_ready(strm_ready), .out_last(strm_last),
    .dec_reset(dec_reset_w),
    .pcm_l(pcm_l), .pcm_r(pcm_r),
    .ld_curr_frame(ld_curr_frame_top), .pause(pause_cpu),   // HLE-DRIVE-2026-07-04
    .aud_primed(fb_aud_primed), .hold_play(fb_seek_hold), .seek_flush(fb_seek_pulse),   // SEEK-HOLD/FLUSH-2026-07-20
    .ld_playing(ld_playing_top),                            // AUDIO-GATE-2026-07-05
    .blit_req(blit_req_r), .blit_frame(blit_frame_r), .blit_ack(blit_ack_w),
    .dec_idle(dec_idle), .blit_hold(blit_busy),
    .fetch_blit(fetch_blit_w), .blit_start(blit_start_w), .blit_fail(blit_fail_w), .tape_frames(tape_frames_w)
);


// ---- JPEG frame decoder: byte stream -> px writes (block-order, addressed by x,y) ----
wire        dec_px_we, dec_px_ready;
wire [15:0] dec_px_x, dec_px_y, dec_w, dec_h;
wire  [7:0] dec_px_r, dec_px_g, dec_px_b;

jpeg_frame_decoder dec (
    .clk(CLK_40M), .rst(dec_reset_w),   // STREAMING-2026-07-04: per-frame reset (NOT global); fb_writer stays on global reset
    .in_byte(strm_byte), .in_valid(strm_valid), .in_ready(strm_ready), .in_last(strm_last),
    .px_ready(dec_px_ready), .px_we(dec_px_we),
    .px_x(dec_px_x), .px_y(dec_px_y), .px_r(dec_px_r), .px_g(dec_px_g), .px_b(dec_px_b),
    .frame_width(dec_w), .frame_height(dec_h), .frame_done(dec_frame_done), .idle(dec_idle)
);


// FB-DOUBLEBUF-2026-07-15: two-frame ping-pong so the decoder never writes into the same buffer
// the raster reader is scanning out of. Root cause of the black-line-comb/streak bug (latest17):
// fb_writer and fb_raster_reader were both hardcoded to DDR halfword base 0 -- one shared
// framebuffer, no swap at all, so the reader could catch a frame mid-write. Swap on the decoder's
// own frame_done pulse (dec_frame_done was computed above but never connected to anything).
// FB-TRIPLEBUF-2026-07-20: the two-buffer ping-pong above was NOT sufficient, and the reason is
// structural -- keeping the old code commented directly below for reference.
//
// THE BUG IT FIXES (matches "garbage rows in the TOP area of specific frames, identical every
// attract cycle"): fb_raster_reader deliberately LATCHES frame_base_hw once per raster frame
// (fb_raster_reader.v:128-134, applied at v_last) so a mid-scan flip can't tear one displayed
// frame across two buffers. But fb_wr_base flipped IMMEDIATELY on dec_frame_done. So when the
// decoder finished mid-scanout:
//   reader has BUF1 latched and is still scanning it  ->  fb_buf_sel toggles  ->
//   writer's base becomes BUF1  ->  writer writes the NEXT frame INTO THE BUFFER BEING DISPLAYED.
// fb_writer emits top-to-bottom, so wherever it outran the raster beam those upper rows showed
// the new frame's pixels, with correct output below = a garbage band at the top that recovers.
// Deterministic per frame because decode duration tracks frame size, so a given frame always
// collides at the same point. With only TWO buffers this is unavoidable: the writer's back buffer
// and the reader's latched front buffer are forced to be the same buffer.
// (The fill_idle write-gate does not help -- it arbitrates DDR BUS access, not buffer choice.)
//
// THE FIX: three buffers with an explicit ready/display handoff. Invariant maintained below:
// wr_idx != disp_idx ALWAYS, so the writer can never target the displayed buffer.
//   - dec_frame_done : the just-written buffer becomes `ready`; writing moves to the one buffer
//                      that is neither `ready` nor `disp` (indices 0+1+2=3, so free = 3-a-b).
//   - reader vblank  : if a completed frame is waiting, adopt it as the new display buffer.
// Updating disp_idx at the RISING EDGE OF VBLANK gives the value time to settle well before the
// reader's own latch fires at v_last, so the reader still sees one stable base per frame.
// Cost: one extra 320x240x16b buffer = 153,600 B in the 0x30000000 region (ddram_fb is ours
// alone -- rom_req is hardwired off on this core's instance).
//
// DIAG-REVERT-2026-07-20: original two-buffer logic, uncomment to restore
// localparam [26:0] FB_BUF0_HW = 27'd0;
// localparam [26:0] FB_BUF1_HW = 27'd76800;   // 320*240 halfwords past buf0
// reg fb_buf_sel;
// always @(posedge CLK_40M) begin
//     if (reset) fb_buf_sel <= 1'b0;
//     else if (dec_frame_done) fb_buf_sel <= ~fb_buf_sel;
// end
// wire [26:0] fb_wr_base = fb_buf_sel ? FB_BUF1_HW : FB_BUF0_HW;   // decoder writes here (back buffer)
// wire [26:0] fb_rd_base = fb_buf_sel ? FB_BUF0_HW : FB_BUF1_HW;   // raster reader reads here (front buffer)

// ---- RES-512x480-2026-07-24: framebuffer geometry, defined ONCE and passed everywhere ----------
// The Daphne source m2v IS 512x480, so encoding at 512x480 is a pure re-compress with NO resampling
// at all -- which is why raising JPEG quality (q3 -> q2) and switching the downscale to lanczos both
// bought ZERO visible improvement: resampling was never the dominant loss, the 320x240 pixel budget
// was. 512 is also exactly fb_raster_reader's line-buffer ceiling (linebuf[0:1023] indexed
// {buf, hcnt[8:0]} => 2 x 512), so the widest useful target needs no line-buffer change.
// ORIGINAL (320x240): FB_COLS_HW=320, FB_ROWS_HW=240, FB_BUF_HW=27'd76800.
localparam [15:0] FB_COLS_HW   = 16'd512;
localparam [15:0] FB_ROWS_HW   = 16'd480;
localparam [26:0] FB_BUF_HW    = 27'd245760;  // 512*480 halfwords per buffer (was 76800)
// Display canvas (square pixels, sys scales 2x to 1080p). Video window at (VID_X, VID_Y); rest is panel.
localparam [15:0] CANVAS_W     = 16'd960;
localparam [15:0] CANVAS_H     = 16'd540;
localparam [15:0] VID_X        = 16'd0;
localparam [15:0] VID_Y        = 16'd30;
localparam [15:0] CANVAS_BG    = 16'h10A3;    // RGB565 near-black blue, matches the layout mockup
localparam [26:0] FB_BUF0_HW   = 27'd0;
localparam [26:0] FB_BUF1_HW   = FB_BUF_HW;
localparam [26:0] FB_BUF2_HW   = FB_BUF_HW * 2;
localparam [26:0] PANEL_BASE_HW = FB_BUF_HW * 3;   // single 960x540 panel buffer (stride CANVAS_W) after the 3 video buffers
// Card thumbnail slots (canvas pixels): 279x321 -> 140x161, a 3x2 grid on the right: A B C / D E F.
localparam [15:0] SLOT_X0 = 16'd519, SLOT_X1 = 16'd666, SLOT_X2 = 16'd813;
localparam [15:0] SLOT_Y0 = 16'd200, SLOT_Y1 = 16'd370;
reg  [26:0] blit_base_r = 27'd0;
reg         blit_half_r = 1'b0;
reg  [15:0] blit_dx_r = 16'd0, blit_dy_r = 16'd0;
// Destination of the blit being decoded, latched when its fetch starts: a later request must not redirect it.
reg  [26:0] blit_base_a = 27'd0;
reg         blit_half_a = 1'b0;
reg  [15:0] blit_dx_a = 16'd0, blit_dy_a = 16'd0;
// never past the panel edge (clip is in source pixels; a half-size blit covers twice its room)
wire [15:0] blit_room_w = CANVAS_W - blit_dx_a;
wire [15:0] blit_room_h = CANVAS_H - blit_dy_a;
wire [15:0] blit_lim_w  = blit_half_a ? {blit_room_w[14:0], 1'b0} : blit_room_w;
wire [15:0] blit_lim_h  = blit_half_a ? {blit_room_h[14:0], 1'b0} : blit_room_h;
wire [15:0] blit_clip_w = (dec_w > blit_lim_w) ? blit_lim_w : dec_w;
wire [15:0] blit_clip_h = (dec_h > blit_lim_h) ? blit_lim_h : dec_h;

reg  [1:0] fb_wr_idx;      // buffer the decoder is writing
reg  [1:0] fb_disp_idx;    // buffer the raster reader is displaying
reg  [1:0] fb_ready_idx;   // most recently COMPLETED frame, waiting to be displayed
reg        fb_have_new;    // a completed frame is waiting for the next vblank

// ---- SEEK-HOLD-2026-07-20 state (see the note above the dlv_streamer instance) ---------------
localparam [2:0]  SEEK_PRIME = 3'd3;          // post-seek frames to bank before resuming
localparam [31:0] CORE_CLK_HZ = 32'd100_000_000;   // CLK-PARAM-2026-08-15: single source
localparam [27:0] SEEK_TMO   = CORE_CLK_HZ[27:0];  // ~1 s at any clock  // ~1 s @40 MHz -- SAFETY, see below

// Blit bookkeeping: busy from the blit fetch until its decode completes (or 100 ms, so a bad
// asset can never stall video).
localparam [26:0] BLIT_TMO = CORE_CLK_HZ[26:0];   // 1 s: a full-size card over real SD can exceed 100 ms
reg [26:0] blit_tmr = 27'd0;
reg        blit_ok = 1'b0;             // BLIT-RETRY-2026-09-25: this blit's decode reached its last pixel
always @(posedge CLK_40M) begin
    if (reset || blit_start_w) blit_ok <= 1'b0;
    else if (blit_busy && dec_frame_done) blit_ok <= 1'b1;
end
always @(posedge CLK_40M) begin
    if (reset) begin
        blit_busy <= 1'b0; blit_tmr <= 27'd0;
    end else if (blit_start_w) begin
        blit_busy <= 1'b1; blit_tmr <= 27'd0;
        blit_base_a <= blit_base_r; blit_half_a <= blit_half_r; blit_dx_a <= blit_dx_r; blit_dy_a <= blit_dy_r;
    end else if (blit_busy) begin
        // BLIT-RETRY-2026-09-25 original: if (dec_frame_done || blit_tmr == BLIT_TMO) blit_busy <= 1'b0;
        if (dec_frame_done || blit_fail_w || blit_tmr == BLIT_TMO) blit_busy <= 1'b0;
        else blit_tmr <= blit_tmr + 27'd1;
    end
end

// Panel renderer: every piece of panel art is an asset blit, requested on game events.
//   menus      : entering a menu repaints the panel, then draws ALL of that menu's choices as
//                half-size plates in a column in the video window (video is off in the menus);
//                the selection is a border drawn at scanout, so moving it redraws nothing
//   thumbnails : one per newly revealed card, into its slot
//   restart    : back to the skill menu = repaint (thumbnails gone) + skill plates
// Asset k is .dlv frame tape_frames + k (layout: _VCR/assets/manifest.json).
localparam [16:0] A_DIFFICULTY = 17'd311;   // difficulty_0_beginner .. difficulty_3_expert (420x200)
localparam [16:0] A_MODE       = 17'd315;   // mode_0_random, mode_1_choose
localparam [15:0] PLATE_X = 16'd151;        // 210x100 half-size plates, centred in the 512x480 window
localparam [15:0] PLATE_W = 16'd210, PLATE_H = 16'd100, PLATE_PITCH = 16'd116, PLATE_Y0 = 16'd46;
localparam [16:0] A_BTN_MAP    = 17'd305;   // btn_0_show_map, btn_1_suspects (426x140), half-size along the panel top
localparam [15:0] MAP_X = 16'd520, MAP_Y = 16'd8, BTN_PITCH = 16'd219;
reg  [1:0] ph_q = 2'd3;
reg  [5:0] cards_q = 6'd0;
reg  [3:0] plate_need = 4'd0;                // plate rows still to draw on the current menu screen
reg  [5:0] card_need = 6'd0;
reg  [1:0] cm_q = 2'd0;
reg  [1:0] face_need = 2'd0;                // card moment, choose: both faces still to draw
reg        zoom_need = 1'b0;                // card moment: the zoomed card still to draw
reg  [1:0] map_need = 2'd0;                 // Show Map / Suspects buttons still to draw (first card moment of a game)
reg        map_drawn = 1'b0;
reg        blit_cm_q = 1'b0;                // the blit in flight is modal art (card moment or study view)
// Study views, half-size tiles from the .dlv: map = leaflet_map (2 tiles, 586x540);
// leaflet = Important Data | Cast | Cast, pages side by side (5 tiles, 837x540).
localparam [16:0] A_LEAFLET = 17'd271;       // map t0,t1 = 271,272; page1 273,274; page2 275,276; page3 277
// Views 3-6 and the endgame panel (2026-09-25): answer page (2 tiles, 285x540 over the video column),
// notebook (3 tiles, full width, centred), game assets (2-6 tiles, full canvas), clue zoom (the full card).
localparam [16:0] A_SUSPECT = 17'd317;       // suspect_00..10 (760x88) -> 380x44 plates over the frozen video
localparam [15:0] SUS_X = 16'd66, SUS_Y0 = 16'd17, SUS_PITCH = 16'd46, SUS_W = 16'd380, SUS_H = 16'd44;
localparam [15:0] EGB_X0 = 16'd520, EGB_X1 = 16'd739, EGB_Y0 = 16'd85, EGB_Y1 = 16'd163;   // endgame buttons
reg  [5:0] view_need = 6'd0;
reg  [2:0] view_q = 3'd0;
reg  [3:0] gal_q = 4'd0;
reg  [1:0] eg_q = 2'd0;
reg  [4:0] eg_need = 5'd0;                   // banner, Full Answer, Baley's Notes, Play Again, Game Assets
reg [10:0] sus_need = 11'd0;                 // suspect plates still to draw
reg  [2:0] closed_v = 3'd0;                  // the view that just closed
// BLIT-RETRY-2026-09-25: a blit that ends without a completed decode (watchdog abort or timeout) is
// re-issued unchanged -- the blit_*_r registers still hold it -- up to 3 times, before anything else.
reg        retry_pend = 1'b0;
reg  [1:0] retry_cnt = 2'd0;
reg        verdict_pend = 1'b0;              // verdict: clear the panel once nothing is in flight
reg        view_close = 1'b0;                // a view just closed: repaint the panel once nothing is in flight
reg        cm_post = 1'b0;                  // after B: keep the zoomed card up until the tape's jump has settled
reg        cm_post_hold = 1'b0;             // the seek hold for that jump has started
reg [27:0] cm_post_tmr = 28'd0;
wire [1:0] disp_cm = (g_cm_w != 2'd0) ? g_cm_w : (cm_post ? 2'd2 : 2'd0);   // what the video column shows
reg        pf_refill = 1'b0;
reg        pf_wait = 1'b0;                  // refill requested, filler not yet restarted
reg        blit_inflight = 1'b0;            // issued and not yet decoded: its destination must not change
reg        blit_busy_q = 1'b0;
// Original: reg [24:0] blit_wait_tmr (dropped after ~0.3 s -- shorter than a post-seek audio refill on real SD)
reg [27:0] blit_wait_tmr = 28'd0;           // safety: a request never picked up is dropped after ~2.7 s
wire       pf_done;
wire       in_menu   = (g_phase_w != 2'd2);
wire [5:0] need_now  = card_need | (cards_revealed_w & ~cards_q);
wire [2:0] need_k    = need_now[0] ? 3'd0 : need_now[1] ? 3'd1 : need_now[2] ? 3'd2 :
                       need_now[3] ? 3'd3 : need_now[4] ? 3'd4 : 3'd5;
wire [15:0] slot_x   = (need_k == 3'd0 || need_k == 3'd3) ? SLOT_X0 :
                       (need_k == 3'd1 || need_k == 3'd4) ? SLOT_X1 : SLOT_X2;
wire [15:0] slot_y   = (need_k < 3'd3) ? SLOT_Y0 : SLOT_Y1;
wire [26:0] slot_base = PANEL_BASE_HW + slot_y * CANVAS_W + {11'd0, slot_x};
wire [16:0] thumb_asset = {12'd0, g_packet_w, 3'b000} * 17'd3 + {12'd0, need_k, 2'b00} + {15'd0, g_seed_w[need_k], 1'b0} + 17'd1;   // p*24 + k*4 + side*2 + 1
// Card moment art in the 512-wide video column: faces 225x259 side by side, zoomed card 449x517.
localparam [15:0] FACE_X0 = 16'd21, FACE_X1 = 16'd266, FACE_Y = 16'd140, FACE_W = 16'd225, FACE_H = 16'd259;
localparam [15:0] ZOOM_X  = 16'd31, ZOOM_Y  = 16'd11,  ZOOM_W = 16'd449, ZOOM_H = 16'd517;
wire        face_j    = face_need[0] ? 1'b0 : 1'b1;
wire [16:0] card_asset_base = {12'd0, g_packet_w, 3'b000} * 17'd3 + {12'd0, g_cm_card_w, 2'b00};   // p*24 + k*4
wire [16:0] face_asset = card_asset_base + {15'd0, face_j, 1'b0};                 // full card, face j
wire [16:0] zoom_asset = card_asset_base + {15'd0, g_seed_w[g_cm_card_w], 1'b0};  // full card, chosen face
wire [15:0] face_x    = face_j ? FACE_X1 : FACE_X0;
// GENERATED from _VCR/assets/manifest.json (2026-09-25): half-size tile placement, {valid, asset[8:0], x[9:0], y[9:0]}.
function [29:0] notes_tile(input [4:0] pg, input [2:0] j);
    case ({pg, j})
        8'd0: notes_tile = {1'b1, 9'd160, 10'd0, 10'd49};   // notes_A t0
        8'd1: notes_tile = {1'b1, 9'd161, 10'd0, 10'd195};   // notes_A t1
        8'd2: notes_tile = {1'b1, 9'd162, 10'd0, 10'd342};   // notes_A t2
        8'd8: notes_tile = {1'b1, 9'd163, 10'd0, 10'd77};   // notes_B t0
        8'd9: notes_tile = {1'b1, 9'd164, 10'd0, 10'd205};   // notes_B t1
        8'd10: notes_tile = {1'b1, 9'd165, 10'd0, 10'd334};   // notes_B t2
        8'd16: notes_tile = {1'b1, 9'd166, 10'd0, 10'd51};   // notes_C t0
        8'd17: notes_tile = {1'b1, 9'd167, 10'd0, 10'd196};   // notes_C t1
        8'd18: notes_tile = {1'b1, 9'd168, 10'd0, 10'd342};   // notes_C t2
        8'd24: notes_tile = {1'b1, 9'd169, 10'd0, 10'd41};   // notes_D t0
        8'd25: notes_tile = {1'b1, 9'd170, 10'd0, 10'd155};   // notes_D t1
        8'd26: notes_tile = {1'b1, 9'd171, 10'd0, 10'd270};   // notes_D t2
        8'd27: notes_tile = {1'b1, 9'd172, 10'd0, 10'd384};   // notes_D t3
        8'd32: notes_tile = {1'b1, 9'd173, 10'd0, 10'd47};   // notes_E t0
        8'd33: notes_tile = {1'b1, 9'd174, 10'd0, 10'd158};   // notes_E t1
        8'd34: notes_tile = {1'b1, 9'd175, 10'd0, 10'd269};   // notes_E t2
        8'd35: notes_tile = {1'b1, 9'd176, 10'd0, 10'd380};   // notes_E t3
        8'd40: notes_tile = {1'b1, 9'd177, 10'd0, 10'd67};   // notes_F t0
        8'd41: notes_tile = {1'b1, 9'd178, 10'd0, 10'd202};   // notes_F t1
        8'd42: notes_tile = {1'b1, 9'd179, 10'd0, 10'd337};   // notes_F t2
        8'd48: notes_tile = {1'b1, 9'd180, 10'd0, 10'd70};   // notes_G t0
        8'd49: notes_tile = {1'b1, 9'd181, 10'd0, 10'd203};   // notes_G t1
        8'd50: notes_tile = {1'b1, 9'd182, 10'd0, 10'd336};   // notes_G t2
        8'd56: notes_tile = {1'b1, 9'd183, 10'd0, 10'd26};   // notes_H t0
        8'd57: notes_tile = {1'b1, 9'd184, 10'd0, 10'd148};   // notes_H t1
        8'd58: notes_tile = {1'b1, 9'd185, 10'd0, 10'd270};   // notes_H t2
        8'd59: notes_tile = {1'b1, 9'd186, 10'd0, 10'd392};   // notes_H t3
        8'd64: notes_tile = {1'b1, 9'd187, 10'd0, 10'd41};   // notes_I t0
        8'd65: notes_tile = {1'b1, 9'd188, 10'd0, 10'd155};   // notes_I t1
        8'd66: notes_tile = {1'b1, 9'd189, 10'd0, 10'd269};   // notes_I t2
        8'd67: notes_tile = {1'b1, 9'd190, 10'd0, 10'd383};   // notes_I t3
        8'd72: notes_tile = {1'b1, 9'd191, 10'd0, 10'd73};   // notes_J t0
        8'd73: notes_tile = {1'b1, 9'd192, 10'd0, 10'd204};   // notes_J t1
        8'd74: notes_tile = {1'b1, 9'd193, 10'd0, 10'd335};   // notes_J t2
        8'd80: notes_tile = {1'b1, 9'd194, 10'd0, 10'd99};   // notes_K t0
        8'd81: notes_tile = {1'b1, 9'd195, 10'd0, 10'd213};   // notes_K t1
        8'd82: notes_tile = {1'b1, 9'd196, 10'd0, 10'd327};   // notes_K t2
        8'd88: notes_tile = {1'b1, 9'd197, 10'd0, 10'd71};   // notes_L t0
        8'd89: notes_tile = {1'b1, 9'd198, 10'd0, 10'd203};   // notes_L t1
        8'd90: notes_tile = {1'b1, 9'd199, 10'd0, 10'd336};   // notes_L t2
        8'd96: notes_tile = {1'b1, 9'd200, 10'd0, 10'd98};   // notes_M t0
        8'd97: notes_tile = {1'b1, 9'd201, 10'd0, 10'd212};   // notes_M t1
        8'd98: notes_tile = {1'b1, 9'd202, 10'd0, 10'd327};   // notes_M t2
        8'd104: notes_tile = {1'b1, 9'd203, 10'd0, 10'd20};   // notes_N t0
        8'd105: notes_tile = {1'b1, 9'd204, 10'd0, 10'd144};   // notes_N t1
        8'd106: notes_tile = {1'b1, 9'd205, 10'd0, 10'd269};   // notes_N t2
        8'd107: notes_tile = {1'b1, 9'd206, 10'd0, 10'd393};   // notes_N t3
        8'd112: notes_tile = {1'b1, 9'd207, 10'd0, 10'd70};   // notes_O t0
        8'd113: notes_tile = {1'b1, 9'd208, 10'd0, 10'd203};   // notes_O t1
        8'd114: notes_tile = {1'b1, 9'd209, 10'd0, 10'd336};   // notes_O t2
        8'd120: notes_tile = {1'b1, 9'd210, 10'd0, 10'd71};   // notes_P t0
        8'd121: notes_tile = {1'b1, 9'd211, 10'd0, 10'd203};   // notes_P t1
        8'd122: notes_tile = {1'b1, 9'd212, 10'd0, 10'd335};   // notes_P t2
        8'd128: notes_tile = {1'b1, 9'd213, 10'd0, 10'd72};   // notes_Q t0
        8'd129: notes_tile = {1'b1, 9'd214, 10'd0, 10'd203};   // notes_Q t1
        8'd130: notes_tile = {1'b1, 9'd215, 10'd0, 10'd335};   // notes_Q t2
        8'd136: notes_tile = {1'b1, 9'd216, 10'd0, 10'd39};   // notes_R t0
        8'd137: notes_tile = {1'b1, 9'd217, 10'd0, 10'd192};   // notes_R t1
        8'd138: notes_tile = {1'b1, 9'd218, 10'd0, 10'd346};   // notes_R t2
        8'd144: notes_tile = {1'b1, 9'd219, 10'd0, 10'd68};   // notes_S t0
        8'd145: notes_tile = {1'b1, 9'd220, 10'd0, 10'd168};   // notes_S t1
        8'd146: notes_tile = {1'b1, 9'd221, 10'd0, 10'd269};   // notes_S t2
        8'd147: notes_tile = {1'b1, 9'd222, 10'd0, 10'd369};   // notes_S t3
        8'd152: notes_tile = {1'b1, 9'd223, 10'd0, 10'd74};   // notes_T t0
        8'd153: notes_tile = {1'b1, 9'd224, 10'd0, 10'd204};   // notes_T t1
        8'd154: notes_tile = {1'b1, 9'd225, 10'd0, 10'd335};   // notes_T t2
        8'd160: notes_tile = {1'b1, 9'd226, 10'd0, 10'd48};   // notes_U t0
        8'd161: notes_tile = {1'b1, 9'd227, 10'd0, 10'd159};   // notes_U t1
        8'd162: notes_tile = {1'b1, 9'd228, 10'd0, 10'd270};   // notes_U t2
        8'd163: notes_tile = {1'b1, 9'd229, 10'd0, 10'd381};   // notes_U t3
        8'd168: notes_tile = {1'b1, 9'd230, 10'd0, 10'd48};   // notes_V t0
        8'd169: notes_tile = {1'b1, 9'd231, 10'd0, 10'd158};   // notes_V t1
        8'd170: notes_tile = {1'b1, 9'd232, 10'd0, 10'd269};   // notes_V t2
        8'd171: notes_tile = {1'b1, 9'd233, 10'd0, 10'd379};   // notes_V t3
        8'd176: notes_tile = {1'b1, 9'd234, 10'd0, 10'd0};   // notes_W t0
        8'd177: notes_tile = {1'b1, 9'd235, 10'd0, 10'd135};   // notes_W t1
        8'd178: notes_tile = {1'b1, 9'd236, 10'd0, 10'd270};   // notes_W t2
        8'd179: notes_tile = {1'b1, 9'd237, 10'd0, 10'd405};   // notes_W t3
        8'd184: notes_tile = {1'b1, 9'd238, 10'd0, 10'd50};   // notes_X t0
        8'd185: notes_tile = {1'b1, 9'd239, 10'd0, 10'd160};   // notes_X t1
        8'd186: notes_tile = {1'b1, 9'd240, 10'd0, 10'd270};   // notes_X t2
        8'd187: notes_tile = {1'b1, 9'd241, 10'd0, 10'd380};   // notes_X t3
        8'd192: notes_tile = {1'b1, 9'd242, 10'd0, 10'd51};   // notes_Y t0
        8'd193: notes_tile = {1'b1, 9'd243, 10'd0, 10'd160};   // notes_Y t1
        8'd194: notes_tile = {1'b1, 9'd244, 10'd0, 10'd269};   // notes_Y t2
        8'd195: notes_tile = {1'b1, 9'd245, 10'd0, 10'd378};   // notes_Y t3
        8'd200: notes_tile = {1'b1, 9'd246, 10'd0, 10'd76};   // notes_Z t0
        8'd201: notes_tile = {1'b1, 9'd247, 10'd0, 10'd205};   // notes_Z t1
        8'd202: notes_tile = {1'b1, 9'd248, 10'd0, 10'd334};   // notes_Z t2
        8'd208: notes_tile = {1'b1, 9'd249, 10'd0, 10'd47};   // notes_AA t0
        8'd209: notes_tile = {1'b1, 9'd250, 10'd0, 10'd158};   // notes_AA t1
        8'd210: notes_tile = {1'b1, 9'd251, 10'd0, 10'd269};   // notes_AA t2
        8'd211: notes_tile = {1'b1, 9'd252, 10'd0, 10'd380};   // notes_AA t3
        8'd216: notes_tile = {1'b1, 9'd253, 10'd0, 10'd48};   // notes_BB t0
        8'd217: notes_tile = {1'b1, 9'd254, 10'd0, 10'd159};   // notes_BB t1
        8'd218: notes_tile = {1'b1, 9'd255, 10'd0, 10'd270};   // notes_BB t2
        8'd219: notes_tile = {1'b1, 9'd256, 10'd0, 10'd381};   // notes_BB t3
        8'd224: notes_tile = {1'b1, 9'd257, 10'd0, 10'd92};   // notes_CC t0
        8'd225: notes_tile = {1'b1, 9'd258, 10'd0, 10'd210};   // notes_CC t1
        8'd226: notes_tile = {1'b1, 9'd259, 10'd0, 10'd329};   // notes_CC t2
        8'd232: notes_tile = {1'b1, 9'd260, 10'd0, 10'd21};   // notes_DD t0
        8'd233: notes_tile = {1'b1, 9'd261, 10'd0, 10'd145};   // notes_DD t1
        8'd234: notes_tile = {1'b1, 9'd262, 10'd0, 10'd269};   // notes_DD t2
        8'd235: notes_tile = {1'b1, 9'd263, 10'd0, 10'd393};   // notes_DD t3
        8'd240: notes_tile = {1'b1, 9'd264, 10'd0, 10'd20};   // notes_EE t0
        8'd241: notes_tile = {1'b1, 9'd265, 10'd0, 10'd145};   // notes_EE t1
        8'd242: notes_tile = {1'b1, 9'd266, 10'd0, 10'd270};   // notes_EE t2
        8'd243: notes_tile = {1'b1, 9'd267, 10'd0, 10'd395};   // notes_EE t3
        8'd248: notes_tile = {1'b1, 9'd268, 10'd0, 10'd76};   // notes_FF t0
        8'd249: notes_tile = {1'b1, 9'd269, 10'd0, 10'd205};   // notes_FF t1
        8'd250: notes_tile = {1'b1, 9'd270, 10'd0, 10'd334};   // notes_FF t2
        default: notes_tile = 30'd0;
    endcase
endfunction
function [19:0] notes_geo(input [4:0] pg);   // {y0, height} of the half-size page, centred vertically
    case (pg)
        5'd0: notes_geo = {10'd49, 10'd441};
        5'd1: notes_geo = {10'd77, 10'd386};
        5'd2: notes_geo = {10'd51, 10'd438};
        5'd3: notes_geo = {10'd41, 10'd458};
        5'd4: notes_geo = {10'd47, 10'd445};
        5'd5: notes_geo = {10'd67, 10'd405};
        5'd6: notes_geo = {10'd70, 10'd399};
        5'd7: notes_geo = {10'd26, 10'd488};
        5'd8: notes_geo = {10'd41, 10'd457};
        5'd9: notes_geo = {10'd73, 10'd393};
        5'd10: notes_geo = {10'd99, 10'd342};
        5'd11: notes_geo = {10'd71, 10'd398};
        5'd12: notes_geo = {10'd98, 10'd344};
        5'd13: notes_geo = {10'd20, 10'd499};
        5'd14: notes_geo = {10'd70, 10'd400};
        5'd15: notes_geo = {10'd71, 10'd397};
        5'd16: notes_geo = {10'd72, 10'd395};
        5'd17: notes_geo = {10'd39, 10'd461};
        5'd18: notes_geo = {10'd68, 10'd403};
        5'd19: notes_geo = {10'd74, 10'd392};
        5'd20: notes_geo = {10'd48, 10'd444};
        5'd21: notes_geo = {10'd48, 10'd444};
        5'd22: notes_geo = {10'd0, 10'd540};
        5'd23: notes_geo = {10'd50, 10'd440};
        5'd24: notes_geo = {10'd51, 10'd438};
        5'd25: notes_geo = {10'd76, 10'd388};
        5'd26: notes_geo = {10'd47, 10'd446};
        5'd27: notes_geo = {10'd48, 10'd444};
        5'd28: notes_geo = {10'd92, 10'd356};
        5'd29: notes_geo = {10'd21, 10'd498};
        5'd30: notes_geo = {10'd20, 10'd500};
        5'd31: notes_geo = {10'd76, 10'd388};
        default: notes_geo = {10'd50, 10'd440};
    endcase
endfunction
function [29:0] gal_tile(input [3:0] g, input [2:0] j);   // game assets: box, box_flap, tape, answer_covers, notes_covers, 4 sleeves
    case ({g, j})
        7'd0: gal_tile = {1'b1, 9'd278, 10'd0, 10'd0};   // box t0
        7'd1: gal_tile = {1'b1, 9'd279, 10'd0, 10'd135};   // box t1
        7'd2: gal_tile = {1'b1, 9'd280, 10'd0, 10'd270};   // box t2
        7'd3: gal_tile = {1'b1, 9'd281, 10'd0, 10'd405};   // box t3
        7'd8: gal_tile = {1'b1, 9'd282, 10'd0, 10'd0};   // box_flap t0
        7'd9: gal_tile = {1'b1, 9'd283, 10'd0, 10'd270};   // box_flap t1
        7'd16: gal_tile = {1'b1, 9'd284, 10'd0, 10'd0};   // tape t0
        7'd17: gal_tile = {1'b1, 9'd285, 10'd0, 10'd90};   // tape t1
        7'd18: gal_tile = {1'b1, 9'd286, 10'd0, 10'd180};   // tape t2
        7'd19: gal_tile = {1'b1, 9'd287, 10'd0, 10'd270};   // tape t3
        7'd20: gal_tile = {1'b1, 9'd288, 10'd0, 10'd360};   // tape t4
        7'd21: gal_tile = {1'b1, 9'd289, 10'd0, 10'd450};   // tape t5
        7'd24: gal_tile = {1'b1, 9'd290, 10'd0, 10'd0};   // answer_covers t0
        7'd25: gal_tile = {1'b1, 9'd291, 10'd0, 10'd180};   // answer_covers t1
        7'd26: gal_tile = {1'b1, 9'd292, 10'd0, 10'd360};   // answer_covers t2
        7'd32: gal_tile = {1'b1, 9'd293, 10'd0, 10'd0};   // notes_covers t0
        7'd33: gal_tile = {1'b1, 9'd294, 10'd0, 10'd270};   // notes_covers t1
        7'd40: gal_tile = {1'b1, 9'd295, 10'd0, 10'd0};   // sleeve_beg t0
        7'd41: gal_tile = {1'b1, 9'd296, 10'd0, 10'd270};   // sleeve_beg t1
        7'd48: gal_tile = {1'b1, 9'd297, 10'd0, 10'd0};   // sleeve_int t0
        7'd49: gal_tile = {1'b1, 9'd298, 10'd0, 10'd270};   // sleeve_int t1
        7'd56: gal_tile = {1'b1, 9'd299, 10'd0, 10'd0};   // sleeve_adv t0
        7'd57: gal_tile = {1'b1, 9'd300, 10'd0, 10'd270};   // sleeve_adv t1
        7'd64: gal_tile = {1'b1, 9'd301, 10'd0, 10'd0};   // sleeve_exp t0
        7'd65: gal_tile = {1'b1, 9'd302, 10'd0, 10'd270};   // sleeve_exp t1
        default: gal_tile = 30'd0;
    endcase
endfunction
wire [2:0] view_j    = view_need[0] ? 3'd0 : view_need[1] ? 3'd1 : view_need[2] ? 3'd2 :
                       view_need[3] ? 3'd3 : view_need[4] ? 3'd4 : 3'd5;
wire [4:0]  zk5       = g_focus_w - 5'd3;                                  // clue zoom: card under the cursor
wire [2:0]  zk        = zk5[2:0];
wire [16:0] zcard     = {12'd0, g_packet_w, 3'b000} * 17'd3 + {12'd0, zk, 2'b00} + {15'd0, g_seed_w[zk], 1'b0};
wire [29:0] map_t     = (view_j == 3'd0) ? {1'b1, 9'd271, 10'd0, 10'd0} : (view_j == 3'd1) ? {1'b1, 9'd272, 10'd0, 10'd270} : 30'd0;
wire [29:0] leaf_t    = (view_j == 3'd0) ? {1'b1, 9'd273, 10'd0,   10'd0} : (view_j == 3'd1) ? {1'b1, 9'd274, 10'd0,   10'd270} :
                        (view_j == 3'd2) ? {1'b1, 9'd275, 10'd279, 10'd0} : (view_j == 3'd3) ? {1'b1, 9'd276, 10'd279, 10'd270} :
                        (view_j == 3'd4) ? {1'b1, 9'd277, 10'd558, 10'd0} : 30'd0;
wire [8:0]  ans_a     = 9'd96 + {3'd0, g_page_w, 1'b0} + {8'd0, view_j[0]};
wire [29:0] ans_t     = (view_j < 3'd2) ? {1'b1, ans_a, 10'd113, (view_j[0] ? 10'd270 : 10'd0)} : 30'd0;
wire [29:0] zoom_t    = (view_j == 3'd0) ? {1'b1, zcard[8:0], ZOOM_X[9:0], ZOOM_Y[9:0]} : 30'd0;
wire [29:0] vt        = (g_view_w == 3'd1) ? map_t : (g_view_w == 3'd2) ? leaf_t : (g_view_w == 3'd3) ? ans_t :
                        (g_view_w == 3'd4) ? notes_tile(g_page_w, view_j) : (g_view_w == 3'd5) ? gal_tile(g_gal_w, view_j) : zoom_t;
wire        view_ok   = vt[29];
wire [16:0] view_asset = {8'd0, vt[28:20]};
wire [15:0] view_x    = {6'd0, vt[19:10]};
wire [15:0] view_y    = {6'd0, vt[9:0]};
wire        view_half = (g_view_w != 3'd6);
// endgame panel items and suspect plates
wire [2:0]  egj       = eg_need[0] ? 3'd0 : eg_need[1] ? 3'd1 : eg_need[2] ? 3'd2 : eg_need[3] ? 3'd3 : 3'd4;
wire [16:0] eg_asset  = (egj == 3'd0) ? (g_win_w ? 17'd304 : 17'd303) : (egj == 3'd1) ? 17'd307 :
                        (egj == 3'd2) ? 17'd308 : (egj == 3'd3) ? 17'd310 : 17'd309;
wire [15:0] eg_x      = (egj == 3'd0) ? 16'd512 : (egj[0] ? EGB_X0 : EGB_X1);
wire [15:0] eg_y      = (egj == 3'd0) ? 16'd8 : (egj < 3'd3) ? EGB_Y0 : EGB_Y1;
wire [3:0]  susj      = sus_need[0] ? 4'd0 : sus_need[1] ? 4'd1 : sus_need[2] ? 4'd2 : sus_need[3] ? 4'd3 :
                        sus_need[4] ? 4'd4 : sus_need[5] ? 4'd5 : sus_need[6] ? 4'd6 : sus_need[7] ? 4'd7 :
                        sus_need[8] ? 4'd8 : sus_need[9] ? 4'd9 : 4'd10;
wire [15:0] sus_y     = SUS_Y0 + {12'd0, susj} * SUS_PITCH;
wire        eg_panel  = (g_eg_w[1] == 1'b0);   // play or accusation: Map/Suspects/thumbnails live
wire        btn_j     = map_need[0] ? 1'b0 : 1'b1;
wire [15:0] btn_x     = btn_j ? (MAP_X + BTN_PITCH) : MAP_X;
wire [1:0] plate_j   = plate_need[0] ? 2'd0 : plate_need[1] ? 2'd1 : plate_need[2] ? 2'd2 : 2'd3;
wire [15:0] plate_y  = PLATE_Y0 + {14'd0, plate_j} * PLATE_PITCH;
wire [16:0] plate_asset = (g_phase_w == 2'd0) ? (A_DIFFICULTY + {15'd0, plate_j})
                                              : (A_MODE + {15'd0, plate_j} - 17'd1);   // mode plates sit in rows 1-2
wire       blit_free = !blit_inflight && (blit_req_r == blit_ack_w) && !blit_busy && (tape_frames_w != 17'd0) &&
                       pf_done && !pf_wait && !pf_refill;
always @(posedge CLK_40M) begin
    pf_refill <= 1'b0;
    if (reset) begin
        ph_q <= 2'd3; plate_need <= 4'd0; card_need <= 6'd0; cards_q <= 6'd0; pf_wait <= 1'b0;
        cm_q <= 2'd0; face_need <= 2'd0; zoom_need <= 1'b0;
        map_need <= 2'd0; map_drawn <= 1'b0; blit_cm_q <= 1'b0;
        view_need <= 6'd0; view_q <= 3'd0; view_close <= 1'b0;
        gal_q <= 4'd0; eg_q <= 2'd0; eg_need <= 5'd0; sus_need <= 11'd0;
        closed_v <= 3'd0; verdict_pend <= 1'b0;
        retry_pend <= 1'b0; retry_cnt <= 2'd0;
        cm_post <= 1'b0; cm_post_hold <= 1'b0; cm_post_tmr <= 28'd0;
        blit_inflight <= 1'b0; blit_busy_q <= 1'b0; blit_wait_tmr <= 28'd0;
    end else begin
        ph_q <= g_phase_w; cards_q <= cards_revealed_w; cm_q <= g_cm_w;
        blit_busy_q <= blit_busy;
        if (blit_inflight) blit_wait_tmr <= blit_wait_tmr + 28'd1;
        if (blit_busy_q && !blit_busy) blit_inflight <= 1'b0;                       // its decode finished
        if (blit_busy_q && !blit_busy && !blit_ok && retry_cnt != 2'd3) begin      // ...or failed: redo it
            retry_pend <= 1'b1;  retry_cnt <= retry_cnt + 2'd1;
        end
        if (!blit_busy && blit_wait_tmr == 28'hFFFFFFF) blit_inflight <= 1'b0;      // never started
        if (pf_wait && !pf_done) pf_wait <= 1'b0;
        card_need <= need_now;
        if (blit_free && retry_pend) begin
            blit_req_r    <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0;
            retry_pend    <= 1'b0;
        end else if (blit_free && zoom_need) begin
            blit_frame_r <= tape_frames_w + zoom_asset;
            blit_base_r  <= PANEL_BASE_HW + ZOOM_Y * CANVAS_W + {11'd0, ZOOM_X};
            blit_dx_r    <= ZOOM_X;  blit_dy_r <= ZOOM_Y;
            blit_half_r  <= 1'b0;
            blit_req_r   <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b1;
            zoom_need    <= 1'b0;
        end else if (blit_free && face_need != 2'd0) begin
            blit_frame_r <= tape_frames_w + face_asset;
            blit_base_r  <= PANEL_BASE_HW + FACE_Y * CANVAS_W + {11'd0, face_x};
            blit_dx_r    <= face_x;  blit_dy_r <= FACE_Y;
            blit_half_r  <= 1'b1;
            blit_req_r   <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b1;
            face_need    <= face_need & ~(2'd1 << face_j);
        end else if (blit_free && view_need != 6'd0) begin
            if (view_ok) begin   // a view's tile; slots past its last tile are just cleared
                blit_frame_r <= tape_frames_w + view_asset;
                blit_base_r  <= PANEL_BASE_HW + view_y * CANVAS_W + {11'd0, view_x};
                blit_dx_r    <= view_x;  blit_dy_r <= view_y;
                blit_half_r  <= view_half;
                blit_req_r   <= ~blit_req_r;
                blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b1;
            end
            view_need    <= view_need & ~(6'd1 << view_j);
        end else if (blit_free && g_view_w == 3'd0 && !view_close && !verdict_pend && eg_need != 5'd0) begin
            blit_frame_r <= tape_frames_w + eg_asset;
            blit_base_r  <= PANEL_BASE_HW + eg_y * CANVAS_W + {11'd0, eg_x};
            blit_dx_r    <= eg_x;  blit_dy_r <= eg_y;
            blit_half_r  <= 1'b1;
            blit_req_r   <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b0;
            eg_need      <= eg_need & ~(5'd1 << egj);
        end else if (blit_free && g_view_w == 3'd0 && !view_close && sus_need != 11'd0) begin
            blit_frame_r <= tape_frames_w + A_SUSPECT + {13'd0, susj};
            blit_base_r  <= PANEL_BASE_HW + sus_y * CANVAS_W + {11'd0, SUS_X};
            blit_dx_r    <= SUS_X;  blit_dy_r <= sus_y;
            blit_half_r  <= 1'b1;
            blit_req_r   <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b1;
            sus_need     <= sus_need & ~(11'd1 << susj);
        end else if (blit_free && !in_menu && eg_panel && g_view_w == 3'd0 && !view_close && map_need != 2'd0) begin
            blit_frame_r <= tape_frames_w + A_BTN_MAP + {16'd0, btn_j};
            blit_base_r  <= PANEL_BASE_HW + MAP_Y * CANVAS_W + {11'd0, btn_x};
            blit_dx_r    <= btn_x;  blit_dy_r <= MAP_Y;
            blit_half_r  <= 1'b1;
            blit_req_r   <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b0;
            map_need     <= map_need & ~(2'd1 << btn_j);
        end else if (blit_free && in_menu && plate_need != 4'd0) begin
            blit_frame_r <= tape_frames_w + plate_asset;
            blit_base_r  <= PANEL_BASE_HW + plate_y * CANVAS_W + {11'd0, PLATE_X};
            blit_dx_r    <= PLATE_X;  blit_dy_r <= plate_y;
            blit_half_r  <= 1'b1;
            blit_req_r   <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b0;
            plate_need   <= plate_need & ~(4'd1 << plate_j);
        end else if (blit_free && !in_menu && eg_panel && g_view_w == 3'd0 && !view_close && need_now != 6'd0) begin
            blit_frame_r <= tape_frames_w + thumb_asset;
            blit_base_r  <= slot_base;  blit_dx_r <= slot_x;  blit_dy_r <= slot_y;
            blit_half_r  <= 1'b1;
            blit_req_r   <= ~blit_req_r;
            blit_inflight <= 1'b1; blit_wait_tmr <= 28'd0; retry_cnt <= 2'd0; blit_cm_q <= 1'b0;
            card_need    <= need_now & ~(6'd1 << need_k);
        end
        // After B the tape jumps to the next segment and the display holds its last decoded frame
        // (clue footage) until that seek primes. Keep the zoomed card up until the hold is over.
        if (cm_q != 2'd0 && g_cm_w == 2'd0) begin
            cm_post <= 1'b1; cm_post_hold <= 1'b0; cm_post_tmr <= 28'd0;
        end else if (cm_post) begin
            cm_post_tmr <= cm_post_tmr + 28'd1;
            if (fb_seek_hold) cm_post_hold <= 1'b1;
            if ((cm_post_hold && !fb_seek_hold) || cm_post_tmr == 28'd150_000_000 || in_menu) cm_post <= 1'b0;
        end
        // card moment changes: choose -> both faces; zoom -> the chosen face, full size
        if (g_cm_w != cm_q) begin
            face_need <= (g_cm_w == 2'd1) ? 2'b11 : 2'b00;
            zoom_need <= (g_cm_w == 2'd2);
            if (cm_q == 2'd0 && !map_drawn) begin map_need <= 2'b11; map_drawn <= 1'b1; end
        end
        // a new menu screen: repaint, then all of its plates (after the issue block so it wins)
        if (g_phase_w != ph_q && in_menu) begin
            pf_refill  <= 1'b1; pf_wait <= 1'b1;
            plate_need <= (g_phase_w == 2'd0) ? 4'b1111 : 4'b0110;
            card_need  <= 6'd0; face_need <= 2'd0; zoom_need <= 1'b0;
            map_need   <= 2'd0; map_drawn <= 1'b0;
            eg_need    <= 5'd0; sus_need <= 11'd0;
        end
        // A view opened (or the game-assets item changed): draw its tiles. Closed: the answer page and
        // the clue zoom only covered the video column, so just the suspect plates (if showing) come back;
        // anything wider repaints the panel and redraws what the current phase shows there.
        view_q <= g_view_w;  gal_q <= g_gal_w;
        if (g_view_w != view_q || (g_view_w == 3'd5 && g_gal_w != gal_q)) begin
            view_need  <= (g_view_w != 3'd0) ? 6'b111111 : 6'b000000;
            if (g_view_w == 3'd0) begin view_close <= 1'b1; closed_v <= view_q; end
        end
        if (view_close && !blit_inflight && g_view_w == 3'd0) begin
            view_close <= 1'b0;
            if (closed_v != 3'd3 && closed_v != 3'd6) begin
                pf_refill  <= 1'b1; pf_wait <= 1'b1;
                if (eg_panel) begin
                    card_need <= cards_revealed_w;
                    if (map_drawn) map_need <= 2'b11;
                end else
                    eg_need <= (g_eg_w == 2'd3) ? 5'b11111 : 5'b00111;
            end
            if (g_eg_w == 2'd1) sus_need <= 11'h7FF;
        end
        // Endgame: the accusation draws the suspect plates; the verdict clears the panel for the banner
        // and Full Answer / Baley's Notes; the end adds Play Again / Game Assets.
        eg_q <= g_eg_w;
        if (g_eg_w != eg_q) begin
            if (g_eg_w == 2'd1) sus_need <= 11'h7FF;
            if (g_eg_w == 2'd2) begin
                verdict_pend <= 1'b1;
                sus_need  <= 11'd0;  card_need <= 6'd0;  map_need <= 2'd0;
            end
            if (g_eg_w == 2'd3) eg_need <= eg_need | 5'b11000;
        end
        if (verdict_pend && !blit_inflight) begin
            verdict_pend <= 1'b0;
            pf_refill <= 1'b1; pf_wait <= 1'b1;
            eg_need   <= eg_need | 5'b00111;
        end
    end
end

// Menu selection border: 6 px around the selected plate, drawn at scanout once the screen is complete.
wire [1:0] sel_row   = (g_phase_w == 2'd0) ? g_packet_w : {1'b0, g_pick_w} + 2'd1;
wire [15:0] sel_y    = PLATE_Y0 + {14'd0, sel_row} * PLATE_PITCH;
wire       menu_ready = in_menu && plate_need == 4'd0 && pf_done && !pf_wait && !blit_inflight && !retry_pend;
wire       in_outer  = (rr_hpos + 16'd6 >= PLATE_X) && (rr_hpos < PLATE_X + PLATE_W + 16'd6) &&
                       (rr_vpos + 16'd6 >= sel_y)   && (rr_vpos < sel_y + PLATE_H + 16'd6);
wire       in_inner  = (rr_hpos >= PLATE_X) && (rr_hpos < PLATE_X + PLATE_W) &&
                       (rr_vpos >= sel_y)   && (rr_vpos < sel_y + PLATE_H);
wire       sel_px    = menu_ready && in_outer && !in_inner;

// Card moment: the whole 512-wide video column is packet colour except the card art, which is
// revealed only once drawn; in choose mode a white border marks the face under the cursor.
wire       cm_on     = (disp_cm != 2'd0) && (rr_hpos < 16'd512);
// A request the streamer has not taken yet also holds the reveal (it can wait out a post-seek audio refill).
wire       blit_pend = (blit_req_r != blit_ack_w);
// Original: wire cm_ready = !zoom_need && face_need == 2'd0 && !(blit_inflight && blit_cm_q);
wire       cm_ready  = !zoom_need && face_need == 2'd0 && !((blit_inflight || blit_pend || retry_pend) && blit_cm_q);
wire       in_zoom   = (rr_hpos >= ZOOM_X) && (rr_hpos < ZOOM_X + ZOOM_W) && (rr_vpos >= ZOOM_Y) && (rr_vpos < ZOOM_Y + ZOOM_H);
wire       in_face0  = (rr_hpos >= FACE_X0) && (rr_hpos < FACE_X0 + FACE_W) && (rr_vpos >= FACE_Y) && (rr_vpos < FACE_Y + FACE_H);
wire       in_face1  = (rr_hpos >= FACE_X1) && (rr_hpos < FACE_X1 + FACE_W) && (rr_vpos >= FACE_Y) && (rr_vpos < FACE_Y + FACE_H);
wire [15:0] cur_x    = g_cm_sel_w ? FACE_X1 : FACE_X0;
wire       in_cur_o  = (rr_hpos + 16'd6 >= cur_x) && (rr_hpos < cur_x + FACE_W + 16'd6) &&
                       (rr_vpos + 16'd6 >= FACE_Y) && (rr_vpos < FACE_Y + FACE_H + 16'd6);
wire       cm_art    = cm_ready && ((disp_cm == 2'd2) ? in_zoom : (in_face0 || in_face1));
wire       cm_border = cm_ready && (g_cm_w == 2'd1) && in_cur_o && !cm_art;
wire [23:0] pk_rgb   = (g_packet_w == 2'd0) ? 24'h2E9E44 :      // Beginner green
                       (g_packet_w == 2'd1) ? 24'hF2D02A :      // Intermediate yellow
                       (g_packet_w == 2'd2) ? 24'hC82A2A :      // Advanced red
                                              24'h222222;       // Expert black
wire [23:0] cm_rgb   = cm_border ? 24'hFFFFFF : pk_rgb;
wire       cm_fill   = cm_on && !cm_art;
// Original: assign comp_r = sel_px ? 8'hFF : rr_r;  (and _g/_b)
// During play the column strips above/below the video are plain background (they hold stale card art).
// Scanout overlay (2026-09-25), priority: card moment > open view > accusation column > play.
//   view      : its art rect shows the panel buffer once every tile is drawn (background until then);
//               the rest of the video column is packet colour
//   accusation: the video column is packet colour with the suspect plates; the plate under the cursor
//               gets a border, red/white pulsing once armed
//   play      : column strips, menu selection border, panel cursor border
// Previous version kept below (commented) for reference.
// // Study view: background until every tile is drawn, then the panel buffer (video is off).
// wire       view_ready = (view_need == 5'd0) && !(blit_inflight && blit_cm_q);
// wire [15:0] view_w    = (g_view_w == 2'd1) ? 16'd586 : 16'd837;
// wire       view_on   = (g_view_w != 2'd0) && (rr_hpos < view_w) && (rr_vpos < 16'd540);
// wire       view_fill = view_on && !view_ready;
// // Panel cursor: 6 px white border around the focused button or card thumbnail.
// wire [15:0] foc_x    = (g_focus_w == 4'd1) ? MAP_X : (g_focus_w == 4'd2) ? (MAP_X + BTN_PITCH) :
//                        (g_focus_w == 4'd3 || g_focus_w == 4'd6) ? SLOT_X0 :
//                        (g_focus_w == 4'd4 || g_focus_w == 4'd7) ? SLOT_X1 : SLOT_X2;
// wire [15:0] foc_y    = (g_focus_w < 4'd3) ? MAP_Y : (g_focus_w < 4'd6) ? SLOT_Y0 : SLOT_Y1;
// wire [15:0] foc_w    = (g_focus_w < 4'd3) ? 16'd213 : 16'd140;
// wire [15:0] foc_h    = (g_focus_w < 4'd3) ? 16'd70  : 16'd161;
// wire       foc_o     = (rr_hpos + 16'd6 >= foc_x) && (rr_hpos < foc_x + foc_w + 16'd6) &&
//                        (rr_vpos + 16'd6 >= foc_y) && (rr_vpos < foc_y + foc_h + 16'd6);
// wire       foc_i     = (rr_hpos >= foc_x) && (rr_hpos < foc_x + foc_w) && (rr_vpos >= foc_y) && (rr_vpos < foc_y + foc_h);
// wire       foc_px    = (g_focus_w != 4'd0) && (g_view_w == 2'd0) && (disp_cm == 2'd0) && !in_menu && foc_o && !foc_i;
// // Original: wire strip_px = !in_menu && !cm_on && (rr_hpos < 16'd512) && ...
// wire       strip_px  = !in_menu && !cm_on && (g_view_w == 2'd0) && (rr_hpos < 16'd512) && ((rr_vpos < 16'd30) || (rr_vpos >= 16'd510) && (rr_vpos < 16'd540));
// // Original: assign comp_r = cm_fill ? cm_rgb[23:16] : strip_px ? 8'h10 : sel_px ? 8'hFF : rr_r;
// // assign comp_r = cm_fill ? cm_rgb[23:16] : (strip_px || view_fill) ? 8'h10 : (sel_px || foc_px) ? 8'hFF : rr_r;
// // assign comp_g = cm_fill ? cm_rgb[15:8]  : (strip_px || view_fill) ? 8'h14 : (sel_px || foc_px) ? 8'hFF : rr_g;
// // assign comp_b = cm_fill ? cm_rgb[7:0]   : (strip_px || view_fill) ? 8'h18 : (sel_px || foc_px) ? 8'hFF : rr_b;
reg  [24:0] blink_ctr = 25'd0;
always @(posedge CLK_40M) blink_ctr <= blink_ctr + 25'd1;
wire        blink     = blink_ctr[24];
wire        col       = (rr_hpos < 16'd512);
wire        view_act  = (g_view_w != 3'd0) && !in_menu;
wire        view_ready = (view_need == 6'd0) && !((blit_inflight || blit_pend || retry_pend) && blit_cm_q);
wire [19:0] ngeo      = notes_geo(g_page_w);
wire [15:0] va_x      = (g_view_w == 3'd3) ? 16'd113 : (g_view_w == 3'd6) ? ZOOM_X : 16'd0;
wire [15:0] va_y      = (g_view_w == 3'd4) ? {6'd0, ngeo[19:10]} : (g_view_w == 3'd6) ? ZOOM_Y : 16'd0;
wire [15:0] va_w      = (g_view_w == 3'd1) ? 16'd586 : (g_view_w == 3'd2) ? 16'd837 :
                        (g_view_w == 3'd3) ? 16'd285 : (g_view_w == 3'd6) ? ZOOM_W : 16'd960;
wire [15:0] va_h      = (g_view_w == 3'd4) ? {6'd0, ngeo[9:0]} : (g_view_w == 3'd6) ? ZOOM_H : 16'd540;
wire        in_va     = (rr_hpos >= va_x) && (rr_hpos < va_x + va_w) && (rr_vpos >= va_y) && (rr_vpos < va_y + va_h);
// accusation
function in_plate(input [31:0] dy);   // dy inside one of the 11 plates (44 rows each, pitch 46)
    integer k;
    begin
        in_plate = 1'b0;
        for (k = 0; k < 11; k = k + 1)
            if (dy >= 46 * k && dy < 46 * k + 44) in_plate = 1'b1;
    end
endfunction
wire        acc_on    = (g_eg_w == 2'd1) && !view_act && !in_menu && col;
wire        sus_ready = (sus_need == 11'd0) && !((blit_inflight || blit_pend || retry_pend) && blit_cm_q);
wire [15:0] sdy       = rr_vpos - SUS_Y0;
wire        sus_plate = sus_ready && (rr_hpos >= SUS_X) && (rr_hpos < SUS_X + SUS_W) && (rr_vpos >= SUS_Y0) && in_plate({16'd0, sdy});
wire        sus_foc   = (g_focus_w >= 5'd9) && (g_focus_w <= 5'd19);
wire [4:0]  sfk       = g_focus_w - 5'd9;
wire [15:0] sfy       = SUS_Y0 + {11'd0, sfk} * SUS_PITCH;
wire        sus_bo    = sus_ready && sus_foc &&
                        (rr_hpos + 16'd2 >= SUS_X) && (rr_hpos < SUS_X + SUS_W + 16'd2) &&
                        (rr_vpos + 16'd2 >= sfy) && (rr_vpos < sfy + SUS_H + 16'd2) &&
                        !((rr_hpos >= SUS_X) && (rr_hpos < SUS_X + SUS_W) && (rr_vpos >= sfy) && (rr_vpos < sfy + SUS_H));
wire [23:0] sus_bc    = (g_armed_w && blink) ? 24'hE02020 : 24'hFFFFFF;
// panel cursor border: Map/Suspects, card thumbnails, endgame buttons
wire        foc_eg    = (g_focus_w >= 5'd20);
wire [15:0] foc_x     = foc_eg ? (g_focus_w[0] ? EGB_X1 : EGB_X0) :
                        (g_focus_w == 5'd1) ? MAP_X : (g_focus_w == 5'd2) ? (MAP_X + BTN_PITCH) :
                        (g_focus_w == 5'd3 || g_focus_w == 5'd6) ? SLOT_X0 :
                        (g_focus_w == 5'd4 || g_focus_w == 5'd7) ? SLOT_X1 : SLOT_X2;
wire [15:0] foc_y     = foc_eg ? (g_focus_w[1] ? EGB_Y1 : EGB_Y0) :
                        (g_focus_w < 5'd3) ? MAP_Y : (g_focus_w < 5'd6) ? SLOT_Y0 : SLOT_Y1;
wire [15:0] foc_w     = (foc_eg || g_focus_w < 5'd3) ? 16'd213 : 16'd140;
wire [15:0] foc_h     = (foc_eg || g_focus_w < 5'd3) ? 16'd70  : 16'd161;
wire        foc_o     = (rr_hpos + 16'd6 >= foc_x) && (rr_hpos < foc_x + foc_w + 16'd6) &&
                        (rr_vpos + 16'd6 >= foc_y) && (rr_vpos < foc_y + foc_h + 16'd6);
wire        foc_i     = (rr_hpos >= foc_x) && (rr_hpos < foc_x + foc_w) && (rr_vpos >= foc_y) && (rr_vpos < foc_y + foc_h);
wire        foc_item  = ((g_focus_w >= 5'd1) && (g_focus_w <= 5'd8)) || foc_eg;
wire        foc_px    = foc_item && !view_act && (disp_cm == 2'd0) && !in_menu && foc_o && !foc_i &&
                        !(foc_eg && eg_need != 5'd0);   // endgame buttons: border once they are drawn
wire        strip_px  = !in_menu && !cm_on && !view_act && (g_eg_w != 2'd1) && col &&
                        ((rr_vpos < 16'd30) || (rr_vpos >= 16'd510) && (rr_vpos < 16'd540));
wire [23:0] BG_RGB    = 24'h101418;
wire [23:0] rr_rgb    = {rr_r, rr_g, rr_b};
wire [23:0] comp_rgb  = cm_fill  ? cm_rgb :
                        view_act ? (in_va ? (view_ready ? rr_rgb : BG_RGB) : col ? pk_rgb : rr_rgb) :
                        acc_on   ? (sus_bo ? sus_bc : sus_plate ? rr_rgb : pk_rgb) :
                        strip_px ? BG_RGB :
                        (sel_px || foc_px) ? 24'hFFFFFF : rr_rgb;
assign comp_r = comp_rgb[23:16];
assign comp_g = comp_rgb[15:8];
assign comp_b = comp_rgb[7:0];

reg  [2:0]  fb_prime_cnt;
reg  [27:0]  fb_seek_tmr;
reg         fb_wr_stale;   // frame decoding when the seek hit -> finish it, but never publish it
// ⚠️ SAFETY TIMEOUT IS NON-NEGOTIABLE. An unbounded "wait until buffers fill" is a brand-new
// hard-lock source -- exactly the class of bug removed from this core (fill_idle/ddram). The
// timer is NOT re-zeroed by a further seek while already holding, so a burst of seeks cannot keep
// the hold alive indefinitely: the bound is measured from the FIRST seek of the burst.
wire fb_seek_release = (fb_prime_cnt >= SEEK_PRIME && fb_aud_primed) || (fb_seek_tmr >= SEEK_TMO);

reg        rr_vblank_q;
wire       fb_vbl_rise = rr_vblank & ~rr_vblank_q;

// Adoption and completion can land on the SAME cycle, so the free-buffer choice must be made
// against the buffer that will be displayed AFTER this cycle -- not the current one. Using the
// stale fb_disp_idx there would pick exactly the buffer vblank is about to start displaying.
wire       fb_adopt    = fb_vbl_rise & fb_have_new & ~fb_seek_hold;   // SEEK-HOLD: freeze display
wire [1:0] fb_next_disp = fb_adopt ? fb_ready_idx : fb_disp_idx;
// the one index that is neither a nor b (0+1+2=3; valid because the invariant keeps them distinct)
wire [1:0] fb_free_idx  = 2'd3 - fb_wr_idx - fb_next_disp;

always @(posedge CLK_40M) begin
    rr_vblank_q <= rr_vblank;
    if (reset) begin
        fb_wr_idx    <= 2'd0;
        fb_disp_idx  <= 2'd1;
        fb_ready_idx <= 2'd1;
        fb_have_new  <= 1'b0;
        rr_vblank_q  <= 1'b0;
        fb_seek_q    <= 1'b0;
        fb_seek_hold <= 1'b0;      // SEEK-HOLD-2026-07-20
        fb_prime_cnt <= 3'd0;
        fb_seek_tmr  <= 28'd0;
        fb_wr_stale  <= 1'b0;
    end else begin
        fb_seek_q <= fb_seek_pulse;   // SEEK-HOLD-2026-07-20
        // start of vblank: adopt the newest completed frame, if any
        if (fb_adopt) begin
            fb_disp_idx <= fb_ready_idx;
            fb_have_new <= 1'b0;
        end
        // decoder finished: publish it, move writing to the free buffer.
        // Ordered AFTER the adopt block so its fb_have_new<=1'b1 wins on a simultaneous cycle
        // (we adopted the old ready, and this newly finished frame is immediately pending).
        // Original: if (dec_frame_done) begin   -- a blit decode is not a video frame
        if (dec_frame_done && !fetch_blit_w) begin
            fb_ready_idx <= fb_wr_idx;
            fb_wr_idx    <= fb_free_idx;   // != fb_next_disp by construction
            // SEEK-HOLD: a frame that was mid-decode when the seek hit is from the OLD disc
            // position -- let it finish into its buffer, but never publish it.
            fb_have_new  <= ~fb_wr_stale;
            fb_wr_stale  <= 1'b0;
            // bank post-seek frames (a stale one does not count toward priming)
            if (fb_seek_hold && !fb_wr_stale && fb_prime_cnt < SEEK_PRIME)
                fb_prime_cnt <= fb_prime_cnt + 3'd1;
        end
        // SEEK-HOLD: run the safety timer and release once primed (or on timeout)
        if (fb_seek_hold) begin
            if (fb_seek_tmr < SEEK_TMO) fb_seek_tmr <= fb_seek_tmr + 28'd1;
            if (fb_seek_release)        fb_seek_hold <= 1'b0;
        end
        // SEEK-HOLD: arm. LAST so it wins any coincidence -- a frame completing on the same cycle
        // as a seek was decoded BEFORE it, so it is stale too. Note fb_seek_tmr is only zeroed
        // when NOT already holding (see the safety note above).
        if (fb_seek_edge) begin
            fb_have_new  <= 1'b0;              // drop the frame waiting to be displayed
            // STILL-FRAME-FIX-2026-07-25: original below, uncomment (and delete the line under it)
            // to restore.  BUG: fb_wr_stale was tagged UNCONDITIONALLY on every seek, whether or
            // not a decode was actually in flight.  It is cleared only by the next dec_frame_done,
            // and that same completion does `fb_have_new <= ~fb_wr_stale`.  On a SEEK-TO-STILL the
            // disc parks (M_STOP) so vid_target is CONSTANT, the REDUNDANT-REDRAW-FIX gate
            // (dlv_streamer.v:721) fetches exactly ONE frame, and that one frame therefore always
            // absorbed the stale tag: never published (fb_have_new stuck 0), and fb_prime_cnt never
            // left 0 either (its guard is !fb_wr_stale).  Display stayed frozen on the PRE-SEEK
            // buffer for the whole hold -- black whenever the previous scene faded out.  Stills only
            // ever appeared when the watchdog (dlv_streamer.v:893) happened to force a re-fetch.
            // fb_wr_stale  <= 1'b1;              // and tag the one still decoding
            // INFLIGHT-FIX-2026-07-25: ~dec_idle alone was WRONG -- frame_fetch holds the decoder in
            // reset for the WHOLE SD read (dlv_streamer.v:747 set, :779 cleared only after every
            // sector is in), so dec_idle reads 1 (idle) for ~40-100 ms of the frame's life and a seek
            // landing there left the in-flight frame untagged => it published = the "one spare frame"
            // (HW 2026-07-25). dec_reset_w = reset|frame_fetch|wd_rst covers the fetch phase.
            // Residual hole: frame_fetch drops at :779 but dec_idle stays 1 until img_start_i (JPEG
            // header parse, ~10-50 us = ~0.1% of a 41.8 ms frame). Revert = restore the line below.
            // fb_wr_stale  <= ~dec_idle;         // only tag a frame that is ACTUALLY mid-decode
            fb_wr_stale  <= ~dec_idle | dec_reset_w;   // tag anything IN FLIGHT: fetching or decoding
            fb_seek_hold <= 1'b1;
            fb_prime_cnt <= 3'd0;
            if (!fb_seek_hold) fb_seek_tmr <= 28'd0;
        end
    end
end

wire [26:0] fb_wr_base = (fb_wr_idx   == 2'd0) ? FB_BUF0_HW :
                         (fb_wr_idx   == 2'd1) ? FB_BUF1_HW : FB_BUF2_HW;
wire [26:0] fb_rd_base = (fb_disp_idx == 2'd0) ? FB_BUF0_HW :
                         (fb_disp_idx == 2'd1) ? FB_BUF1_HW : FB_BUF2_HW;

// RES-512x480-2026-07-24: geometry now passed explicitly instead of relying on the module's
// 320x240 defaults -- CLEAR_ROWS especially, which would otherwise clear only the top half of each
// buffer and leave the rest as uninitialised DDR. ORIGINAL: fb_writer #(.STRIDE_HW(16'd320)) fb_wr (
fb_writer #(
    .STRIDE_HW (FB_COLS_HW),
    .FB_COLS   (FB_COLS_HW),
    .FB_ROWS   (FB_ROWS_HW),
    .CLEAR_ROWS(FB_ROWS_HW),
    .COALESCE  (1'b0), // Disabled!
    .PANEL_STRIDE(CANVAS_W)
) fb_wr (
    .clk(CLK_40M), .reset(reset),
    .px_we(dec_px_we), .px_x(dec_px_x), .px_y(dec_px_y),
    .px_r(dec_px_r), .px_g(dec_px_g), .px_b(dec_px_b),
    .px_ready(dec_px_ready),
    .fill_idle(rr_fill_idle),       // WRITE-GATE-2026-07-16: yield DDR while the raster reader fetches (delete on revert)
    // Original: .base_hw(fb_wr_base),
    .base_hw(fetch_blit_w ? blit_base_a : fb_wr_base),
    .panel(fetch_blit_w), .half(blit_half_a), .clip_w(blit_clip_w), .clip_h(blit_clip_h),
    .wraddr(fb_wraddr), .din(fb_din),
    .din64(fb_din64), .be64(fb_be64),   // WRITE-STAGE-A-2026-07-20
    .we_req(fb_we_req), .we_ack(fb_we_ack)
);

// Panel background. TEMPORARY test grid until a real panel background asset exists.
wire [27:1] pf_addr;
wire [15:0] pf_din;
wire  [1:0] pf_be;
wire        pf_we, pf_req, pf_ack;
fb_panel_fill #(.W(CANVAS_W), .H(CANVAS_H), .BASE(PANEL_BASE_HW)) panel_fill (
    .clk(CLK_40M), .reset(reset), .refill(pf_refill),
    .r_addr(pf_addr), .r_din(pf_din), .r_be(pf_be), .r_we(pf_we),
    .r_req(pf_req), .r_ack(pf_ack), .done(pf_done)
);

fb_ddr fb_ddr_i (
    .clk(CLK_40M),
    .DDRAM_BUSY(DDRAM_BUSY),
    .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT),
    .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN),
    .DDRAM_BE(DDRAM_BE),
    .DDRAM_WE(DDRAM_WE),
    // word writes (fb_writer)
    .wraddr(fb_wraddr), .din64(fb_din64), .be64(fb_be64),
    .we_req(fb_we_req), .we_ack(fb_we_ack),
    // line-burst reads (raster reader)
    .lr_addr(rr_lr_addr), .lr_len(rr_lr_len), .lr_req(rr_lr_req), .lr_ack(rr_lr_ack),
    .lr_data(rr_lr_data), .lr_valid(rr_lr_valid),
    // random halfword port — panel filler
    .rdaddr(pf_addr), .dout(), .rom_din(pf_din), .rom_be(pf_be),
    .rom_we(pf_we), .rom_req(pf_req), .rom_ack(pf_ack)
);

// Read the framebuffer back in scan order, then composite the LED band over it.
// LAYOUT-2026-07-04: reserve top BAND_H rows for the LED band, video below.
// RES-512x480-2026-07-24: geometry + pixel-clock divider passed explicitly.
//   raster = (512+8+32+24) x (480+12+8+4+16) = 576 x 520
//   ce_pix = clk/2  ->  576*520*2 = 599,040 cyc = 14.98 ms = 66.8 Hz, safely above the 23.938 fps
//   content rate. clk/8 would be 16.7 Hz here -- BELOW content rate, dropping frames at the display.
// ⚠️ CE_DIV_LOG2 is the BANDWIDTH DIAL: DDR read traffic scales directly with refresh. If 512x480
// starves, set 3'd2 (clk/4 = 33.4 Hz, still above content rate) to halve reads before changing
// anything structural. ORIGINAL: fb_raster_reader #(.V_BAND(BAND_H)) rr (
// ORIGINAL (512x480 raster, band strip on top): .H_ACT(FB_COLS_HW) .V_ACT(FB_ROWS_HW) .STRIDE(FB_COLS_HW)
//   .V_BAND(BAND_H) .CE_DIV_LOG2(3'd3) .H_BP(16'd237) .V_BP(16'd16)
// 960x540 canvas: pixel = 100/4 = 25 MHz, 1152 x 724 total -> 29.9749 Hz (ratio 1.00016 to film),
// 46.08 us/line -- the V_TOTAL and line time this core already ran at 100 MHz. LED band sits in the
// 30-row strip above the video, so no V_BAND.
fb_raster_reader #(
    .H_ACT      (CANVAS_W),
    .V_ACT      (CANVAS_H),
    .STRIDE     (FB_COLS_HW),
    .V_BAND     (16'd0),
    .VID_X      (VID_X),
    .VID_Y      (VID_Y),
    .VID_W      (FB_COLS_HW),
    .VID_H      (FB_ROWS_HW),
    .BG         (CANVAS_BG),
    .BURST      (8'd16),            // HPS f2sdram wedges on 128-word read bursts; 16 is proven
    .PANEL_EN   (1'b1),
    .PANEL_BASE (PANEL_BASE_HW),
    // RES-512x480-FIX-2026-07-24: was 3'd1 (clk/2, 66.8 Hz). HW result: **bottom of the picture cut
    // off** -- the classic fill-stall signature. The reader must fetch H_ACT/4 = 128 words inside ONE
    // line-time; at clk/2 that is 576*2 = 1152 cycles = only 9 cycles per DDR request, which it
    // cannot make. It then misses the h_last swap, repeats the line, `fline` falls behind `vcnt`,
    // and the bottom of the framebuffer is never scanned out. (Same mechanism as the 2026-07-15
    // "progressive vertical stretch, mild at top / severe at bottom" -- that was DDR contention,
    // this is line rate.) Per FRAME the bandwidth is fine (61,440 requests in 599,040 cycles); it is
    // purely the per-LINE deadline.
    // clk/4 -> 576*4 = 2304 cyc/line = 18 cycles per request, and 33.4 Hz is still above the
    // 23.938 fps content rate. Also halves DDR read traffic (5.57 M/s -> 3.52 M/s).
    // CLK-100M-BOUNCE-2026-08-15: 2 -> 3. Holding 29.97 Hz at 100 MHz with CE=2
    // needed V_TOTAL 1448 for a 512-line image -- 65% vertical blanking, a mode the
    // scaler struggles to lock, which shows up as the picture BOUNCING. Dividing the
    // pixel clock instead restores a normal shape: V_TOTAL 724, i.e. essentially
    // DL's HW-proven 725. Also gives the DDR MORE cycles per line (4608 vs 2304),
    // on top of the 2.5x faster memory clock.
    // .CE_DIV_LOG2(3'd3),   // ORIGINAL
    .CE_DIV_LOG2(3'd2),

    // ---- CADENCE-FIX-2026-07-24 ------------------------------------------------------------
    // SYMPTOM this addresses (user, on Space Ace): "the graphics are very jumpy" -- specifically
    // a LURCHING CADENCE of otherwise-correct footage (not corrupt frames, not wrong scenes).
    //
    // A new film frame can only become visible at the start of a display scan, so what matters is
    // refresh / film_rate.  refresh = 40e6 / (2^CE_DIV_LOG2 * H_TOTAL * V_TOTAL), where
    // H_TOTAL = H_ACT+H_FP+H_SYNC+H_BP and V_TOTAL = V_ACT+V_BAND+V_FP+V_SYNC+V_BP:
    //   BEFORE (320x240, BAND_H=12, clk/8): 384*280  -> 46.503 Hz = 1.9427x  =~ 2  -> every film
    //       frame got exactly TWO refreshes; even cadence, one mild hitch every ~17 frames. SMOOTH.
    //   AFTER  (512x480, BAND_H=20, clk/4): 576*528  -> 32.881 Hz = 1.3736x -> 41.774 ms of content
    //       against a 30.413 ms refresh means frames alternate ONE and TWO refreshes, i.e. on-screen
    //       durations of 30.4 / 60.8 ms -- a 2:1 swing about 3 times per 8 film frames (~9 Hz).
    //       That is the lurch.  The resolution change did this; it is NOT Space Ace specific.
    // clk/2 (66.8 Hz, 2.789x) is not available -- it already failed on HW (per-LINE deadline, see
    // RES-512x480-FIX above), and 2x the film rate (47.876 Hz) needs clk/2-class rates too:
    // at clk/4 it would need H_TOTAL*V_TOTAL = 208,878 < the 512*500 = 256,000 active pixels.
    //
    // So the only integer ratio reachable at clk/4 is 1:1 -- ONE refresh per film frame, which is
    // the ideal presentation for film content (zero judder by construction).  Pure BLANKING change:
    //   V_TOTAL = 500+8+4+213 = 725 ; 4*576*725 = 1,670,400 cyc = 23.9464 Hz
    //   film_tick (DragonsLair_LDV1000.sv FILM_PERIOD) = 1,670,983 cyc = 23.9380 Hz
    //   ratio 1.00035 -> phase slips one refresh every ~2860 frames (~2 min): a single micro-hitch,
    //   versus the current ~9 Hz lurch.
    // BONUS: fewer scans/second CUTS DDR read traffic another 27% (3.52 M/s -> 2.57 M/s), which is
    // the opposite direction from every other option here.
    // Per-LINE budget is UNCHANGED (still clk/4 = 2304 cyc/line = 18 cyc/request, the known-good
    // value), so this cannot reintroduce the bottom-of-picture cut-off.
    //
    // ⚠️ UNVERIFIED ON HW, AND ONE REAL RISK: a ~23.9 Hz core output is unusually low for the
    // MiSTer video chain. If the scaler/monitor flickers or refuses it, REVERT THIS ONE LINE
    // (V_BP back to the 16 default) and the only loss is that the lurch returns.
    // ⚠️ ALSO CHECK DRAGON'S LAIR IN THE SAME BUILD: DL and TQ share the 23.938 film tick, so they
    // were juddering too. If DL looked SMOOTH before this change, the analysis above is WRONG.
    // ORIGINAL: V_BP defaulted to 16'd16 (V_TOTAL 528 -> 32.881 Hz). Delete this line to revert.
    // ROBOTS-RATE-2026-08-15: retuned for 29.97 fps content. The whole CADENCE-FIX above exists
    // to land ONE refresh per film frame, and 213 was solved for DL's 23.938 fps. Robots runs
    // 29.97, so leaving 213 would present 29.97 fps of content on a 23.95 Hz display -- roughly
    // 6 frames a second never shown, i.e. exactly the lurch the fix was written to remove.
    //   V_TOTAL = 40e6 / (4 * 576 * 29.97) = 579.3  ->  579
    //   V_BP    = 579 - (500 + 8 + 4) = 67
    //   refresh = 40e6 / (4*576*579) = 29.9847 Hz  vs  film 29.97003  ->  ratio 1.00049,
    //   so the phase slips one refresh about every 2,040 frames (~68 s): one micro-hitch a
    //   minute, the same trade DL accepted at 1.00035. 579 is the best integer available at
    //   CE_DIV_LOG2=2 / H_TOTAL=576; the exact match would need V_TOTAL 579.28.
    // BONUS: this also retires the "~23.9 Hz is unusually low for the MiSTer video chain" risk
    // flagged above -- 29.98 Hz is an ordinary refresh, so it is LESS likely to upset the scaler
    // than the value it replaces, not more.
    // ORIGINAL (Dragon's Lair, 23.938 fps content -> 23.9464 Hz): .V_BP (16'd213)
    // CLK-100M-2026-08-15: 100 MHz core (PLL: 800 MHz VCO / C0=8; the COUNTERS are
    //   the real config, the output_clock_frequency strings are only metadata).
    //   pixel = CLK/8 = 12.5 MHz, H_TOTAL = 576
    //   V_TOTAL = 12.5e6 / 29.97003 / 576 = 724.1  ->  724
    //   V_BP    = 724 - (500 + 8 + 4) = 212
    //   refresh = 12.5e6/(576*724) = 29.9749 Hz vs film 29.97003 -> ratio 1.00016,
    //   the best yet (40 MHz build was 1.00049) and still on the fast side.
    // ORIGINAL (40 MHz core): .V_BP (16'd67)   ·   DL's proven shape was V_TOTAL 725.
    // LINE-BUDGET: line time = H_TOTAL/pixel_clk, NOT cycles. At 100 MHz the pixel clock is
    // 12.5 MHz, so H_TOTAL 576 gave 46.08 us/line -- 20% LESS than the 57.60 us the 40 MHz
    // build was proven at, tightening the per-LINE fetch deadline the reader must meet.
    // H_TOTAL 789 / V_TOTAL 528 is the MAXIMUM line time the geometry allows while keeping
    // refresh above film rate: 789/12.5e6 = 63.12 us.  CE_DIV_LOG2=4 is unreachable (it would
    // need H_TOTAL < H_ACT), so this is the ceiling at 100 MHz.
    //   refresh = 12.5e6/(789*528) = 30.0053 Hz vs film 29.97003 -> ratio 1.00118
    // REVERT one step: .H_BP (16'd168) / .V_BP (16'd67)   [57.60 us, ratio 1.00049]
    // REVERT fully:    delete .H_BP (module default 24) / .V_BP (16'd212)
    // .H_BP       (16'd237),   // ORIGINAL
    // .V_BP       (16'd16)     // ORIGINAL
    .H_BP       (16'd152),      // 960+8+32+152 = 1152
    .V_BP       (16'd172)       // 540+8+4+172  = 724
) rr (
    .clk(CLK_40M), .reset(reset),
    .frame_base_hw(fb_rd_base),             // FB-DOUBLEBUF-2026-07-15: was hardcoded 27'd0, see fb_buf_sel above
    // Original: .vid_en(g_phase_w == 2'd2 && disp_cm == 2'd0),
    // Original: .vid_en(g_phase_w == 2'd2 && disp_cm == 2'd0 && g_view_w == 2'd0),
    .vid_en(g_phase_w == 2'd2 && disp_cm == 2'd0 && g_view_w == 3'd0 && g_eg_w != 2'd1),  // video is covered in the menus and during a card moment
    .lr_addr(rr_lr_addr), .lr_len(rr_lr_len), .lr_req(rr_lr_req), .lr_ack(rr_lr_ack),
    .lr_data(rr_lr_data), .lr_valid(rr_lr_valid),
    .fill_idle(rr_fill_idle),               // WRITE-GATE-2026-07-16 (delete on revert)
    .ce_pix(rr_ce_pix),
    .hsync(rr_hs), .vsync(rr_vs), .hblank(rr_hblank), .vblank(rr_vblank),
    .hpos(rr_hpos), .vpos(rr_vpos),
    .vid_r(rr_r), .vid_g(rr_g), .vid_b(rr_b)
);



endmodule
