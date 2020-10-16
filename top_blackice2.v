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

module top_blackice2(
    input wire clk100, 
    output wire [3:0] LED, 
    output wire UART_TX, input wire UART_RX, 
    output wire RAMOE, output wire RAMWE, output wire RAMCS,  // SRAM pins
    output wire RAMLB, output wire RAMUB,
    output [17:0] ADR, input [15:0] DAT,
    input wire QSPICSN, input wire QSPICK, // QUAD SPI pins
    output wire [3:0] QSPIDQ,
    input wire B1,      // buttons
    input wire B2,
    input wire GRESET, input wire DONE,
    input wire DIG16,   // These are normally high
    input wire DIG17, 
    input wire DIG18, 
    input wire DIG19,
    output wire [3:0] red, output wire [3:0] green, output wire [3:0] blue, 
    output wire hsync, output wire vsync,
    output wire PMOD5_1, output wire PMOD5_2, output wire PMOD5_3, output wire PMOD5_4,
    output wire PMOD6_1, output wire PMOD6_2, output wire PMOD6_3, output wire PMOD6_4,
    input wire ps2_clk,
    input wire ps2_data
  );

  // not used
	assign QSPIDQ[3:0] = {4{1'b0}}; // {4{1'bz}};

//-------------------------------------------------------------------

  wire clk;
  pll _pll(
    .clock_in(clk100),
    .clock_out(clk)
      );  

  // Yosys can't handle bidirectional pins directly, need to handle them differently.
  wire [15:0] sram_pins_din;
  wire [15:0] sram_pins_dout;
  wire sram_pins_drive;
  // Yosys component
  SB_IO #(
    .PIN_TYPE(6'b1010_01),
  ) sram_data_pins [15:0] (
    .PACKAGE_PIN(DAT),
    .OUTPUT_ENABLE(sram_pins_drive), 
    .D_OUT_0(sram_pins_dout),
    .D_IN_0(sram_pins_din)
  );


  // Serial port assignments begin
  wire serloader_rx = UART_RX;  // all incoming traffic goes to serloader 
  wire serloader_tx;
  wire tms9902_rx = (DIG19 == 1'b1) ? UART_RX : 1'b1; // if DIG19 is low, the UART receive is disabled
  wire tms9902_tx;
  assign UART_TX  = (DIG19 == 1'b1) ? tms9902_tx : serloader_tx;
  // Serial port assignments end
  wire vde;
  wire pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden;
  wire [22:0] sys_addr;
  assign ADR = sys_addr[17:0];
  sys ti994a(
      .clk(clk), 
      .LED(LED), 
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
      // LCD signals
      .pin_cs(pin_cs), 
      .pin_sdin(pin_sdin), 
      .pin_sclk(pin_sclk), 
      .pin_d_cn(pin_d_cn), 
      .pin_resn(pin_resn), 
      .pin_vccen(pin_vccen), 
      .pin_pmoden(pin_pmoden),
      .serloader_tx(serloader_tx), 
      .serloader_rx(serloader_rx), // bootloader UART
    .vde(vde),    // Video display enable (active area)
    .ps2clk(ps2_clk), 
    .ps2dat(ps2_data)
  );

  assign PMOD5_1 = pin_cs;
  assign PMOD5_2 = pin_sdin;
  assign PMOD5_3 = 1'b0;
  assign PMOD5_4 = pin_sclk;
  assign PMOD6_1 = pin_d_cn;
  assign PMOD6_2 = pin_resn;
  assign PMOD6_3 = pin_vccen;
  assign PMOD6_4 = pin_pmoden;


endmodule

