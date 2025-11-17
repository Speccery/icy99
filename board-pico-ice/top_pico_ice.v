// top_pico_ice.v
// EP (C) 2025-11-16
// This is the toplevel for the platform neutral sys.v which
// implements the TI-99/4A.
//------------------------------------------------------------

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

  output ICE_21, // debug output, easier to attach a probe than the outer pins
  output ICE_20  // debug output, easier to attach a probe than the outer pins
  );

  wire pixel_clk;

//-------------------------------------------------------------------


//-----------------------------------------------------------------------------
// PLL - Generate 40 MHz pixel clock and 10 MHz system clock
// pixel_clk: 40 MHz for VDP pixel pipeline and DVI output
// sys_clk: 10 MHz for CPU, memory controller, and all other logic
//-----------------------------------------------------------------------------
wire sys_clk;  // 10 MHz system clock for CPU and logic

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

// Generate 10 MHz system clock from 40 MHz pixel clock
reg [1:0] clk_div;
always @(posedge pixel_clk) begin
  clk_div <= clk_div + 1;
end
assign sys_clk = clk_div[1];  // Divide by 4: 40 MHz / 4 = 10 MHz

  // VGA
  wire [3:0] red, green, blue;
  wire hsync, vsync;

  // Serial port assignments begin
  wire serloader_rx = UART_RX;  // all incoming traffic goes to serloader 
  wire serloader_tx;
  assign UART_TX = serloader_tx;  // default outgoing is from serloader

  wire vde;
  wire pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden;
  wire [22:0] sys_addr;  // Address bus from sys.v (word address)
  
  // ========================================================================
  // Memory subsystem for pico-ice
  // - VDP VRAM: Uses SPRAM (32KB) via USE_SPRAM_FOR_VRAM define in tms9918.v
  // - Scratchpad: Block RAM (1KB) at 0x8000-0x83FF
  // - ROM/GROM: TBD (SPI flash or remaining SPRAM blocks)
  // ========================================================================
  
  // Reset signal - use sys_clk for proper startup
  wire reset;
  reg [7:0] reset_counter = 8'h00;
  assign reset = (reset_counter != 8'hFF);
  always @(posedge sys_clk) begin
    if (reset_counter != 8'hFF)
      reset_counter <= reset_counter + 8'd1;
  end

  // Scratchpad RAM - 1KB at 0x8000-0x83FF using block RAM (EBR)
  // TI-99/4A originally has 256 bytes at 0x8300, we provide full 1KB at 0x8000-0x83FF
  // sys_addr is a WORD address from sys.v, covering 16MB address space
  wire pad_sel = (sys_addr[22:10] == 13'b0000_0000_1000_0); // 0x8000-0x83FF (byte addresses)
  wire [15:0] pad_data_out;
  reg [7:0] scratchpad_lo [0:511];  // 512 bytes low
  reg [7:0] scratchpad_hi [0:511];  // 512 bytes high
  reg [15:0] pad_data_reg;
  
  wire pad_we_lo = pad_sel && !RAMLB && !RAMWE;  // Lower byte write enable
  wire pad_we_hi = pad_sel && !RAMUB && !RAMWE;  // Upper byte write enable
  
  always @(posedge sys_clk) begin
    if (pad_we_lo) begin
      scratchpad_lo[sys_addr[8:0]] <= sram_pins_dout[7:0];
    end
    if (pad_we_hi) begin
      scratchpad_hi[sys_addr[8:0]] <= sram_pins_dout[15:8];
    end
    if (pad_sel) begin
      pad_data_reg <= {scratchpad_hi[sys_addr[8:0]], scratchpad_lo[sys_addr[8:0]]};
    end
  end
  
  assign pad_data_out = pad_data_reg;
  
  // ========================================================================
  // SPI Flash ROM/GROM
  // Console ROM: 8KB at flash offset 0x040000, mapped to CPU 0x0000-0x1FFF
  // Console GROM: 24KB at flash offset 0x042000, mapped via gromext module
  // ========================================================================
  
  // ROM selection: 8KB at word addresses 0x00000-0x00FFF
  wire rom_sel = (sys_addr[22:12] == 11'b0000_0000_000);  // 8K @ 0x00000
  // GROM selection: sys.v maps GROM to word addresses 0x10000-0x17FFF
  wire grom_sel = (sys_addr[22:15] == 8'b0000_0001);      // 64K @ 0x10000
  
  wire [15:0] flash_rom_data;
  wire flash_rom_ready;
  wire [3:0] flash_debug_state;
  
  // Memory busy logic for SPI flash ROM access (similar to ULX3S SDRAM)
  // The CPU needs to wait while SPI flash read is in progress
  wire flash_rom_rd = (rom_sel || grom_sel) && !RAMOE;
  wire use_memory_busy = flash_rom_rd;
  
  reg [7:0] busy_count = 8'h00;
  wire memory_busy = (|busy_count);
  
  assign ICE_20 = flash_debug_state[0];  // debug output - flash state bit 0
  assign ICE_21 = flash_rom_ready;  // debug output - should go high when data ready

  // Generate wait states for SPI flash access
  // Need to latch the request and wait for flash_rom_ready to go high
  reg flash_access_pending;
  reg flash_rom_ready_prev;
  
  always @(posedge sys_clk) begin
    flash_rom_ready_prev <= flash_rom_ready;
    
    // Start a flash access when flash_rom_rd goes high and we're not already busy
    if (flash_rom_rd && !flash_access_pending) begin
      flash_access_pending <= 1'b1;
      busy_count <= 8'd200;  // Maximum wait time
    end
    // Keep waiting until flash responds (rising edge) or timeout
    else if (flash_access_pending) begin
      if ((flash_rom_ready && !flash_rom_ready_prev) || busy_count == 0) begin
        flash_access_pending <= 1'b0;
        busy_count <= 0;
      end else begin
        busy_count <= busy_count - 8'd1;
      end
    end
  end

  spi_flash_rom flash_rom(
    .clk(sys_clk),          // Use 10 MHz system clock
    .reset(reset),
    
    // SRAM-style interface
    .addr(sys_addr),        // Word address from sys.v
    .rom_sel(rom_sel),
    .grom_sel(grom_sel),
    .data_out(flash_rom_data),
    .data_ready(flash_rom_ready),
    
    // SPI Flash pins - connect to QSPI flash (shared with PSRAM)
    .flash_csn(ICE_16),     // FLASH_CSN
    .flash_clk(ICE_15),     // FLASH_CLK  
    .flash_mosi(flash_mosi_out),  // FLASH_IO0 (bidirectional, need tristate)
    .flash_miso(flash_miso_in),   // FLASH_IO1 (bidirectional, need tristate)
    
    // Debug
    .debug_state(flash_debug_state)
  );
  
  // Handle bidirectional QSPI pins with tristate buffers
  // For simple SPI read, we only need IO0 (MOSI) and IO1 (MISO)
  wire flash_mosi_out, flash_miso_in;
  
  // ICE_14 is FLASH_IO0 (MOSI - output only during SPI operations)
  SB_IO #(
    .PIN_TYPE(6'b1010_01),  // PIN_OUTPUT_TRISTATE + PIN_INPUT
    .PULLUP(1'b0)
  ) flash_io0_buf (
    .PACKAGE_PIN(ICE_14),
    .OUTPUT_ENABLE(~ICE_16),  // Drive when CS is low
    .D_OUT_0(flash_mosi_out),
    .D_IN_0()  // Not used for MOSI
  );
  
  // ICE_17 is FLASH_IO1 (MISO - input during SPI operations)
  SB_IO #(
    .PIN_TYPE(6'b1010_01),  // PIN_OUTPUT_TRISTATE + PIN_INPUT
    .PULLUP(1'b1)           // Pullup when not driven
  ) flash_io1_buf (
    .PACKAGE_PIN(ICE_17),
    .OUTPUT_ENABLE(1'b0),     // Always input for MISO
    .D_OUT_0(1'b0),
    .D_IN_0(flash_miso_in)
  );
  
  // ICE_12 and ICE_13 are FLASH_IO2 and FLASH_IO3 (not used in standard SPI mode)
  // Leave them as high-Z with pullups
  SB_IO #(
    .PIN_TYPE(6'b1010_01),
    .PULLUP(1'b1)
  ) flash_io2_buf (
    .PACKAGE_PIN(ICE_12),
    .OUTPUT_ENABLE(1'b0),
    .D_OUT_0(1'b0),
    .D_IN_0()
  );
  
  SB_IO #(
    .PIN_TYPE(6'b1010_01),
    .PULLUP(1'b1)
  ) flash_io3_buf (
    .PACKAGE_PIN(ICE_13),
    .OUTPUT_ENABLE(1'b0),
    .D_OUT_0(1'b0),
    .D_IN_0()
  );
  
  // SRAM interface signals
  wire [15:0] sram_pins_din;
  wire [15:0] sram_pins_dout;
  wire sram_pins_drive;  // Output from sys - unused on pico-ice (no external SRAM)
  wire RAMOE, RAMWE, RAMCS, RAMLB, RAMUB;
  
  // Data multiplexer: return data based on what's selected
  assign sram_pins_din = pad_sel ? pad_data_out :
                         (rom_sel || grom_sel) ? flash_rom_data :
                         16'h0000;
  
  // Ensure PSRAM chip select stays high (we're not using PSRAM yet)
  assign ICE_37 = 1'b1;  // SRAM_SS - PSRAM chip select (active low, keep high)

  sys #(.uart_divider(43)) ti994a(  // 10 MHz / 230400 baud = 43
      .clk(sys_clk),      // Use 10 MHz system clock for CPU and logic  
      .pixel_clk(pixel_clk), // Use 40 MHz pixel clock for VDP
      .LED(LED_R), 

      .tms9902_tx(1'b1), // these are reversed in sys.v module
      .tms9902_rx(open),

      .RAMOE(RAMOE), 
      .RAMWE(RAMWE), 
      .RAMCS(RAMCS), 
      .RAMLB(RAMLB), 
      .RAMUB(RAMUB),
      .ADR(sys_addr),         // Word address output from sys
      .sram_pins_din(sram_pins_din), 
      .sram_pins_dout(sram_pins_dout),
      .sram_pins_drive(sram_pins_drive),
      .memory_busy(memory_busy),        // Signal CPU to wait during SPI flash read
      .use_memory_busy(use_memory_busy), // Enable wait state generation
      .red(red), 
      .green(green), 
      .blue(blue), 
      .hsync(hsync), 
      .vsync(vsync),
      .cpu_reset_switch_n(ICE_10),  // ICE_10 is the user button, active low  
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
      // External bootloader interface (not used on pico-ice, tie off)
      .xbootloader_addr(32'h00000000),
      .xbootloader_read_rq(1'b0),
      .xbootloader_read_ack(),      // unconnected
      .xbootloader_din(),           // unconnected
      .xbootloader_write_rq(1'b0),
      .xbootloader_write_ack(),     // unconnected
      .xbootloader_dout(8'h00),
      // Misc
      .vde(vde),                    // Video display enable (active area)
      .ps2clk(1'b0), 
      .ps2dat(1'b0),

      .f1_pressed(),                // unconnected for now
      .cursor_keys_pressed(),       // unconnected for now
      .audio()                      // unconnected for now
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

wire [7:4] r, g, b;
assign r[7:4] = red;
assign g[7:4] = green;
assign b[7:4] = blue;
wire vga_hs = hsync;
wire vga_vs = vsync;
wire vga_de = vde;


SB_IO #(
  .PIN_TYPE(6'b01_0000)  // PIN_OUTPUT_DDR
) dvi_clk_iob (
  //.PACKAGE_PIN (P1B2),  // icebreaker
  .PACKAGE_PIN (ICE_38),  // pico-ice2
  .D_OUT_0     (1'b0),
  .D_OUT_1     (1'b1),
  .OUTPUT_CLK  (pixel_clk)
);

SB_IO #(
  .PIN_TYPE(6'b01_0100)  // PIN_OUTPUT_REGISTERED
) dvi_data_iob [14:0] (
  .PACKAGE_PIN ({
    // pico-ice2
    ICE_4,  ICE_3,  ICE_2, ICE_48, ICE_47, ICE_46, ICE_45, ICE_44, // R3,R2,R1,R0,G3,G2,G1,G0
    ICE_43, ICE_42, ICE_36, ICE_34, ICE_32, ICE_31, ICE_28         // B3,B2,B1,B0,DE,HS,VS

    // Icebreaker
    // P1A1,   P1A2,   P1A3,   P1A4,   P1A7,   P1A8,   P1A9,   P1A10,
    // P1B1,           P1B3,   P1B4,   P1B7,   P1B8,   P1B9,   P1B10
    } ),
  .D_OUT_0     ({r[7],   r[5],   g[7],   g[5],   r[6],   r[4],   g[6],   g[4],
                 b[7],           b[4],   b[6],   b[5],  vga_de, vga_hs,   vga_vs}),
  .OUTPUT_CLK  (pixel_clk)
);


endmodule

