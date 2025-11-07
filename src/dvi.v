// module port
//
module DVI_out
#(
  parameter generic_ddr = 1,
  parameter ecp5_ddr    = 0
)
(
  input  wire pixclk,
  input  wire pixclk_x5,
  input  wire [7:0] red, green, blue,
  input  wire vde, hSync, vSync,
  output wire [1:0] tmds_c, tmds_r, tmds_g, tmds_b
);

  // Synchronize all inputs on the pixel clock first to ensure alignment
  reg [7:0] sync_red = 0, sync_green = 0, sync_blue = 0;
  reg sync_vde = 0, sync_hSync = 0, sync_vSync = 0;
  
  always @(posedge pixclk) begin
    sync_red   <= red;
    sync_green <= green;
    sync_blue  <= blue;
    sync_vde   <= vde;
    sync_hSync <= hSync;
    sync_vSync <= vSync;
  end

  // 10b8b TMDS encoding of RGB and Sync
  //
  wire [9:0] TMDS_red, TMDS_green, TMDS_blue;
  TMDS_encoder encode_R(.clk(pixclk), .VD(sync_red  ), .CD(2'b00)              , .VDE(sync_vde), .TMDS(TMDS_red));
  TMDS_encoder encode_G(.clk(pixclk), .VD(sync_green), .CD(2'b00)              , .VDE(sync_vde), .TMDS(TMDS_green));
  TMDS_encoder encode_B(.clk(pixclk), .VD(sync_blue ), .CD({sync_vSync,sync_hSync}), .VDE(sync_vde), .TMDS(TMDS_blue));

  // Latch encoded data on pixel clock (pipeline stage for timing)
  reg [9:0] latched_red = 0, latched_green = 0, latched_blue = 0;
  
  always @(posedge pixclk)
  begin
    latched_red   <= TMDS_red;
    latched_green <= TMDS_green;
    latched_blue  <= TMDS_blue;
  end

  // DDR serializer with proper clock domain synchronization
  // Uses rotating shift_clock pattern to synchronize load timing
  // This is based on the working vga2dvid implementation
  parameter [9:0] c_shift_clock_initial = 10'b0000011111;
  reg [9:0] shift_clock = c_shift_clock_initial;
  reg [9:0] shift_red = 0, shift_green = 0, shift_blue = 0;

  always @(posedge pixclk_x5)
  begin
    // Load new data when shift_clock pattern indicates it's time
    if(shift_clock[5:4] == c_shift_clock_initial[5:4]) begin
      shift_red   <= latched_red;
      shift_green <= latched_green;
      shift_blue  <= latched_blue;
    end
    else begin
      // Shift out 2 bits for DDR
      shift_red   <= {2'b00, shift_red[9:2]};
      shift_green <= {2'b00, shift_green[9:2]};
      shift_blue  <= {2'b00, shift_blue[9:2]};
    end
    // Rotate the shift_clock pattern (2 bits per cycle for DDR)
    shift_clock <= {shift_clock[1:0], shift_clock[9:2]};
  end

  assign tmds_c = shift_clock[1:0];  // Clock pattern
  assign tmds_r = shift_red[1:0];
  assign tmds_g = shift_green[1:0];
  assign tmds_b = shift_blue[1:0];
endmodule


// DVI-D 10b8b TMDS encoder module
//
module TMDS_encoder(
  input clk,       // pix clock
  input [7:0] VD,  // video data (red, green or blue)
  input [1:0] CD,  // control data
  input VDE,       // video data enable, to choose between CD (when VDE=0) and VD (when VDE=1)
  output reg [9:0] TMDS = 0
);

  genvar i;
  reg  [3:0] dc_bias = 0;

  // compute data word
  wire [3:0] ones = VD[0] + VD[1] + VD[2] + VD[3] + VD[4] + VD[5] + VD[6] + VD[7];
  wire       XNOR = (ones>4'd4) || (ones==4'd4 && VD[0]==1'b0);

  // Replace the following with the generator below to avoid signal loop warnings
  // from Yosys.
  // wire [8:0] dw   = { ~XNOR, dw[6:0] ^ VD[7:1] ^ {7{XNOR}}, VD[0] };

  wire [8:0] dw;
  assign                     dw[8] = ~XNOR;
  for(i=1; i<=7; i++) assign dw[i] = dw[i-1] ^ VD[i] ^ XNOR;
  assign                     dw[0] = VD[0];


  // calculate 1/0 disparity & invert as needed to minimize dc bias
  wire [3:0] dw_disp = dw[0] + dw[1] + dw[2] + dw[3] + dw[4] + dw[5] + dw[6] + dw[7] + 4'b1100;
  wire       sign_eq = (dw_disp[3] == dc_bias[3]);
  
  wire [3:0] delta  = dw_disp - ({dw[8] ^ ~sign_eq} & ~(dw_disp==0 || dc_bias==0));
  wire       inv_dw = (dw_disp==0 || dc_bias==0) ? ~dw[8] : sign_eq;
  
  wire [3:0] dc_bias_d = inv_dw ? dc_bias - delta : dc_bias + delta;
  
  // set output signals
  wire [9:0] TMDS_data = { inv_dw, dw[8], dw[7:0] ^ {8{inv_dw}} };
  wire [9:0] TMDS_code = CD[1] ? (CD[0] ? 10'b1010101011 : 10'b0101010100)
                               : (CD[0] ? 10'b0010101011 : 10'b1101010100);

  always @(posedge clk) TMDS    <= VDE ? TMDS_data : TMDS_code;
  always @(posedge clk) dc_bias <= VDE ? dc_bias_d : 0;

endmodule