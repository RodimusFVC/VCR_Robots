//============================================================================
// fb_ddr.sv — framebuffer DDR3 controller for the MiSTer DDRAM (f2sdram Avalon-MM) port.
//
// Replaces Sorgelig's ddram.sv for the video path. Three clients, one bus:
//   L  line reads   : one burst of up to 255 64-bit words per request (raster reader).
//                     NOTE the HPS f2sdram bridge wedges on 128-word read bursts; 16 works on HW.
//   W  word writes  : single 64-bit word + byte enables, posted (fb_writer's contract).
//   R  random 16-bit: read/write one halfword (ddram.sv "rom" port contract; spare for CPU RAM).
//
// Rules (all carried over from what is proven on HW with ddram.sv):
//   * A command is accepted on a clock edge where RD/WE=1 and BUSY=0; while BUSY it is held.
//   * Read data (DOUT_READY) is consumed independently of BUSY (the 2026-07-20 hard-lock bug).
//   * No command is issued while a read burst is still returning (ddram.sv never overlapped).
// Every decision is made from registered state or a single compare, so the whole module is
// sized for 100 MHz: no address arithmetic or cache compare in front of a wide register load.
//============================================================================
module fb_ddr
(
	input             clk,

	input             DDRAM_BUSY,
	output      [7:0] DDRAM_BURSTCNT,
	output     [28:0] DDRAM_ADDR,
	input      [63:0] DDRAM_DOUT,
	input             DDRAM_DOUT_READY,
	output            DDRAM_RD,
	output     [63:0] DDRAM_DIN,
	output      [7:0] DDRAM_BE,
	output            DDRAM_WE,

	// W: posted word writes. Toggle we_req; we_ack follows once the write is latched here.
	input      [27:1] wraddr,
	input      [63:0] din64,
	input       [7:0] be64,
	input             we_req,
	output reg        we_ack,

	// L: line burst reads. Toggle lr_req with lr_addr/lr_len stable; lr_len words arrive on
	// lr_data/lr_valid in address order; lr_ack follows on the same edge as the last word.
	input      [27:3] lr_addr,
	input       [7:0] lr_len,          // 1..255
	input             lr_req,
	output reg        lr_ack,
	output reg [63:0] lr_data,
	output reg        lr_valid,

	// R: random halfword access, same contract as ddram.sv's rom port (hold inputs until ack).
	input      [27:1] rdaddr,
	output     [15:0] dout,
	input      [15:0] rom_din,
	input       [1:0] rom_be,
	input             rom_we,
	input             rom_req,
	output reg        rom_ack
);

initial begin we_ack = 1'b0; lr_ack = 1'b0; lr_valid = 1'b0; rom_ack = 1'b0; end

reg  [7:0] ram_burst = 8'd1;
reg [27:3] ram_address;
reg [63:0] ram_data;
reg  [7:0] ram_be = 8'd0;
reg        ram_read = 1'b0;
reg        ram_write = 1'b0;

assign DDRAM_BURSTCNT = ram_burst;
assign DDRAM_ADDR     = {4'b0011, ram_address};   // RAM at 0x30000000
assign DDRAM_RD       = ram_read;
assign DDRAM_WE       = ram_write;
assign DDRAM_DIN      = ram_data;
assign DDRAM_BE       = ram_read ? 8'hFF : ram_be;

reg [63:0] r_q;
reg [1:0]  r_lane;
assign dout = r_q[{r_lane, 4'b0000} +: 16];

reg        rd_busy  = 1'b0;   // a read burst is issued and not fully returned
reg        rd_owner = 1'b0;   // 0 = L, 1 = R
reg  [7:0] beats_left = 8'd0;
reg        lr_req_q = 1'b0;   // lr_req value being served
reg        rom_req_q = 1'b0;

always @(posedge clk) begin
	lr_valid <= 1'b0;

	// ---- read-data return: never gated by BUSY ----
	if (DDRAM_DOUT_READY && rd_busy) begin
		beats_left <= beats_left - 8'd1;
		if (!rd_owner) begin
			lr_data  <= DDRAM_DOUT;
			lr_valid <= 1'b1;
		end else begin
			r_q <= DDRAM_DOUT;
		end
		if (beats_left == 8'd1) begin
			rd_busy <= 1'b0;
			if (!rd_owner) lr_ack  <= lr_req_q;
			else           rom_ack <= rom_req_q;
		end
	end

	// ---- command issue: only when the previous command has been accepted ----
	if (!DDRAM_BUSY) begin
		ram_read  <= 1'b0;
		ram_write <= 1'b0;

		if (!rd_busy) begin
			if (lr_req != lr_ack) begin
				ram_address <= lr_addr;
				ram_burst   <= lr_len;
				ram_read    <= 1'b1;
				beats_left  <= lr_len;
				rd_owner    <= 1'b0;
				rd_busy     <= 1'b1;
				lr_req_q    <= lr_req;
			end
			else if (rom_req != rom_ack) begin
				ram_address <= rdaddr[27:3];
				ram_burst   <= 8'd1;
				if (rom_we) begin
					ram_be    <= {6'd0, rom_be} << {rdaddr[2:1], 1'b0};
					ram_data  <= {4{rom_din}};
					ram_write <= 1'b1;
					rom_ack   <= rom_req;              // posted
				end else begin
					ram_read   <= 1'b1;
					beats_left <= 8'd1;
					rd_owner   <= 1'b1;
					rd_busy    <= 1'b1;
					rom_req_q  <= rom_req;
					r_lane     <= rdaddr[2:1];
				end
			end
			else if (we_req != we_ack) begin
				ram_address <= wraddr[27:3];
				ram_burst   <= 8'd1;
				ram_be      <= be64;
				ram_data    <= din64;
				ram_write   <= 1'b1;
				we_ack      <= we_req;                 // posted
			end
		end
	end
end


endmodule
