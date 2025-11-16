// spi_flash_reader.v
// EP 2025-11-16
// Simple SPI flash reader for iCE40 FPGA to access ROM data stored in flash
// This module provides read-only access to data stored beyond the bitstream in flash memory
//
// The iCE40 FPGA boots from flash, so we can store additional data (ROMs) after the bitstream.
// This module uses standard SPI read commands to access that data.
//
// Memory map (example):
// 0x000000 - 0x03FFFF: FPGA bitstream (256KB)
// 0x040000 - 0x041FFF: Console ROM (8KB)
// 0x042000 - 0x047FFF: Console GROM (24KB)

module spi_flash_reader #(
    parameter FLASH_BASE_ADDR = 24'h040000  // Base address in flash where ROM data starts
)(
    input wire clk,
    input wire reset,
    
    // Read interface
    input wire [15:0] read_addr,        // 16-bit address from CPU (byte address)
    input wire read_enable,              // Start read operation
    output reg [7:0] read_data,         // Data output
    output reg read_ready,              // Data is valid
    output reg busy,                    // Operation in progress
    
    // SPI Flash pins
    output reg flash_csn,               // Chip select (active low)
    output reg flash_clk,               // SPI clock
    output reg flash_mosi,              // Master out, slave in
    input wire flash_miso               // Master in, slave out
);

    // SPI Flash commands
    localparam CMD_READ = 8'h03;        // Standard read command
    
    // State machine
    localparam STATE_IDLE       = 4'd0;
    localparam STATE_CMD        = 4'd1;
    localparam STATE_ADDR_HIGH  = 4'd2;
    localparam STATE_ADDR_MID   = 4'd3;
    localparam STATE_ADDR_LOW   = 4'd4;
    localparam STATE_READ_DATA  = 4'd5;
    localparam STATE_DONE       = 4'd6;
    
    reg [3:0] state;
    reg [7:0] bit_counter;
    reg [23:0] flash_addr;
    reg [7:0] tx_byte;
    reg [7:0] rx_byte;
    
    // Clock divider for SPI clock (divide system clock by 4 for conservative timing)
    reg [1:0] clk_div;
    wire spi_clk_en = (clk_div == 2'b00);
    
    always @(posedge clk) begin
        if (reset) begin
            clk_div <= 2'b00;
        end else begin
            clk_div <= clk_div + 1'b1;
        end
    end
    
    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_IDLE;
            flash_csn <= 1'b1;
            flash_clk <= 1'b0;
            flash_mosi <= 1'b0;
            read_ready <= 1'b0;
            busy <= 1'b0;
            bit_counter <= 8'd0;
            read_data <= 8'h00;
        end else if (spi_clk_en) begin
            case (state)
                STATE_IDLE: begin
                    flash_csn <= 1'b1;
                    flash_clk <= 1'b0;
                    read_ready <= 1'b0;
                    busy <= 1'b0;
                    
                    if (read_enable) begin
                        // Calculate flash address: base + read_addr
                        flash_addr <= FLASH_BASE_ADDR + {8'h00, read_addr};
                        state <= STATE_CMD;
                        flash_csn <= 1'b0;  // Assert chip select
                        tx_byte <= CMD_READ;
                        bit_counter <= 8'd7;
                        busy <= 1'b1;
                    end
                end
                
                STATE_CMD: begin
                    // Send READ command (8 bits)
                    flash_mosi <= tx_byte[bit_counter];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk && bit_counter == 8'd0) begin
                        // Command sent, move to address phase
                        state <= STATE_ADDR_HIGH;
                        tx_byte <= flash_addr[23:16];
                        bit_counter <= 8'd7;
                    end else if (flash_clk) begin
                        bit_counter <= bit_counter - 1'b1;
                    end
                end
                
                STATE_ADDR_HIGH: begin
                    // Send high byte of address
                    flash_mosi <= tx_byte[bit_counter];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk && bit_counter == 8'd0) begin
                        state <= STATE_ADDR_MID;
                        tx_byte <= flash_addr[15:8];
                        bit_counter <= 8'd7;
                    end else if (flash_clk) begin
                        bit_counter <= bit_counter - 1'b1;
                    end
                end
                
                STATE_ADDR_MID: begin
                    // Send middle byte of address
                    flash_mosi <= tx_byte[bit_counter];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk && bit_counter == 8'd0) begin
                        state <= STATE_ADDR_LOW;
                        tx_byte <= flash_addr[7:0];
                        bit_counter <= 8'd7;
                    end else if (flash_clk) begin
                        bit_counter <= bit_counter - 1'b1;
                    end
                end
                
                STATE_ADDR_LOW: begin
                    // Send low byte of address
                    flash_mosi <= tx_byte[bit_counter];
                    flash_clk <= ~flash_clk;
                    
                    if (flash_clk && bit_counter == 8'd0) begin
                        state <= STATE_READ_DATA;
                        bit_counter <= 8'd7;
                        rx_byte <= 8'h00;
                    end else if (flash_clk) begin
                        bit_counter <= bit_counter - 1'b1;
                    end
                end
                
                STATE_READ_DATA: begin
                    // Read data byte
                    flash_clk <= ~flash_clk;
                    
                    if (~flash_clk) begin
                        // Sample on rising edge of flash_clk (falling edge of our clock toggle)
                        rx_byte <= {rx_byte[6:0], flash_miso};
                        
                        if (bit_counter == 8'd0) begin
                            state <= STATE_DONE;
                            read_data <= {rx_byte[6:0], flash_miso};
                        end else begin
                            bit_counter <= bit_counter - 1'b1;
                        end
                    end
                end
                
                STATE_DONE: begin
                    flash_csn <= 1'b1;  // Deassert chip select
                    flash_clk <= 1'b0;
                    read_ready <= 1'b1;
                    state <= STATE_IDLE;
                end
                
                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
