// spi_flash_rom.v
// EP 2025-11-16
// SPI Flash ROM reader for pico-ice TI-99/4A implementation
// 
// Reads ROM/GROM data from SPI flash that's appended to the FPGA bitstream.
// Responds to SRAM-style bus interface for compatibility with sys.v
//
// Flash memory layout (set in Makefile):
// 0x000000 - 0x03FFFF (256KB): FPGA bitstream (padded)
// 0x040000 - 0x041FFF (8KB):   Console ROM
// 0x042000 - 0x047FFF (24KB):  Console GROM  
// 0x048000 - 0x04FFFF (32KB):  Reserved for cartridge ROM
//
// Clock strategy:
// - SPI clock (flash_clk) is driven directly by input clk when enabled
// - Two-phase operation per bit: phase 0 = setup data, phase 1 = sample data
// - Each state explicitly manages spi_phase transitions to ensure proper timing
// - Phase 0: MOSI data presented (clock low), Phase 1: MISO sampled (clock high)
// - This allows easy upgrade to higher speed (40 MHz pixel_clk for QSPI)
// - Standard SPI read command (0x03) at 10 MHz, upgradeable to QSPI later

module spi_flash_rom(
    input wire clk,
    input wire reset,
    
    // SRAM-style interface (compatible with sys.v ADR/data bus)
    input wire [22:0] addr,             // 23-bit word address from sys.v
    input wire rom_sel,                 // ROM selected (0x0000-0x1FFF, 8KB)
    input wire grom_sel,                // GROM selected (custom address range)
    output reg [15:0] data_out = 16'h0000,  // 16-bit data output
    output reg data_ready = 1'b0,           // Data valid (can be used as ready signal)
    
    // SPI Flash pins (connect to QSPI flash pins)
    output reg flash_csn = 1'b1,            // Chip select (active low)
    output wire flash_clk,              // SPI clock (gated 5MHz, only during active transaction)
    output reg flash_mosi,              // Master out, slave in
    input wire flash_miso,              // Master in, slave out
    
    // Debug output
    output wire [3:0] debug_state,      // Current state for debugging
    output reg flash_available = 1'b0   // High when flash is ready for access
);

    // Flash memory offsets (must match Makefile layout)
    // DEBUG: Temporarily reading from start of flash (FPGA bitstream) to verify SPI works
    localparam FLASH_ROM_BASE  = 24'h040000;  // 256KB offset for ROM (was 0x040000)
    localparam FLASH_GROM_BASE = 24'h042000;  // 256KB + 8KB offset for GROM (was 0x042000)
    
    // SPI Flash commands
    localparam CMD_READ = 8'h03;              // Standard SPI read command
    localparam CMD_RDID = 8'h9F;              // Read ID command (for testing)
    localparam FLASH_CMD_RELEASE_POWERDOWN = 8'hAB; // Release from power-down command
    
    // State machine states
    localparam [3:0]
        ST_POWERDOWN_RELEASE = 4'd0,
        ST_POWERDOWN_WAIT    = 4'd1,
        ST_IDLE              = 4'd2,
        ST_CMD               = 4'd3,
        ST_ADDR2             = 4'd4,
        ST_ADDR1             = 4'd5,
        ST_ADDR0             = 4'd6,
        ST_READ_HI           = 4'd7,
        ST_READ_LO           = 4'd8,
        ST_DONE              = 4'd9;
    
    reg [3:0] state;
    reg [3:0] bit_count;
    reg [23:0] flash_addr;
    reg [7:0] shift_reg;
    reg [7:0] data_hi, data_lo;
    reg rom_sel_prev, grom_sel_prev;  // Track selection changes

    reg spi_phase;  // 0 = setup data, 1 = sample (for rising edge sampling)
    reg flash_clk_en;  // Enable for SPI clock
    reg flash_miso_sampled;  // Sample MISO on negative edge for better timing

    // 5MHz clock divider (from 10MHz system clock)
    reg clk_div;
    always @(posedge clk) begin
        if (reset || !flash_clk_en) begin
            clk_div <= 1'b0;
        end else begin
            clk_div <= ~clk_div;
        end
    end

    // SPI clock: 5MHz only when enabled, otherwise low
    assign flash_clk = (flash_clk_en) ? clk_div : 1'b0;

    assign debug_state = state;  // Expose state for debugging

    // Sample MISO on negative edge of system clock for better timing margin
    always @(negedge clk) begin
        flash_miso_sampled <= flash_miso;
    end
    
    // Main SPI state machine
    reg [15:0] powerdown_wait_count;
    always @(posedge clk) begin
        if (reset) begin
            state <= ST_POWERDOWN_RELEASE;
            flash_csn <= 1'b1;
            flash_clk_en <= 1'b0;
            flash_mosi <= 1'b0;
            data_ready <= 1'b0;
            data_out <= 16'h0000;
            rom_sel_prev <= 1'b0;
            grom_sel_prev <= 1'b0;
            spi_phase <= 1'b0;
            flash_available <= 1'b0;
            powerdown_wait_count <= 16'd0;
        end else begin
            // Track selection changes - clear data_ready on new access
            rom_sel_prev <= rom_sel;
            grom_sel_prev <= grom_sel;

            // Clear data_ready when we see a new selection (rising edge)
            if ((rom_sel && !rom_sel_prev) || (grom_sel && !grom_sel_prev)) begin
                data_ready <= 1'b0;
            end

            case (state)
                // Release powerdown sequence
                ST_POWERDOWN_RELEASE: begin
                    flash_csn <= 1'b0;          // Assert CS
                    flash_clk_en <= 1'b1;       // Enable SPI clock
                    shift_reg <= FLASH_CMD_RELEASE_POWERDOWN;
                    bit_count <= 4'd7;
                    spi_phase <= 1'b0;
                    flash_available <= 1'b0;
                    state <= ST_POWERDOWN_WAIT;
                end
                ST_POWERDOWN_WAIT: begin
                    // Send release powerdown command (single byte)
                    if (spi_phase == 1'b0) begin
                        flash_mosi <= shift_reg[7];
                        spi_phase <= 1'b1;
                    end else begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        spi_phase <= 1'b0;
                        if (bit_count == 4'd0) begin
                            flash_csn <= 1'b1;      // Deassert CS
                            flash_clk_en <= 1'b0;   // Disable SPI clock
                            powerdown_wait_count <= 16'd50000; // Wait ~5ms @ 10MHz
                            state <= ST_IDLE;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                ST_IDLE: begin
                    // Wait for powerdown release to complete
                    if (powerdown_wait_count != 16'd0) begin
                        powerdown_wait_count <= powerdown_wait_count - 1'b1;
                        flash_available <= 1'b0;
                    end else begin
                        flash_available <= 1'b1;
                        flash_csn <= 1'b1;
                        flash_clk_en <= 1'b0;
                        spi_phase <= 1'b0;
                        // Clear data_ready when selection is removed
                        if (!rom_sel && !grom_sel) begin
                            data_ready <= 1'b0;
                        end
                        // Start read when ROM or GROM selected
                        if ((rom_sel || grom_sel)) begin
                            // Calculate flash address based on selection
                            if (rom_sel) begin
                                flash_addr <= FLASH_ROM_BASE + {addr[12:0], 1'b0};
                            end else begin // grom_sel
                                flash_addr <= FLASH_GROM_BASE + {addr[14:0], 1'b0};
                            end
                            data_ready <= 1'b0;         // Clear ready at start of transaction
                            flash_csn <= 1'b0;          // Assert CS
                            flash_clk_en <= 1'b1;       // Enable SPI clock
                            shift_reg <= CMD_READ;      // Load read command
                            bit_count <= 4'd7;
                            state <= ST_CMD;
                        end
                    end
                end
                // Send READ command (0x03)
                ST_CMD: begin
                    if (spi_phase == 1'b0) begin
                        // Setup phase: present data on MOSI
                        flash_mosi <= shift_reg[7];
                        spi_phase <= 1'b1;  // Next clock will be sample phase
                    end else begin
                        // Sample phase: shift and advance
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        spi_phase <= 1'b0;  // Next clock will be setup phase
                        if (bit_count == 4'd0) begin
                            shift_reg <= flash_addr[23:16];
                            bit_count <= 4'd7;
                            state <= ST_ADDR2;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                // Send address byte 2 (MSB)
                ST_ADDR2: begin
                    if (spi_phase == 1'b0) begin
                        flash_mosi <= shift_reg[7];
                        spi_phase <= 1'b1;
                    end else begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        spi_phase <= 1'b0;
                        if (bit_count == 4'd0) begin
                            shift_reg <= flash_addr[15:8];
                            bit_count <= 4'd7;
                            state <= ST_ADDR1;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                // Send address byte 1
                ST_ADDR1: begin
                    if (spi_phase == 1'b0) begin
                        flash_mosi <= shift_reg[7];
                        spi_phase <= 1'b1;
                    end else begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        spi_phase <= 1'b0;
                        if (bit_count == 4'd0) begin
                            shift_reg <= flash_addr[7:0];
                            bit_count <= 4'd7;
                            state <= ST_ADDR0;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                // Send address byte 0 (LSB)
                ST_ADDR0: begin
                    if (spi_phase == 1'b0) begin
                        flash_mosi <= shift_reg[7];
                        spi_phase <= 1'b1;
                    end else begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        spi_phase <= 1'b0;
                        if (bit_count == 4'd0) begin
                            bit_count <= 4'd7;
                            shift_reg <= 8'h00;
                            state <= ST_READ_HI;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                // Read high byte of 16-bit word
                ST_READ_HI: begin
                    if (spi_phase == 1'b0) begin
                        // Setup phase: just wait (MOSI doesn't matter during read)
                        spi_phase <= 1'b1;
                    end else begin
                        // Sample phase: capture data (sampled on negedge, available now)
                        shift_reg <= {shift_reg[6:0], flash_miso_sampled};
                        spi_phase <= 1'b0;
                        if (bit_count == 4'd0) begin
                            data_hi <= {shift_reg[6:0], flash_miso_sampled};
                            bit_count <= 4'd7;
                            state <= ST_READ_LO;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                // Read low byte of 16-bit word
                ST_READ_LO: begin
                    if (spi_phase == 1'b0) begin
                        // Setup phase: just wait
                        spi_phase <= 1'b1;
                    end else begin
                        // Sample phase: capture data (sampled on negedge, available now)
                        shift_reg <= {shift_reg[6:0], flash_miso_sampled};
                        spi_phase <= 1'b0;
                        if (bit_count == 4'd0) begin
                            data_lo <= {shift_reg[6:0], flash_miso_sampled};
                            state <= ST_DONE;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                ST_DONE: begin
                    flash_csn <= 1'b1;          // Deassert CS
                    flash_clk_en <= 1'b0;       // Disable SPI clock
                    spi_phase <= 1'b0;          // Reset phase
                    data_out <= {data_hi, data_lo};  // Output 16-bit word from flash
                    data_ready <= 1'b1;
                    state <= ST_IDLE;
                end
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end  // else (not reset)
    end  // always @(posedge clk)

endmodule
