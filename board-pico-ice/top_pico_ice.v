// top_blackice2.v 
// EP (C) 2019
// This is the toplevel for the platform neutral sys.v which
// implements the TI-99/4A.

//-------------------------------------------------------------------
// PLL added by EP 2019-08-30
//-------------------------------------------------------------------
// icepll -i 100 -o 25 -m -f erik_pll.v
// PLL configuration written to: erik_pll.v
//-------------------------------------------------------------------

module top_pico_ice(
  input  CLK,
  output LED_R, // on board red
  output LED_G, // on board green
  input ICE_10, // user button aka reset

  // outer, inner alternate. ICE_28 is outer next to GND, ICE_31 inner next to GND
  // This is VS,     HS,     DE,     B0,     B1,     CK,     B2,     B3
  output ICE_28, ICE_31, ICE_32, ICE_34, ICE_36, ICE_38, ICE_42, ICE_43, 
  //         G0,     G1,     G2,     G3,     R0,     R1,     R2,     R3
  output ICE_44, ICE_45, ICE_46, ICE_47, ICE_48, ICE_2, ICE_3, ICE_4,

  // QSPI Flash pins. Apart for ICE_16 (CSN) these are shared with the PSRAM chip.
  output ICE_16, // FLASH_CSN
  output ICE_15, // FLASH_CLK
  inout  ICE_14, // ICE_SO, FLASH_IO0
  inout  ICE_17, // ICE_SI, FLASH_IO1
  inout  ICE_12, // FLASH_IO2
  inout  ICE_13, // FLASH_IO3
  output ICE_37, // SRAM_SS - PSRAM chip select

  // UART connections, newest default firmware, second USB serial port is connected to an UART
  input  UART_RX, // UART_RX connected to RP2040 GPIO1 (pin 3)
  output UART_TX, // UART_TX connected to RP2040 GPIO0 (pin 2)

  output ICE_21 // debug output, easier to attach a probe than the outer pins
  );

  wire pixel_clk;

//-------------------------------------------------------------------


//-----------------------------------------------------------------------------
// PLL.
//-----------------------------------------------------------------------------
SB_PLL40_PAD #(
  .DIVR(4'b0000),
  // 40MHz ish to be exact it is 39.750MHz
  .DIVF(7'b0110100), // 39.750MHz
  .DIVQ(3'b100),
  .FILTER_RANGE(3'b001),
  .FEEDBACK_PATH("SIMPLE"),
  .DELAY_ADJUSTMENT_MODE_FEEDBACK("FIXED"),
  .FDA_FEEDBACK(4'b0000),
  .DELAY_ADJUSTMENT_MODE_RELATIVE("FIXED"),
  .FDA_RELATIVE(4'b0000),
  .SHIFTREG_DIV_MODE(2'b00),
  .PLLOUT_SELECT("GENCLK"),
  .ENABLE_ICEGATE(1'b0)
) pll_inst (
  .PACKAGEPIN(CLK),
  .PLLOUTCORE(),
  .PLLOUTGLOBAL(pixel_clk),
  .EXTFEEDBACK(),
  .DYNAMICDELAY(),
  .RESETB(1'b1),
  .BYPASS(1'b0),
  .LATCHINPUTVALUE(),
  //.LOCK(),
  //.SDI(),
  //.SDO(),
  //.SCLK()
);

  // VGA
  wire [3:0] red, green, blue;
  wire hsync, vsync;

  // Serial port assignments begin
  wire serloader_rx = UART_RX;  // all incoming traffic goes to serloader 
  wire serloader_tx;
  assign UART_TX = serloader_tx;  // default outgoing is from serloader

  wire vde;
  wire pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden;
  wire [22:0] sys_addr;
  assign ADR = sys_addr[17:0];

  sys ti994a(
      .clk(pixel_clk), 
      .LED(LED_R), 
      .tms9902_tx(tms9902_tx), 
      .tms9902_rx(tms9902_rx),
      .RAMOE(RAMOE), 
      .RAMWE(RAMWE), 
      .RAMCS(RAMCS), 
      .RAMLB(RAMLB), 
      .RAMUB(RAMUB),
      .ADR(sys_addr), 
      .sram_pins_din(sram_pins_din), 
      .sram_pins_dout(sram_pins_dout),
      .sram_pins_drive(sram_pins_drive),
      .memory_busy(1'b0),
      .use_memory_busy(1'b0),
      .red(red), 
      .green(green), 
      .blue(blue), 
      .hsync(hsync), 
      .vsync(vsync),
      .cpu_reset_switch_n(DIG18),  
`ifdef LCD_SUPPORT      
      // LCD signals
      .pin_cs(pin_cs), 
      .pin_sdin(pin_sdin), 
      .pin_sclk(pin_sclk), 
      .pin_d_cn(pin_d_cn), 
      .pin_resn(pin_resn), 
      .pin_vccen(pin_vccen), 
      .pin_pmoden(pin_pmoden),
`endif      
      .serloader_tx(serloader_tx), 
      .serloader_rx(serloader_rx), // bootloader UART
    .vde(vde),    // Video display enable (active area)
    .ps2clk(ps2_clk), 
    .ps2dat(ps2_data)
  );

`ifdef LCD_SUPPORT
  assign PMOD5_1 = pin_cs;
  assign PMOD5_2 = pin_sdin;
  assign PMOD5_3 = 1'b0;
  assign PMOD5_4 = pin_sclk;
  assign PMOD6_1 = pin_d_cn;
  assign PMOD6_2 = pin_resn;
  assign PMOD6_3 = pin_vccen;
  assign PMOD6_4 = pin_pmoden;
`endif 

// video output to DVI module
// ----------------------------------------------------------------------------
// Assign the PMOD(s) pins
// ----------------------------------------------------------------------------
// Also add IO registers to minimize timing between lines and ensure we're
// properly aligned to the clock. Clock is output using a DDR flop and 180deg
// out of phase (rising edge in middle of data eye) to maximize setup/hold
// time margin.

SB_IO #(
  .PIN_TYPE(6'b01_0000)  // PIN_OUTPUT_DDR
) dvi_clk_iob (
  .PACKAGE_PIN (P1B2),
  .D_OUT_0     (1'b0),
  .D_OUT_1     (1'b1),
  .OUTPUT_CLK  (pixel_clk)
);

wire [7:4] r, g, b;
assign r[7:4] = red;
assign g[7:4] = green;
assign b[7:4] = blue;
wire vga_hs = hsync;
wire vga_vs = vsync;
wire vga_de = vde;


SB_IO #(
  .PIN_TYPE(6'b01_0100)  // PIN_OUTPUT_REGISTERED
) dvi_data_iob [14:0] (
  .PACKAGE_PIN ({P1A1,   P1A2,   P1A3,   P1A4,   P1A7,   P1A8,   P1A9,   P1A10,
                 P1B1,           P1B3,   P1B4,   P1B7,   P1B8,   P1B9,   P1B10}),
  .D_OUT_0     ({r[7],   r[5],   g[7],   g[5],   r[6],   r[4],   g[6],   g[4],
                 b[7],           b[4],   vga_hs, b[6],   b[5],   vga_de, vga_vs}),
  .OUTPUT_CLK  (pixel_clk)
);

endmodule

