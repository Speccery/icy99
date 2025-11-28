# Makefile for pico-ice board with icy99 TI-99/4A implementation
# Author: Erik Piehl
# Adapted from my board-ulx3s/Makefile
# This is a very small FPGA compared to the ECP5 chips.
# Therefore LCD, or OSD support is included. Also other things may be cut if needed.
# There is not enough internal block RAM for ROM memories, so an external SPI flash is used for that.

# APIO package manager paths 
# YOSYSPATH := $(shell echo $(HOME)/.apio/packages/tools-oss-cad-suite/bin)
YOSYSPATH := $(shell echo $(HOME)/.apio/packages/oss-cad-suite/bin)
export YOSYSPATH

# Build options. For pico-ice, SDRAM_SUPPORT means support for external PSRAM chip.
SDRAM_SUPPORT ?= 0

# Get hostname for build directory (like FleaFPGA Makefile)
HOSTNAME := $(shell hostname)

# Define compilation flags
#  -DUSE_SPRAM_FOR_VRAM: Use iCE40UP5K SPRAM for VDP video RAM (32KB available)
#  Size reduction for iCE40UP5K: TRACEBUFFER and TMS9902_SUPPORT already disabled in sys.v
#  Keep serloader (useful for debugging and keyboard input)
#  Keep PCIR_SUPPORT in tms9900.v (useful for debugging before video works)

# Synthesis without CPU
# DEFINES = -DUSE_SPRAM_FOR_VRAM -DFORCE_CPU_RESET
# Synthesis with CPU
DEFINES = -DUSE_SPRAM_FOR_VRAM -DTMS9918_NO_EXTENDED_REGS_READ

ifeq ($(SDRAM_SUPPORT),1)
    DEFINES += -DUSE_SDRAM
    PROJ = pico_ice_sdram
else
    PROJ = pico_ice_nosdram
endif

# Target files
TOP_MODULE = top_pico_ice
VERILOG_FILES = \
	$(TOP_MODULE).v \
	spi_flash_rom.v \
    ../src/dvi.v \
    ../src/ram2.v \
    ../src/sys.v \
    ../src/tms9900.v \
    ../src/alu9900.v \
    ../src/tms9902.v \
    ../src/erik_pll.v \
    ../src/tms9918.v \
    ../src/vga_sync.v \
    ../src/xmemctrl.v \
    ../src/gromext.v \
    ../src/serloader.v \
    ../src/serial_rx.v \
    ../src/serial_tx.v \
    ../src/spi_slave.v \
    ../src/tms9901.v \
    ../src/dualport_par.v \
    ../src/ps2kb.v \
    ../src/tms9919.v \
    ../src/pager612.v \
    ../lcd/ram_source.v 

# ECP5 device (ULX3S uses ECP5-85F - the largest chip in BGA381 package)
DEVICE = --up5k --package sg48

# Build directories
BUILD_DIR = $(HOSTNAME)
BITSTREAM = $(BUILD_DIR)/$(PROJ).bit

# Default target
all: $(BUILD_DIR)/$(PROJ).uf2

# JSON synthesis
$(BUILD_DIR)/$(PROJ).json: $(VERILOG_FILES) | $(BUILD_DIR)
	@echo "Synthesizing design with Yosys (ABC9 optimization for area)..."
	cd $(BUILD_DIR) && $(YOSYSPATH)/yosys -q -p "synth_ice40 -abc9 -device u -json $(PROJ).json" $(DEFINES) $(addprefix ../,$(VERILOG_FILES))

# Place and route
$(BUILD_DIR)/$(PROJ)_out.asc: $(BUILD_DIR)/$(PROJ).json pico_ice.pcf
	@echo "Place and route with NextPNR (relaxed timing for tight fit)..."
	$(YOSYSPATH)/nextpnr-ice40 $(DEVICE) --json $(BUILD_DIR)/$(PROJ).json --pcf pico_ice.pcf --asc $@ --placer heap --seed 1 --ignore-loops

# Generate bitstream
$(BITSTREAM): $(BUILD_DIR)/$(PROJ)_out.asc
	@echo "Generating bitstream with icepack..."
	rm -f $@
	# -s flag below keeps the SPI Flash chip powered on after programming. Without the chip
	# has to be woken up with "0xAB – Release from Deep Power-Down".
	$(YOSYSPATH)/icepack -s $< $@

# ROM/GROM files
# ROM_FILE = ../roms/994aROM.Bin
ROM_FILE = ../boot/boot99105_ti994a.bin
GROM_FILE = ../roms/994AGROM.Bin

# Flash memory layout:
# 0x000000 - 0x03FFFF (256KB): FPGA bitstream (padded)
# 0x040000 - 0x041FFF (8KB):   Console ROM
# 0x042000 - 0x047FFF (24KB):  Console GROM  
# 0x048000 - 0x04FFFF (32KB):  Cartridge ROM space (optional)
FLASH_SIZE = 262144
ROM_OFFSET = 262144
GROM_OFFSET = 270336

