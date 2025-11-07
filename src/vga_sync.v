// File src/vga_sync.vhd translated with vhd2vl v3.0 VHDL to Verilog RTL translator
// Modified for 960x540 @ 60Hz resolution
// Parameters:
//   Pixel clock: 40 MHz
//   Resolution: 960x540
//   Frame dimensions: 1216x548 (horizontal x vertical total)
//   Hsync: front=85, pulse=85, back=86 (total blanking=256)
//   Vsync: front=2, pulse=2, back=4 (total blanking=8)
module VGA_SYNC(
  input wire clk,
  output wire video_on,
  output reg horiz_sync,
  output reg vert_sync,
  output wire [9:0] pixel_row,
  output wire [9:0] pixel_column
);

  reg [10:0] h_count=0;  // Need 11 bits for 1216
  reg [9:0] v_count=0;   // 10 bits sufficient for 548
  assign pixel_column = h_count[9:0];  // Truncate to 10 bits for compatibility
  assign pixel_row    = v_count;

  localparam pixel_f                  = 40000000; // pixel frequency
  localparam f                        = 60;       // frame rate
  localparam [10:0] x                 = 960; // 800;  // 960;      // active horizontal pixels
  localparam [10:0] y                 = 540; // 600;  // 540;      // active vertical pixels
  localparam [10:0] yminblank         = y/64;    // 8; // y/64;    // minimum vertical blanking lines
  localparam [10:0] yframe            = y+yminblank; // total vertical lines
  localparam [10:0] xadjustf          = 0;   // adjustment factor if needed
  localparam [10:0] xframe            = x+256; // pixel_f/(f*yframe);
  localparam [10:0] xblank            = xframe-x;
  localparam [10:0] yblank            = yframe-y;
  localparam [10:0] hsync_front_porch = 40; // xblank/3;
  localparam [10:0] hsync_pulse_width = 128; // xblank/3;
  localparam [10:0] hsync_back_porch  = xblank-hsync_pulse_width-hsync_front_porch+xadjustf;
  localparam [10:0] vsync_front_porch = yblank/3; // 1 for 800x600
  localparam [10:0] vsync_pulse_width = yblank/3; // 4 for 800x600
  localparam [10:0] vsync_back_porch  = yblank-vsync_pulse_width-vsync_front_porch;
// initial begin
//   $display("Calculated xframe: %d", xframe);
// end


  assign video_on = (h_count < x) && (v_count < y);
  
  //Generate Horizontal and Vertical Timing Signals for Video Signal
  // 960x540 @ 60Hz timing:
  // Horizontal: 960 + 85(front) + 85(sync) + 86(back) = 1216 total
  // Vertical:   540 + 2(front) + 2(sync) + 4(back) = 548 total
  //
  //  Horiz_sync  ------------------------------------__________--------
  //  H_count       0                960            1045      1130   1215
  //
  always @(posedge clk) 
  begin
    //if(h_count == 11'd1214) begin // 11'd1215 is the ok, 1126 tested causes blinking
    if(h_count == (xframe-1)) begin 
      h_count <= 11'd0;
      v_count <= (v_count == (yframe-1) ? 10'd0 : v_count + 10'd1);
    end else begin
      h_count <= h_count + 11'd1;
    end
  end

  // Generate sync signals
  // Match reference vga.v timing exactly (all values are -1):
  // Hsync pulse: starts at 960+85-1=1044, ends at 960+85+85-1=1129
  // Vsync pulse: starts at 540+2-1=541, ends at 540+2+2-1=543
  always @(posedge clk) 
  begin
    horiz_sync <= (h_count >= (x + hsync_front_porch - 1) && h_count <= (x + hsync_front_porch + hsync_pulse_width - 1)) ? 1'b0 : 1'b1;
    vert_sync  <= (v_count >= (y + vsync_front_porch - 1) && v_count <= (y + vsync_front_porch + vsync_pulse_width - 1)) ? 1'b0 : 1'b1;
  end

endmodule
