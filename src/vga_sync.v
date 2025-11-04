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

  assign video_on = (h_count < 960) && (v_count < 540);
  
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
    if(h_count == 11'd1215) begin
      h_count <= 11'd0;
      v_count <= (v_count == 10'd547) ? 10'd0 : v_count + 10'd1;
    end else begin
      h_count <= h_count + 11'd1;
    end
  end

  // Generate sync signals
  // Hsync pulse: starts at 960+85=1045, ends at 1045+85-1=1129
  // Vsync pulse: starts at 540+2=542, ends at 542+2-1=543
  always @(posedge clk) 
  begin
    horiz_sync <= (h_count >= 1045 && h_count <= 1129) ? 1'b0 : 1'b1;
    vert_sync  <= (v_count >= 542 && v_count <= 543) ? 1'b0 : 1'b1;
  end

endmodule