# Combined bitstream with ROM data
$(BUILD_DIR)/$(PROJ)_combined.bin: $(BITSTREAM) $(ROM_FILE) $(GROM_FILE)
	@echo "Creating combined flash image with ROM data..."
	@# Start with the bitstream
	cp $(BITSTREAM) $@
	@# Pad to 256KB (FLASH_SIZE bytes)
	@CURRENT_SIZE=$$(stat -f%z $@ 2>/dev/null || stat -c%s $@ 2>/dev/null); \
	PADDING=$$(($(FLASH_SIZE) - $$CURRENT_SIZE)); \
	if [ $$PADDING -gt 0 ]; then \
		dd if=/dev/zero bs=1 count=$$PADDING >> $@ 2>/dev/null; \
	fi
	@# Append Console ROM (8KB at offset 256KB)
	cat $(ROM_FILE) >> $@
	@# Pad ROM 8 K if it is smaller
	@ROM_SIZE=$$(stat -f%z $(ROM_FILE) 2>/dev/null || stat -c%s $(ROM_FILE) 2>/dev/null); \
	ROM_PADDING=$$((8192 - $$ROM_SIZE)); \
	if [ $$ROM_PADDING -gt 0 ]; then \
		dd if=/dev/zero bs=1 count=$$ROM_PADDING >> $@ 2>/dev/null; \
	fi
	@# Append Console GROM (24KB)
	cat $(GROM_FILE) >> $@
	@echo "Combined image size: $$(stat -f%z $@ 2>/dev/null || stat -c%s $@) bytes"

$(BUILD_DIR)/$(PROJ).uf2: $(BUILD_DIR)/$(PROJ)_combined.bin
	rm -f $@	
	bin2uf2 -o $@ $<	

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)


# Clean build files for current configuration
clean:
	rm -f $(BUILD_DIR)/$(PROJ).json
	rm -f $(BUILD_DIR)/$(PROJ)_out.cfg
	rm -f $(BITSTREAM)

# Clean all build files (both SDRAM and non-SDRAM)
cleanall:
	rm -rf $(BUILD_DIR)

# Show resource usage
resource-usage: $(BUILD_DIR)/$(PROJ)_out.asc
	@echo "Resource utilization:"
	@grep -A 20 "Device utilisation:" $(BUILD_DIR)/nextpnr.log || echo "Run place and route first"

# Build without SDRAM support
no-sdram:
	$(MAKE) SDRAM_SUPPORT=0

# Build with SDRAM support (default)
sdram:
	$(MAKE) SDRAM_SUPPORT=1

reset:
	../tools/serialtool -p 1000008 FC
	../tools/serialtool -p 1000008 FF

enter1:
	../tools/serialtool -p 1000005 ef
	../tools/serialtool -p 1000005 ff
	
enter2:
	../tools/serialtool -p 1000001 ef
	../tools/serialtool -p 1000001 ff

init9918:
	@# TMS9918 register write protocol: DATA first, then (0x80 | register_number)
	@# we write the following register values: 00, E0, F0, 0E, F9, 86, F8, 01
	@../tools/serialtool -p 800002 00 # value 00
	@../tools/serialtool -p 800002 80 # register 0 = 0x80
	@../tools/serialtool -p 800002 E0 # value E0
	@../tools/serialtool -p 800002 81 # register 1 = 0x81
	@../tools/serialtool -p 800002 F0 # value F0
	@../tools/serialtool -p 800002 82 # register 2 = 0x82
	@../tools/serialtool -p 800002 0E # value 0E
	@../tools/serialtool -p 800002 83 # register 3 = 0x83
	@../tools/serialtool -p 800002 F9 # value F9
	@../tools/serialtool -p 800002 84 # register 4 = 0x84
	@../tools/serialtool -p 800002 86 # value 86
	@../tools/serialtool -p 800002 85 # register 5 = 0x85
	@../tools/serialtool -p 800002 F8 # value F8
	@../tools/serialtool -p 800002 86 # register 6 = 0x86
	@../tools/serialtool -p 800002 04 # value 04
	@../tools/serialtool -p 800002 87 # register 7 = 0x87

set_vdp_addr_wr:
	# Set VDP address to 0 for writes
	../tools/serialtool -p 800002 00 # low byte
	../tools/serialtool -p 800002 40 # high byte + write command

set_vdp_addr_rd:
	# Set VDP address to 0 for reads
	../tools/serialtool -p 800002 00 # low byte
	../tools/serialtool -p 800002 00 # high byte + read command


load_parsec:
	# Parsec ROM
	../tools/serialtool -w ../dev-sd/cart/parsecc.bin 200000 8192
	# Parsec GROM
	../tools/serialtool -w ../dev-sd/grom/parsecg.bin 16000 24576


# Show help
help:
	@echo "ULX3S icy99 TI-99/4A Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build bitstream (default)"
	@echo "  clean      - Clean current build files"
	@echo "  cleanall   - Clean all build files"
	@echo "  sdram      - Build with SDRAM support (default)"
	@echo "  no-sdram   - Build without SDRAM support"
	@echo "  help       - Show this help"
	@echo ""
	@echo "Options:"
	@echo "  SDRAM_SUPPORT=1|0      - Enable/disable SDRAM (default: 0)"
	@echo ""
	@echo "Examples:"
	@echo "  make SDRAM_SUPPORT=1 - Build with SDRAM"

.PHONY: all prog ujprog clean cleanall resource-usage no-sdram sdram help
