// lcd_sys.v
// EP based on the open tech lab LCD controller stuff

module lcd_sys(
    input wire clk,
    input wire reset,
    output wire cs, 
    output wire sdin, 
    output wire sclk, 
    output wire d_cn, 
    output wire resn, 
    output wire vccen, 
    output wire pmoden,
    // LCD RAM buffer memory
    input wire ram_wr,
    input wire [12:0] ram_addr,
    input wire [15:0] ram_data
);

// output cs, sdin, sclk, d_cn, resn, vccen, pmoden;


wire frame_begin, sending_pixels, sample_pixel;
wire [12:0] pixel_index;
wire [15:0] pixel_data;
wire [6:0] x;
wire [5:0] y;

// Use a quarter of clk as our spi_clk
reg spi_clk;
reg [1:0] div = 2'b00;
always @(posedge clk) begin
    spi_clk <= div[1];
    div <= div + 2'd1;
end

// Need to write our pixels with ram_addr, ram_data_ram_wr

ram_source ram_source(spi_clk, reset, frame_begin, sample_pixel,
  pixel_index, pixel_data, clk, ram_wr, ram_addr, ram_data);

// SPI Clock Generator
parameter ClkFreq = 25000000; // Hz
localparam SpiDesiredFreq = 6250000; // Hz
localparam SpiPeriod = (ClkFreq + (SpiDesiredFreq * 2) - 1) / (SpiDesiredFreq * 2);
localparam SpiFreq = ClkFreq / (SpiPeriod * 2);

pmodoledrgb_controller #(SpiFreq) pmodoledrgb_controller(spi_clk, reset,
  frame_begin, sending_pixels, sample_pixel, pixel_index, pixel_data,
  cs, sdin, sclk, d_cn, resn, vccen, pmoden);

endmodule