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

module spi_flash_rom(
    input wire clk,
    input wire reset,
    
    // SRAM-style interface (compatible with sys.v ADR/data bus)
    input wire [22:0] addr,             // 23-bit word address from sys.v
    input wire rom_sel,                 // ROM selected (0x0000-0x1FFF, 8KB)
    input wire grom_sel,                // GROM selected (custom address range)
    output reg [15:0] data_out,         // 16-bit data output
    output reg data_ready,              // Data valid (can be used as ready signal)
    
    // SPI Flash pins (connect to QSPI flash pins)
    output reg flash_csn,               // Chip select (active low)
    output reg flash_clk,               // SPI clock
    output reg flash_mosi,              // Master out, slave in
    input wire flash_miso               // Master in, slave out
);

    // Flash memory offsets (must match Makefile layout)
    localparam FLASH_ROM_BASE  = 24'h040000;  // 256KB offset for ROM
    localparam FLASH_GROM_BASE = 24'h042000;  // 256KB + 8KB offset for GROM
    
    // SPI Flash command
    localparam CMD_READ = 8'h03;              // Standard SPI read command
    
    // State machine states
    localparam [3:0]
        ST_IDLE       = 4'd0,
        ST_CMD        = 4'd1,
        ST_ADDR2      = 4'd2,
        ST_ADDR1      = 4'd3,
        ST_ADDR0      = 4'd4,
        ST_READ_HI    = 4'd5,
        ST_READ_LO    = 4'd6,
        ST_DONE       = 4'd7;
    
    reg [3:0] state;
    reg [3:0] bit_count;
    reg [23:0] flash_addr;
    reg [7:0] shift_reg;
    reg [7:0] data_hi, data_lo;
    reg [1:0] clk_div;
    
    // Generate slower SPI clock (divide by 4 for conservative timing)
    wire spi_tick = (clk_div == 2'b11);
    
    always @(posedge clk) begin
        clk_div <= clk_div + 1'b1;
    end
    
    // Main SPI state machine
    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            flash_csn <= 1'b1;
            flash_clk <= 1'b0;
            flash_mosi <= 1'b0;
            data_ready <= 1'b0;
            data_out <= 16'h0000;
        end else if (spi_tick) begin
            case (state)
                ST_IDLE: begin
                    flash_csn <= 1'b1;
                    flash_clk <= 1'b0;
                    data_ready <= 1'b0;
                    
                    // Start read when ROM or GROM selected
                    if (rom_sel || grom_sel) begin
                        // Calculate flash address based on selection
                        if (rom_sel) begin
                            // ROM: map word address to byte address with offset
                            flash_addr <= FLASH_ROM_BASE + {addr[12:0], 1'b0};
                        end else begin // grom_sel
                            // GROM: map to appropriate flash offset
                            flash_addr <= FLASH_GROM_BASE + {addr[13:0], 1'b0};
                        end
                        
                        flash_csn <= 1'b0;         // Assert CS
                        shift_reg <= CMD_READ;      // Load read command
                        bit_count <= 4'd7;
                        state <= ST_CMD;
                    end
                end
                
                // Send READ command (0x03)
                ST_CMD: begin
                    flash_mosi <= shift_reg[7];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk) begin  // On falling edge of flash_clk
                        shift_reg <= {shift_reg[6:0], 1'b0};
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
                    flash_mosi <= shift_reg[7];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk) begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
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
                    flash_mosi <= shift_reg[7];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk) begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
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
                    flash_mosi <= shift_reg[7];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk) begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
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
                    flash_clk <= ~flash_clk;
                    
                    if (~flash_clk) begin  // Sample on rising edge
                        shift_reg <= {shift_reg[6:0], flash_miso};
                        if (bit_count == 4'd0) begin
                            data_hi <= {shift_reg[6:0], flash_miso};
                            bit_count <= 4'd7;
                            state <= ST_READ_LO;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                
                // Read low byte of 16-bit word
                ST_READ_LO: begin
                    flash_clk <= ~flash_clk;
                    
                    if (~flash_clk) begin  // Sample on rising edge
                        shift_reg <= {shift_reg[6:0], flash_miso};
                        if (bit_count == 4'd0) begin
                            data_lo <= {shift_reg[6:0], flash_miso};
                            state <= ST_DONE;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                        end
                    end
                end
                
                ST_DONE: begin
                    flash_csn <= 1'b1;          // Deassert CS
                    flash_clk <= 1'b0;
                    data_out <= {data_hi, data_lo};  // Output 16-bit word
                    data_ready <= 1'b1;
                    state <= ST_IDLE;
                end
                
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
