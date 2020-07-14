// File src/vga_sync.vhd translated with vhd2vl v3.0 VHDL to Verilog RTL translator
module VGA_SYNC(
  input wire clk,
  output wire video_on,
  output reg horiz_sync,
  output reg vert_sync,
  output wire [9:0] pixel_row,
  output wire [9:0] pixel_column
);

  reg [9:0] h_count=0; 
  reg [9:0] v_count=0;
  assign pixel_column = h_count;
  assign pixel_row    = v_count;

  assign video_on = (h_count < 640) && (v_count < 480);
  //Generate Horizontal and Vertical Timing Signals for Video Signal
  // H_count counts pixels (640 + extra time for sync signals)
  // 
  //  Horiz_sync  ------------------------------------__________--------
  //  H_count       0                640             659       755    799
  //
  always @(posedge clk) 
  begin
    if(h_count == 10'd799) begin
      h_count <= 10'd0;
      v_count <= (v_count == 10'd519) ? 10'd0 : v_count + 10'd1;
    end else begin
      h_count <= h_count + 10'd1;
    end
  end

  // Generate sync signals
  always @(posedge clk) 
  begin
    horiz_sync <= (h_count >= 659 && h_count <= 755) ? 1'b0 : 1'b1;
    vert_sync  <= (v_count >= 493 && v_count <= 494) ? 1'b0 : 1'b1;
  end

endmodule
